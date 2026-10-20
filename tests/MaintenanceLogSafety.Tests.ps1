# Pester 5.5; all changes are disposable TestDrive files. Never run real maintenance.
BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'src\VhdMaintenance.ps1')

    # Copy entrypoints with an empty dependency so Pester supplies every boundary.
    $script:FixtureRoot = Join-Path $TestDrive 'entrypoints'
    foreach ($directory in @('src', 'scripts\maintenance', 'scripts\diagnostics')) {
        $null = New-Item -Path (Join-Path $script:FixtureRoot $directory) -ItemType Directory -Force
    }
    [IO.File]::WriteAllText((Join-Path $script:FixtureRoot 'src\VhdMaintenance.ps1'), '# Dependencies supplied by tests.')
    foreach ($name in @('Invoke-VhdCompaction', 'Invoke-UbuntuMaintenance', 'Invoke-SystemCleanup',
        'Set-PagefileAndCompact', 'Disable-Hibernation')) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot "scripts\maintenance\$name.ps1") -Destination (Join-Path $script:FixtureRoot 'scripts\maintenance')
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts\diagnostics\Find-OpenHandles.ps1') -Destination (Join-Path $script:FixtureRoot 'scripts\diagnostics')

    function Invoke-TestLogWrapper {
        param([string]$Name, [string]$LogPath, [switch]$WhatIf)
        $arguments = @{ LogPath = $LogPath; Confirm = $false; WhatIf = $WhatIf }
        $folder = 'maintenance'
        if ($Name -eq 'Find-OpenHandles') {
            $folder = 'diagnostics'
            $arguments.Search = 'synthetic volume'
            $arguments.AcceptEula = $true
            $arguments.ExecutablePath = 'C:\synthetic\handle64.exe'
        }
        elseif ($Name -ne 'Disable-Hibernation') { $arguments.VhdPath = $script:Image }
        & (Join-Path $script:FixtureRoot "scripts\$folder\$Name.ps1") @arguments
    }
    function Assert-TestLogReleased {
        param([string]$Path)
        $handle = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try { $handle.CanWrite | Should -BeTrue } finally { $handle.Dispose() }
    }
    # Fail-safe commands in addition to the high-level mocks: none can mutate a system.
    function Mount-DiskImage { [CmdletBinding(SupportsShouldProcess = $true)] param([string]$ImagePath) throw 'SAFETY: no mounting.' }
    function Dismount-DiskImage { [CmdletBinding(SupportsShouldProcess = $true)] param([string]$ImagePath) throw 'SAFETY: no dismounting.' }
    function Get-WmiObject { [CmdletBinding()] param([string]$Class) throw 'SAFETY: no WMI.' }
}

Describe 'Exclusive creation and owned-stream log API' {
    BeforeEach {
        $script:Log = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + ' [literal].log')
    }
    It 'generates names without creating directories or files' {
        $path = Join-Path $TestDrive 'not-created\new.log'
        New-MaintenanceLogPath -Operation 'safety-test' -LogPath $path | Should -Be $path
        Test-Path -LiteralPath (Split-Path -Parent $path) | Should -BeFalse
    }
    It 'creates literal parents and retains one stream through every write including Start' {
        $path = Join-Path $TestDrive 'new [literal] parent\owned.log'
        $log = Open-MaintenanceLog -LogPath $path
        try {
            Write-MaintenanceLog -Log $log -Start -Message 'first'
            Write-MaintenanceLog -Log $log -Start -Message 'second'
            Write-MaintenanceFailure -Log $log -Failure 'synthetic failure'
            { [IO.File]::Open($path, 'Open', 'Write', 'ReadWrite') } | Should -Throw
            { [IO.File]::Move($path, ($path + '.moved')) } | Should -Throw
        }
        finally { Close-MaintenanceLog -Log $log }
        [IO.File]::ReadAllText($path) | Should -Match 'first\r?\nsecond\r?\n=== FAILED '
        Assert-TestLogReleased -Path $path
        { Write-MaintenanceLog -Log $log -Message 'after disposal' } | Should -Throw '*open owned maintenance log*'
    }
    It 'never overwrites or appends to any existing file even when requested as Start' {
        [IO.File]::WriteAllBytes($script:Log, [byte[]]@(0, 1, 255, 13, 10, 42))
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Log))
        { Open-MaintenanceLog -LogPath $script:Log } | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Log)) | Should -BeExactly $before
        Assert-TestLogReleased -Path $script:Log
    }
    It 'rejects legacy path-based writes instead of reopening the path' {
        [IO.File]::WriteAllText($script:Log, 'keep me')
        { Write-MaintenanceLog -Log $script:Log -Start -Message 'overwrite' } | Should -Throw '*owned maintenance log*'
        { Write-MaintenanceLog -LogPath $script:Log -Message 'append' } | Should -Throw
        Write-MaintenanceFailure -Log $script:Log -Failure 'failure' -WarningAction Stop
        [IO.File]::ReadAllText($script:Log) | Should -BeExactly 'keep me'
    }
    It 'rejects nonlocal, provider, device, ADS, wildcard and control-character paths before file creation' {
        foreach ($bad in @('relative.log', 'C:relative.log', '\\server\share\test.log', '\\?\C:\test.log',
            'HKLM:\test.log', 'C:\test.log:stream', 'C:\test*.log', 'C:\NUL.log', "C:\bad`nname.log")) {
            { Open-MaintenanceLog -LogPath $bad } | Should -Throw
        }
    }
    It 'fails on an existing directory without changing its contents' {
        $directory = Join-Path $TestDrive 'directory.log'
        $null = New-Item -Path $directory -ItemType Directory
        $sentinel = Join-Path $directory 'sentinel.vhdx'
        [IO.File]::WriteAllText($sentinel, 'not a real VHD')
        { Open-MaintenanceLog -LogPath $directory } | Should -Throw
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'not a real VHD'
    }
    It 'does not replace a primary failure when failure-log writing also fails' {
        $log = Open-MaintenanceLog -LogPath $script:Log
        Close-MaintenanceLog -Log $log
        { Write-MaintenanceFailure -Log $log -Failure 'primary' -WarningAction Stop } | Should -Not -Throw
        Assert-TestLogReleased -Path $script:Log
    }
}

