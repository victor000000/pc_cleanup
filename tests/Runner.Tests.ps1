BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    function Invoke-RunnerFixture {
        param([string]$Runner, [string]$WorkingDirectory, [string]$PathExt)
        $executable = Join-Path $PSHOME 'powershell.exe'
        if ($PSVersionTable.PSEdition -eq 'Core') { $executable = Join-Path $PSHOME 'pwsh.exe' }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $executable
        $start.Arguments = '-NoProfile -NonInteractive -File "' + $Runner + '"'
        $start.WorkingDirectory = $WorkingDirectory
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.CreateNoWindow = $true
        if ($PSBoundParameters.ContainsKey('PathExt')) { $start.EnvironmentVariables['PATHEXT'] = $PathExt }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            $null = $process.Start()
            if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Synthetic runner fixture timed out.' }
            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $process.StandardOutput.ReadToEnd()
                Error = $process.StandardError.ReadToEnd()
            }
        } finally { $process.Dispose() }
    }
}

Describe 'Fresh-process runner entrypoint' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ('runner [fixture] ' + [guid]::NewGuid())
        $null = New-Item -ItemType Directory -Path (Join-Path $script:FixtureRoot 'tools') -Force
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'Test.ps1') -Destination (Join-Path $script:FixtureRoot 'Test.ps1')
        $script:Stub = Join-Path $script:FixtureRoot 'tools\ProjectTools.ps1'
    }
    It 'resolves its default paths under -File from another working directory' {
        @'
function Invoke-ProjectValidation {
    param($ProjectRoot, $OutputPath, [switch]$Coverage, [switch]$SkipLint)
    @{ Root = $ProjectRoot; Output = $OutputPath } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ProjectRoot 'observed.json')
}
'@ | Set-Content -LiteralPath $script:Stub -Encoding UTF8
        $result = Invoke-RunnerFixture -Runner (Join-Path $script:FixtureRoot 'Test.ps1') -WorkingDirectory $TestDrive
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $observed = Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'observed.json') -Raw | ConvertFrom-Json
        $observed.Root | Should -Be $script:FixtureRoot
        $observed.Output | Should -Be (Join-Path $script:FixtureRoot ('artifacts\ps-' + $PSVersionTable.PSVersion.Major))
    }
    It 'returns a nonzero process exit status when validation fails' {
        "function Invoke-ProjectValidation { throw 'synthetic validation failure' }" | Set-Content -LiteralPath $script:Stub -Encoding UTF8
        $result = Invoke-RunnerFixture -Runner (Join-Path $script:FixtureRoot 'Test.ps1') -WorkingDirectory $TestDrive
        $result.ExitCode | Should -Be 1
        $result.Error | Should -Match 'synthetic validation failure'
    }
    It 'runs a harmless native fixture when inherited PATHEXT omits EXE' {
        @'
function Invoke-ProjectValidation {
    param($ProjectRoot, $OutputPath, [switch]$Coverage, [switch]$SkipLint)
    $output = @(& $env:COMSPEC /d /c echo synthetic-pathext-fixture)
    if ($LASTEXITCODE -ne 0 -or ($output -join '') -ne 'synthetic-pathext-fixture') {
        throw 'The native fixture did not execute.'
    }
    if ('.CPL' -notin ($env:PATHEXT -split ';')) { throw 'Existing extensions were lost.' }
}
'@ | Set-Content -LiteralPath $script:Stub -Encoding UTF8
        $result = Invoke-RunnerFixture -Runner (Join-Path $script:FixtureRoot 'Test.ps1') -WorkingDirectory $TestDrive -PathExt '.CPL'
        $result.ExitCode | Should -Be 0 -Because $result.Error
    }
    It 'restores the invoking process PATHEXT after validation' {
        'function Invoke-ProjectValidation {}' | Set-Content -LiteralPath $script:Stub -Encoding UTF8
        $wrapper = Join-Path $script:FixtureRoot 'wrapper.ps1'
        @'
$ErrorActionPreference = 'Stop'
$before = $env:PATHEXT
& (Join-Path $PSScriptRoot 'Test.ps1')
if ($env:PATHEXT -cne $before) { throw 'Validation changed the invoking environment.' }
'@ | Set-Content -LiteralPath $wrapper -Encoding UTF8
        $result = Invoke-RunnerFixture -Runner $wrapper -WorkingDirectory $TestDrive -PathExt '.CPL'
        $result.ExitCode | Should -Be 0 -Because $result.Error
    }

}
