BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'tools\ProjectTools.ps1')

    function Invoke-LiteralToolingChild {
        param([hashtable]$Data, [scriptblock]$Script)
        $Data.ProjectRoot = $ProjectRoot
        $Data.ProjectTools = Join-Path $ProjectRoot 'tools\ProjectTools.ps1'
        $json = ConvertTo-Json -InputObject $Data -Compress -Depth 5
        $encodedData = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        $command = "`$ErrorActionPreference = 'Stop'`n`$fixture = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedData')) | ConvertFrom-Json`n. `$fixture.ProjectTools`n" + $Script.ToString()
        $executable = Join-Path $PSHOME 'powershell.exe'
        if ($PSVersionTable.PSEdition -eq 'Core') { $executable = Join-Path $PSHOME 'pwsh.exe' }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $executable
        $start.Arguments = '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $start.WorkingDirectory = $ProjectRoot
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.CreateNoWindow = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(90000)) { $process.Kill(); throw 'Literal tooling fixture timed out.' }
            $diagnostic = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
            $diagnostic = [regex]::Replace($diagnostic, '<[^>]*>|_x001B_\[[0-9;]*m|\x1b\[[0-9;]*m', '')
            $diagnostic = [regex]::Replace($diagnostic, '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '')
            if ($diagnostic.Length -gt 3000) { $diagnostic = $diagnostic.Substring($diagnostic.Length - 3000) }
            [pscustomobject]@{ ExitCode = $process.ExitCode; Error = $diagnostic }
        } finally { $process.Dispose() }
    }

    function New-LiteralToolingModule {
        param([string]$Root, [string]$Value)
        $moduleRoot = Join-Path $Root '.tools\modules\PSScriptAnalyzer\1.24.0'
        [void][IO.Directory]::CreateDirectory((Join-Path $Root 'tools'))
        [void][IO.Directory]::CreateDirectory($moduleRoot)
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\Dependencies.psd1') -Destination (Join-Path $Root 'tools\Dependencies.psd1')
        $lock = Import-PowerShellDataFile -LiteralPath (Join-Path $Root 'tools\Dependencies.psd1')
        Set-Content -LiteralPath (Join-Path $moduleRoot '.package-sha512') -Value $lock.Modules.PSScriptAnalyzer.SHA512
        Set-Content -LiteralPath (Join-Path $moduleRoot 'PSScriptAnalyzer.psd1') -Value "@{ RootModule = 'PSScriptAnalyzer.psm1'; ModuleVersion = '1.24.0'; FunctionsToExport = @('Get-LiteralToolingProbe') }"
        Set-Content -LiteralPath (Join-Path $moduleRoot 'PSScriptAnalyzer.psm1') -Value "[IO.File]::WriteAllText((Join-Path `$PSScriptRoot 'executed.txt'), '$Value'); function Get-LiteralToolingProbe { '$Value' }; Export-ModuleMember -Function Get-LiteralToolingProbe"
    }
}