Describe 'Entrypoint collision safety and logging lifetime' {
    BeforeEach {
        $script:CaseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $script:CaseRoot -ItemType Directory
        $script:Image = Join-Path $script:CaseRoot 'sentinel.vhdx'
        [IO.File]::WriteAllBytes($script:Image, [byte[]]@(86, 72, 68, 0, 255, 13, 10, 42))
        $script:ImageBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Image))
        $script:Log = Join-Path $script:CaseRoot 'new.log'
        Mock Get-MaintenanceVhdPreflight { param($Path) $Path }
        Mock Assert-MaintenanceWmiAvailable {}
        Mock Resolve-MaintenanceHandleExecutable { param($Path) $Path }
        Mock Invoke-VhdCompaction { [pscustomobject]@{ Path = $script:Image; Length = 1024; Output = 'synthetic compaction' } }
        Mock Invoke-MaintenanceNativeCommand { [pscustomobject]@{ ExitCode = 0; Output = 'synthetic native output' } }
        Mock Set-CPageFileSize { 'synthetic pagefile update' }
        Mock Set-CPageFileRegistrySize { 'synthetic registry update' }
        Mock Mount-DiskImage { throw 'SAFETY: unexpected mount.' }
        Mock Dismount-DiskImage { throw 'SAFETY: unexpected dismount.' }
        Mock Get-WmiObject { throw 'SAFETY: unexpected WMI.' }
        Mock Set-ItemProperty { throw 'SAFETY: unexpected registry update.' }
    }

    It '<Name> rejects a log path equal to the VHD without appending failure output or doing maintenance' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        Mock Write-MaintenanceFailure { throw 'must not write an unowned failure log' }
        { Invoke-TestLogWrapper -Name $Name -LogPath $script:Image } | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Image)) | Should -BeExactly $script:ImageBytes
        Should -Invoke Write-MaintenanceFailure -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Set-CPageFileSize -Times 0 -Exactly
        Should -Invoke Set-CPageFileRegistrySize -Times 0 -Exactly
    }
    It '<Name> rejects an existing ordinary log unchanged and never logs to a rejected acquisition' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        [IO.File]::WriteAllText($script:Log, 'pre-existing ordinary log')
        Mock Write-MaintenanceFailure { throw 'must not write an unowned failure log' }
        { Invoke-TestLogWrapper -Name $Name -LogPath $script:Log } | Should -Throw
        [IO.File]::ReadAllText($script:Log) | Should -BeExactly 'pre-existing ordinary log'
        Should -Invoke Write-MaintenanceFailure -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
    }
    It '<Name> rejects a hard-linked image log without changing either name' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        try { $null = New-Item -Path $script:Log -ItemType HardLink -Target $script:Image -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because "NTFS hard links unavailable: $($_.Exception.Message)"; return }
        { Invoke-TestLogWrapper -Name $Name -LogPath $script:Log } | Should -Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Log)) | Should -BeExactly $script:ImageBytes
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Image)) | Should -BeExactly $script:ImageBytes
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
    }
    It '<Name> rejects a junction alias to the image and does not create logs through the junction' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        $junction = Join-Path $script:CaseRoot 'junction'
        $target = Join-Path $script:CaseRoot 'target'
        $null = New-Item -Path $target -ItemType Directory
        $targetImage = Join-Path $target 'sentinel.vhdx'
        [IO.File]::WriteAllBytes($targetImage, [IO.File]::ReadAllBytes($script:Image))
        try { $null = New-Item -Path $junction -ItemType Junction -Target $target -ErrorAction Stop }
        catch { Set-ItResult -Skipped -Because "Directory junctions unavailable: $($_.Exception.Message)"; return }
        try {
            { Invoke-TestLogWrapper -Name $Name -LogPath (Join-Path $junction 'sentinel.vhdx') } | Should -Throw '*Reparse-point log parent*'
            { Invoke-TestLogWrapper -Name $Name -LogPath (Join-Path $junction 'missing-parent\new.log') } | Should -Throw '*Reparse-point log parent*'
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($targetImage)) | Should -BeExactly $script:ImageBytes
            Test-Path -LiteralPath (Join-Path $target 'missing-parent') | Should -BeFalse
            Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
            Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        }
        finally { [IO.Directory]::Delete($junction) }
    }
    It '<Name> writes zero files and does no work under WhatIf' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        $newPath = Join-Path $script:CaseRoot 'not-created\new.log'
        Mock Open-MaintenanceLog { throw 'must not acquire a log' }
        $null = Invoke-TestLogWrapper -Name $Name -LogPath $newPath -WhatIf
        Test-Path -LiteralPath (Split-Path -Parent $newPath) | Should -BeFalse
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:Image)) | Should -BeExactly $script:ImageBytes
        Should -Invoke Open-MaintenanceLog -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
    }
    It '<Name> releases the log handle after success' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        $null = Invoke-TestLogWrapper -Name $Name -LogPath $script:Log
        [IO.File]::ReadAllText($script:Log) | Should -Match '=== Done '
        Assert-TestLogReleased -Path $script:Log
    }
    It '<Name> logs subsequent failures to the retained stream and releases its handle' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        Mock Invoke-VhdCompaction {
            { [IO.File]::Open($script:Log, 'Open', 'Write', 'ReadWrite') } | Should -Throw
            throw 'synthetic operation failure'
        }
        Mock Invoke-MaintenanceNativeCommand {
            { [IO.File]::Open($script:Log, 'Open', 'Write', 'ReadWrite') } | Should -Throw
            throw 'synthetic operation failure'
        }
        { Invoke-TestLogWrapper -Name $Name -LogPath $script:Log } | Should -Throw '*synthetic operation failure*'
        [IO.File]::ReadAllText($script:Log) | Should -Match '=== FAILED .*synthetic operation failure'
        [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
        Assert-TestLogReleased -Path $script:Log
    }
    It '<Name> cleans up an owned stream when the initial write fails, without doing maintenance' -ForEach @(
        @{ Name = 'Invoke-VhdCompaction' }, @{ Name = 'Invoke-UbuntuMaintenance' },
        @{ Name = 'Invoke-SystemCleanup' }, @{ Name = 'Set-PagefileAndCompact' },
        @{ Name = 'Disable-Hibernation' }, @{ Name = 'Find-OpenHandles' }
    ) {
        Mock Write-MaintenanceLog {
            param($Log, $Message, $Start)
            if ($Start) { throw 'synthetic initial write failure' }
            $Log.Writer.WriteLine($Message)
        }
        { Invoke-TestLogWrapper -Name $Name -LogPath $script:Log } | Should -Throw '*synthetic initial write failure*'
        [IO.File]::ReadAllText($script:Log) | Should -Match '=== FAILED .*synthetic initial write failure'
        Assert-TestLogReleased -Path $script:Log
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
    }
    It 'standalone hibernation treats empty and whitespace optional paths as no logging' {
        Mock Open-MaintenanceLog { throw 'must not acquire optional log' }
        foreach ($path in @('', '   ')) {
            (Invoke-TestLogWrapper -Name 'Disable-Hibernation' -LogPath $path).ExitCode | Should -Be 0
        }
        Should -Invoke Open-MaintenanceLog -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 2 -Exactly
    }
    It 'standalone results are emitted only after the owned log is closed' {
        foreach ($name in @('Disable-Hibernation', 'Find-OpenHandles')) {
            $path = Join-Path $script:CaseRoot ($name + '.log')
            Invoke-TestLogWrapper -Name $name -LogPath $path | ForEach-Object {
                $_.ExitCode | Should -Be 0
                Assert-TestLogReleased -Path $path
            }
        }
    }
}
