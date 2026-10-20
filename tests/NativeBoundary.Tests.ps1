BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'src\VhdMaintenance.ps1')
}

Describe 'Actual native exit-status contract using harmless cmd.exe fixtures' {
    BeforeEach {
        $script:SavedNativeStatus = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        Mock Get-Command { [pscustomobject]@{ Source = $env:COMSPEC } } -ParameterFilter { $CommandType -eq 'Application' }
    }
    AfterEach {
        if ($null -ne $script:SavedNativeStatus) { $global:LASTEXITCODE = $script:SavedNativeStatus.Value }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
    It 'accepts a zero status from an actual native process' {
        $result = Invoke-MaintenanceNativeCommand -FileName dism.exe -ArgumentList @('/d', '/c', 'exit', '0') -Confirm:$false
        $result.ExitCode | Should -Be 0
        Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter { $Name -eq 'dism.exe' -and $CommandType -eq 'Application' }
    }
    It 'propagates the actual nonzero exit status rather than a shadowed or stale value' {
        $global:LASTEXITCODE = 42
        $failure = $null
        try { Invoke-MaintenanceNativeCommand -FileName dism.exe -ArgumentList @('/d', '/c', 'exit', '7') -Confirm:$false }
        catch { $failure = $_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Data['NativeExitCode'] | Should -Be 7
    }
    It 'replaces stale status and captures native stdout on success' {
        $global:LASTEXITCODE = 42
        $result = Invoke-MaintenanceNativeCommand -FileName dism.exe -ArgumentList @('/d', '/c', 'echo', 'synthetic-native-stdout') -Confirm:$false
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'synthetic-native-stdout'
    }
    It 'does not launch a process under WhatIf' {
        Invoke-MaintenanceNativeCommand -FileName dism.exe -ArgumentList @('/d', '/c', 'exit', '7') -WhatIf
        Should -Invoke Get-Command -Times 0
    }
}

Describe 'Handle search validation before any execution or logging' {
    BeforeEach {
        $script:Entry = Join-Path $ProjectRoot 'scripts\diagnostics\Find-OpenHandles.ps1'
        $script:LogPath = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.log')
    }
    It 'rejects quote splitting, disguised switches, and control characters (<Case>)' -ForEach @(
        @{ Case = 'EmbeddedQuotes' }
        @{ Case = 'PaddedDashSwitch' }
        @{ Case = 'PaddedSlashSwitch' }
        @{ Case = 'Whitespace' }
        @{ Case = 'UnicodeControl' }
        @{ Case = 'NullControl' }
        @{ Case = 'TrailingQuote' }
    ) {
        $Search = switch ($Case) {
            'EmbeddedQuotes' { 'literal " -c 123 -p 456 -y " tail' }
            'PaddedDashSwitch' { '   -c' }
            'PaddedSlashSwitch' { '   /c' }
            'Whitespace' { '  ' }
            'UnicodeControl' { 'literal' + [char]0x85 + 'tail' }
            'NullControl' { 'literal' + [char]0 + 'tail' }
            'TrailingQuote' { 'literal"' }
        }
        { & $script:Entry -Search $Search -AcceptEula -LogPath $script:LogPath -Confirm:$false } | Should -Throw '*literal nonempty*'
        Test-Path -LiteralPath $script:LogPath | Should -BeFalse
    }
    It 'can preview ordinary literal search text without requiring Handle or creating a log' {
        { & $script:Entry -Search 'literal [file] name' -LogPath $script:LogPath -WhatIf } | Should -Not -Throw
        Test-Path -LiteralPath $script:LogPath | Should -BeFalse
    }
}
