function Get-ProjectOwnedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$ProductionOnly
    )

    $directories = @('src', 'scripts', 'tools')
    if (-not $ProductionOnly) { $directories += 'tests' }
    Get-ChildItem -LiteralPath $ProjectRoot -File -ErrorAction Stop |
        Where-Object { $_.Extension -in @('.ps1', '.psd1') }
    foreach ($name in $directories) {
        $directory = Join-Path $ProjectRoot $name
        if (Test-Path -LiteralPath $directory) {
            Get-ChildItem -LiteralPath $directory -Recurse -File -ErrorAction Stop |
                Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') }
        }
    }
}

function Get-DevelopmentDependencyPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][ValidateSet('Pester', 'PSScriptAnalyzer')][string]$Name
    )

    $lock = Import-PowerShellDataFile -LiteralPath (Join-Path $ProjectRoot 'tools\Dependencies.psd1') -ErrorAction Stop
    $dependency = $lock.Modules[$Name]
    $directory = Join-Path $ProjectRoot ('.tools\modules\{0}\{1}' -f $Name, $dependency.Version)
    $manifest = Join-Path $directory "$Name.psd1"
    $stamp = Join-Path $directory '.package-sha512'
    if (-not (Test-Path -LiteralPath $manifest) -or -not (Test-Path -LiteralPath $stamp)) {
        throw "Pinned $Name $($dependency.Version) is missing. Run tools/Install-DevDependencies.ps1 first; testing never downloads dependencies."
    }
    if ((Get-Content -LiteralPath $stamp -Raw -ErrorAction Stop).Trim() -cne $dependency.SHA512) {
        throw "The local $Name package stamp differs from the dependency lock. Inspect .tools before reinstalling."
    }
    $metadata = Import-PowerShellDataFile -LiteralPath $manifest -ErrorAction Stop
    if ([version]$metadata.ModuleVersion -ne [version]$dependency.Version) { throw "Wrong module version for $Name." }
    return $manifest
}

function Import-ProjectDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][ValidateSet('Pester', 'PSScriptAnalyzer')][string]$Name
    )

    $manifest = Get-DevelopmentDependencyPath -ProjectRoot $ProjectRoot -Name $Name
    Import-Module -Name $manifest -Force -Global -ErrorAction Stop
}

function Get-ProjectPesterConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$Coverage
    )

    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $ProjectRoot 'tests'
    $config.Run.PassThru = $true
    $config.Run.Exit = $false
    $config.TestRegistry.Enabled = $false
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = Join-Path $OutputPath 'tests.xml'
    $config.Output.Verbosity = 'Normal'
    $config.CodeCoverage.Enabled = [bool]$Coverage
    if ($Coverage) {
        $config.CodeCoverage.Path = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src') -Recurse -File |
            Where-Object { $_.Extension -eq '.ps1' } | Select-Object -ExpandProperty FullName)
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
        $config.CodeCoverage.OutputPath = Join-Path $OutputPath 'coverage.xml'
        $quality = Import-PowerShellDataFile -LiteralPath (Join-Path $ProjectRoot 'tools\Quality.psd1') -ErrorAction Stop
        $config.CodeCoverage.CoveragePercentTarget = $quality.CoverageMinimumPercent
    }
    return $config
}

function Assert-ProjectTestResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result)

    foreach ($property in @('FailedCount', 'FailedContainersCount', 'TotalCount', 'PassedCount', 'SkippedCount', 'NotRunCount')) {
        if ($null -eq $Result.$property) { throw "Test result is missing '$property'." }
    }
    if ($Result.FailedCount -gt 0 -or $Result.FailedContainersCount -gt 0 -or
        $Result.TotalCount -eq 0 -or $Result.PassedCount -eq 0 -or
        $Result.SkippedCount -gt 0 -or $Result.NotRunCount -gt 0) {
        throw "Test gate failed: passed=$($Result.PassedCount), failed=$($Result.FailedCount), containers=$($Result.FailedContainersCount), skipped=$($Result.SkippedCount), not-run=$($Result.NotRunCount)."
    }
}

function Assert-ProjectCoverageResult {
    [CmdletBinding()]
    param(
        [AllowNull()]$Result,
        [Parameter(Mandatory)][ValidateRange(1, 100)][double]$MinimumPercent
    )

    if ($null -eq $Result -or $null -eq $Result.CommandsAnalyzedCount -or
        $Result.CommandsAnalyzedCount -le 0 -or $null -eq $Result.CoveragePercent) {
        throw 'Coverage gate failed: missing or empty instrumented-source result.'
    }
    $percent = [double]$Result.CoveragePercent
    if ([double]::IsNaN($percent) -or [double]::IsInfinity($percent) -or
        $percent -lt $MinimumPercent -or $percent -gt 100) {
        throw "Coverage gate failed: $percent percent; required $MinimumPercent percent."
    }
}

function Invoke-ProjectLint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputPath
    )

    Import-ProjectDependency -ProjectRoot $ProjectRoot -Name PSScriptAnalyzer
    $findings = @(foreach ($file in (Get-ProjectOwnedFile -ProjectRoot $ProjectRoot -ProductionOnly)) {
        Invoke-ScriptAnalyzer -Path $file.FullName -Settings (Join-Path $ProjectRoot 'PSScriptAnalyzerSettings.psd1') -ErrorAction Stop
    })
    ConvertTo-Json -InputObject @($findings | Select-Object RuleName, Severity, Message, ScriptName, Line, Column) -Depth 5 |
        Set-Content -LiteralPath (Join-Path $OutputPath 'lint.json') -Encoding UTF8
    if ($findings.Count -gt 0) {
        $findings | Format-Table ScriptName, Line, RuleName, Message -AutoSize | Out-Host
        throw "Lint gate failed with $($findings.Count) diagnostics. See lint.json."
    }
}

function Invoke-ProjectValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$Coverage,
        [switch]$SkipLint
    )

    Import-ProjectDependency -ProjectRoot $ProjectRoot -Name Pester
    $null = New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop
    [pscustomobject]@{
        PowerShell = $PSVersionTable.PSVersion.ToString()
        Pester = (Get-Module Pester).Version.ToString()
        Platform = [Environment]::OSVersion.VersionString
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputPath 'environment.json') -Encoding UTF8

    $lintFailure = $null
    if (-not $SkipLint) {
        try { Invoke-ProjectLint -ProjectRoot $ProjectRoot -OutputPath $OutputPath }
        catch { $lintFailure = $_ }
    }
    $configuration = Get-ProjectPesterConfiguration -ProjectRoot $ProjectRoot -OutputPath $OutputPath -Coverage:$Coverage
    $result = Invoke-Pester -Configuration $configuration
    Assert-ProjectTestResult -Result $result
    if ($Coverage) {
        Assert-ProjectCoverageResult -Result $result.CodeCoverage -MinimumPercent $configuration.CodeCoverage.CoveragePercentTarget.Value
    }
    if ($null -ne $lintFailure) { $PSCmdlet.ThrowTerminatingError($lintFailure) }
    return $result
}