Describe 'Literal tooling paths' {
    BeforeEach {
        $script:FixtureParent = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:LiteralRoot = Join-Path $script:FixtureParent 'project[x]'
        $script:DecoyRoot = Join-Path $script:FixtureParent 'projectx'
        $script:Output = Join-Path $script:FixtureParent 'output'
        foreach ($root in @($script:LiteralRoot, $script:DecoyRoot)) {
            foreach ($directory in @('tools', 'tests', 'src')) {
                [void][IO.Directory]::CreateDirectory((Join-Path $root $directory))
            }
            Set-Content -LiteralPath (Join-Path $root 'tools\Quality.psd1') -Value '@{ CoverageMinimumPercent = 90 }'
        }
        [void][IO.Directory]::CreateDirectory($script:Output)
        $script:ObservedPath = Join-Path $script:Output 'observed.json'
    }

    It 'imports the validated harmless pinned module in an isolated process at an unambiguous path' {
        New-LiteralToolingModule -Root $script:DecoyRoot -Value 'exact pinned fixture'
        $child = Invoke-LiteralToolingChild -Data @{ Root = $script:DecoyRoot; Observed = $script:ObservedPath } -Script {
            Import-ProjectDependency -ProjectRoot $fixture.Root -Name PSScriptAnalyzer
            $module = Get-Module PSScriptAnalyzer
            $command = Get-Command Get-LiteralToolingProbe
            @{ Value = Get-LiteralToolingProbe; Path = $module.Path; Version = $module.Version.ToString(); CommandPath = $command.Module.Path } |
                ConvertTo-Json | Set-Content -LiteralPath $fixture.Observed
        }
        $child.ExitCode | Should -Be 0 -Because $child.Error
        $observed = Get-Content -LiteralPath $script:ObservedPath -Raw | ConvertFrom-Json
        $observed.Value | Should -Be 'exact pinned fixture'
        $observed.Path | Should -Be (Join-Path $script:DecoyRoot '.tools\modules\PSScriptAnalyzer\1.24.0\PSScriptAnalyzer.psm1')
        $observed.CommandPath | Should -Be $observed.Path
        $observed.Version | Should -Be '1.24.0'
    }

    It 'rejects an ambiguous manifest before importing either the literal module or its matching decoy' -ForEach @(
        @{ RootName = 'project[x]' }, @{ RootName = 'project]x' }, @{ RootName = 'project`x' }
    ) {
        $script:LiteralRoot = Join-Path $script:FixtureParent $RootName
        New-LiteralToolingModule -Root $script:LiteralRoot -Value 'literal fixture'
        New-LiteralToolingModule -Root $script:DecoyRoot -Value 'wrong decoy fixture'
        Get-DevelopmentDependencyPath -ProjectRoot $script:LiteralRoot -Name PSScriptAnalyzer |
            Should -Be (Join-Path $script:LiteralRoot '.tools\modules\PSScriptAnalyzer\1.24.0\PSScriptAnalyzer.psd1')
        $child = Invoke-LiteralToolingChild -Data @{ Root = $script:LiteralRoot; Observed = $script:ObservedPath } -Script {
            $message = $null
            try { Import-ProjectDependency -ProjectRoot $fixture.Root -Name PSScriptAnalyzer }
            catch { $message = $_.Exception.Message }
            @{
                Message = $message
                Modules = @(Get-Module PSScriptAnalyzer).Count
                Commands = @(Get-Command Get-LiteralToolingProbe -ErrorAction SilentlyContinue).Count
            } | ConvertTo-Json | Set-Content -LiteralPath $fixture.Observed
        }
        $child.ExitCode | Should -Be 0 -Because $child.Error
        $observed = Get-Content -LiteralPath $script:ObservedPath -Raw | ConvertFrom-Json
        $observed.Message | Should -Match 'does not support wildcard or backtick'
        $observed.Message | Should -Match 'Move the project'
        $observed.Modules | Should -Be 0
        $observed.Commands | Should -Be 0
        foreach ($root in @($script:LiteralRoot, $script:DecoyRoot)) {
            Test-Path -LiteralPath (Join-Path $root '.tools\modules\PSScriptAnalyzer\1.24.0\executed.txt') | Should -BeFalse
        }
    }

    It 'selects all literal test files exactly and excludes suffix lookalikes' {
        foreach ($relative in @('tests\One.Tests.ps1', 'tests\Two.Tests.ps1', 'tests\Not.Tests.ps1xml', 'tests\Helper.ps1')) {
            Set-Content -LiteralPath (Join-Path $script:DecoyRoot $relative) -Value '# literal fixture'
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $script:DecoyRoot 'tests\nested'))
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'tests\nested\Three.Tests.ps1') -Value '# nested fixture'
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'tests\Unselected.Tests.ps1') -Value '# sibling fixture'
        $config = Get-ProjectPesterConfiguration -ProjectRoot $script:DecoyRoot -OutputPath $script:Output
        $selected = @($config.Run.Path.Value | ForEach-Object { (Get-Item -Path $_ -ErrorAction Stop).FullName })
        $expected = @('tests\One.Tests.ps1', 'tests\Two.Tests.ps1', 'tests\nested\Three.Tests.ps1') |
            ForEach-Object { Join-Path $script:DecoyRoot $_ }
        $selected.Count | Should -Be 3
        @($selected | Where-Object { $_ -notin $expected }).Count | Should -Be 0
    }

    It 'rejects bracketed test paths before real pinned Pester can execute a matching sibling' {
        "Describe 'Literal child fixture' { It 'must not run' { Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'executed.txt') -Value 'literal fixture' } }" |
            Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'tests\Exact[x].Tests.ps1')
        "Describe 'Decoy child fixture' { It 'must not run' { Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'executed.txt') -Value 'wrong sibling fixture' } }" |
            Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'tests\Exactx.Tests.ps1')
        $child = Invoke-LiteralToolingChild -Data @{ Root = $script:LiteralRoot; Output = $script:Output; Observed = $script:ObservedPath } -Script {
            Import-ProjectDependency -ProjectRoot $fixture.ProjectRoot -Name Pester
            $message = $null
            try {
                $config = Get-ProjectPesterConfiguration -ProjectRoot $fixture.Root -OutputPath $fixture.Output
                $config.Output.Verbosity = 'None'
                $null = Invoke-Pester -Configuration $config
            } catch { $message = $_.Exception.Message }
            @{ Message = $message } | ConvertTo-Json | Set-Content -LiteralPath $fixture.Observed
        }
        $child.ExitCode | Should -Be 0 -Because $child.Error
        $observed = Get-Content -LiteralPath $script:ObservedPath -Raw | ConvertFrom-Json
        $observed.Message | Should -Match 'Test discovery does not support wildcard or backtick'
        foreach ($root in @($script:LiteralRoot, $script:DecoyRoot)) {
            Test-Path -LiteralPath (Join-Path $root 'tests\executed.txt') | Should -BeFalse
        }
    }

    It 'measures nonempty exact source at an unambiguous path using real pinned Pester' {
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'src\Value.ps1') -Value "function Get-LiteralCoverageValue { 'literal fixture' }"
        @'
