BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'tools\ProjectTools.ps1')
}

Describe 'PowerShell script syntax' {
    It 'parses every project script without executing it' {
        $files = @(Get-ProjectOwnedFile -ProjectRoot $ProjectRoot)
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$tokens, [ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because $file.FullName
        }
    }
}