BeforeAll { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Value.ps1') }
Describe 'Coverage child fixture' {
    It 'executes the exact source' { Get-LiteralCoverageValue | Should -Be 'literal fixture' }
}
'@ | Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'tests\Exact.Tests.ps1')
        $child = Invoke-LiteralToolingChild -Data @{ Root = $script:DecoyRoot; Output = $script:Output; Observed = $script:ObservedPath } -Script {
            Import-ProjectDependency -ProjectRoot $fixture.ProjectRoot -Name Pester
            $config = Get-ProjectPesterConfiguration -ProjectRoot $fixture.Root -OutputPath $fixture.Output -Coverage
            $config.Output.Verbosity = 'None'
            $result = Invoke-Pester -Configuration $config
            Assert-ProjectTestResult -Result $result
            Assert-ProjectCoverageResult -Result $result.CodeCoverage -MinimumPercent 90
            @{
                Total = $result.TotalCount
                Percent = $result.CodeCoverage.CoveragePercent
                Analyzed = $result.CodeCoverage.CommandsAnalyzedCount
            } | ConvertTo-Json | Set-Content -LiteralPath $fixture.Observed
        }
        $child.ExitCode | Should -Be 0 -Because $child.Error
        $observed = Get-Content -LiteralPath $script:ObservedPath -Raw | ConvertFrom-Json
        $observed.Total | Should -Be 1
        $observed.Analyzed | Should -BeGreaterThan 0
        $observed.Percent | Should -Be 100
        Get-Content -LiteralPath (Join-Path $script:Output 'coverage.xml') -Raw | Should -Match ([regex]::Escape('Value.ps1'))
    }

    It 'rejects ambiguous source paths before the Pester breakpoint backend can expand them' -ForEach @(
        @{ Name = 'Value[x].ps1' }, @{ Name = 'Value].ps1' }, @{ Name = 'Value`x.ps1' }
    ) {
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'tests\Exact.Tests.ps1') -Value '# fixture'
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot ('src\' + $Name)) -Value "'literal fixture'"
        { Get-ProjectPesterConfiguration -ProjectRoot $script:DecoyRoot -OutputPath $script:Output -Coverage } |
            Should -Throw '*Coverage does not support wildcard or backtick*'
        Test-Path -LiteralPath (Join-Path $script:Output 'coverage.xml') | Should -BeFalse
    }

    It 'rejects coverage under an ambiguous project root before creating a zero-coverage report' {
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'tests\Exact.Tests.ps1') -Value '# fixture'
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'src\Value.ps1') -Value "'literal fixture'"
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'src\Value.ps1') -Value "'wrong sibling fixture'"
        { Get-ProjectPesterConfiguration -ProjectRoot $script:LiteralRoot -OutputPath $script:Output -Coverage } |
            Should -Throw '*Test discovery does not support wildcard or backtick*'
        Test-Path -LiteralPath (Join-Path $script:Output 'coverage.xml') | Should -BeFalse
    }

    It 'fails before Pester can fall back to broad coverage when src is empty or missing' {
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'tests\Exact.Tests.ps1') -Value '# fixture'
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'src\NotSource.ps1xml') -Value '# suffix lookalike'
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'src\Decoy.ps1') -Value "'decoy'"
        { Get-ProjectPesterConfiguration -ProjectRoot $script:DecoyRoot -OutputPath $script:Output -Coverage } |
            Should -Throw '*Coverage discovery failed*'
        Remove-Item -LiteralPath (Join-Path $script:DecoyRoot 'src') -Recurse -Force
        { Get-ProjectPesterConfiguration -ProjectRoot $script:DecoyRoot -OutputPath $script:Output -Coverage } | Should -Throw
    }

    It 'fails closed when the literal tests directory is empty even if its sibling has tests' {
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'tests\Decoy.Tests.ps1') -Value '# decoy'
        { Get-ProjectPesterConfiguration -ProjectRoot $script:LiteralRoot -OutputPath $script:Output } |
            Should -Throw '*Test discovery failed*'
    }

    It 'passes literal source and settings to real pinned ScriptAnalyzer without linting matching decoys' {
        # The real analyzer is imported from the unambiguous checkout in the child;
        # replace only the redundant dependency import to exercise path consumers.
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'PSScriptAnalyzerSettings.psd1') -Value "@{ IncludeRules = @('PSAvoidUsingWriteHost') }"
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'PSScriptAnalyzerSettings.psd1') -Value "@{ IncludeRules = @('PSAvoidUsingInvokeExpression') }"
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'src\Source[x].ps1') -Value "Write-Host 'literal diagnostic'"
        Set-Content -LiteralPath (Join-Path $script:LiteralRoot 'src\Sourcex.ps1') -Value "Write-Output 'local filename decoy'"
        Set-Content -LiteralPath (Join-Path $script:DecoyRoot 'src\Sourcex.ps1') -Value "Write-Output 'sibling decoy'"
        $child = Invoke-LiteralToolingChild -Data @{ Root = $script:LiteralRoot; Output = $script:Output; Observed = $script:ObservedPath } -Script {
            Import-ProjectDependency -ProjectRoot $fixture.ProjectRoot -Name PSScriptAnalyzer
            function Import-ProjectDependency { param($ProjectRoot, $Name) }
            $message = $null
            try { Invoke-ProjectLint -ProjectRoot $fixture.Root -OutputPath $fixture.Output }
            catch { $message = $_.Exception.Message }
            @{ Message = $message } | ConvertTo-Json | Set-Content -LiteralPath $fixture.Observed
        }
        $child.ExitCode | Should -Be 0 -Because $child.Error
        $observed = Get-Content -LiteralPath $script:ObservedPath -Raw | ConvertFrom-Json
        $observed.Message | Should -Match 'Lint gate failed with 1 diagnostics'
        $findings = @(Get-Content -LiteralPath (Join-Path $script:Output 'lint.json') -Raw | ConvertFrom-Json)
        $findings.Count | Should -Be 1
        $findings[0].RuleName | Should -Be 'PSAvoidUsingWriteHost'
        $findings[0].ScriptName | Should -Be 'Source[x].ps1'
    }
}
