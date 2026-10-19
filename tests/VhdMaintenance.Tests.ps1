# Pester 5.5. Run with Windows PowerShell 5.1, -NoProfile -NonInteractive.
# Set Pester configuration TestRegistry.Enabled = $false (no real-registry fixture).
# NO real Storage/WMI/native mutations. All writable fixtures live in TestDrive.
BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'src\VhdMaintenance.ps1')

    # Safety stubs shadow the real commands even if a mock is accidentally missed.
    function Get-DiskImage {
        [CmdletBinding()] param([string]$ImagePath)
        throw 'SAFETY: real Get-DiskImage is forbidden in tests.'
    }
    function Mount-DiskImage {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([string]$ImagePath, [string]$Access, [switch]$NoDriveLetter, [switch]$PassThru)
        throw 'SAFETY: real mounting is forbidden in tests.'
    }
    function Dismount-DiskImage {
        [CmdletBinding(SupportsShouldProcess = $true)] param([string]$ImagePath)
        throw 'SAFETY: real dismounting is forbidden in tests.'
    }
    function Get-WmiObject {
        [CmdletBinding()] param([string]$Class)
        throw 'SAFETY: real WMI is forbidden in tests.'
    }
    function Get-AuthenticodeSignature {
        [CmdletBinding()] param([string]$LiteralPath)
        throw 'SAFETY: real signature inspection is forbidden in tests.'
    }
    function Invoke-TestNative {
        param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)
        # Simulate the local LASTEXITCODE behavior of a native process, not one
        # of the actual executables. Do not alter user/global preferences.
        if ($null -ne $script:FakeExitCode) {
            Set-Variable -Name LASTEXITCODE -Scope 1 -Value $script:FakeExitCode
        }
        'synthetic native output'
    }
    function New-TestWmiRecord {
        param([hashtable]$Properties)
        $record = [pscustomobject]$Properties
        $record | Add-Member -NotePropertyName PutCount -NotePropertyValue 0
        $record | Add-Member -NotePropertyName FailOnPut -NotePropertyValue 0
        $record | Add-Member -MemberType ScriptMethod -Name Put -Value {
            $this.PutCount++
            if ($this.PutCount -eq $this.FailOnPut) { throw 'synthetic Put failure' }
            [pscustomobject]@{ Path = 'synthetic WMI object' }
        }
        return $record
    }
    $script:ChineseSuccess = 'DiskPart ' + [string]::Concat(
        [char]0x5df2, [char]0x6210, [char]0x529f, [char]0x538b, [char]0x7f29,
        [char]0x865a, [char]0x62df, [char]0x78c1, [char]0x76d8,
        [char]0x6587, [char]0x4ef6, [char]0x3002)
}

Describe 'Literal VHD file validation and exclusive access' {
    BeforeEach {
        $script:Image = Join-Path $TestDrive 'disk [literal] {id}.vhdx'
        [IO.File]::WriteAllText($script:Image, 'not a real VHD; never mounted')
    }

    It 'accepts an exact existing literal VHD file including brackets and braces' {
        Resolve-MaintenanceVhdPath -Path $script:Image | Should -Be $script:Image
    }
    It 'rejects relative, remote, device, wildcard, ADS, quote, and newline input before reading files' {
        Mock Get-Item { throw 'must not read a rejected path' }
        foreach ($bad in @('disk.vhdx', '\\server\share\disk.vhdx', '\\?\C:\disk.vhdx',
            'C:disk.vhdx', 'C:\disk*.vhdx', 'C:\disk?.vhdx', 'C:\disk.vhdx:stream',
            'C:\disk".vhdx', "C:\disk`r`ncompact vdisk.vhdx")) {
            { Resolve-MaintenanceVhdPath -Path $bad } | Should -Throw '*absolute local*'
        }
        Should -Invoke Get-Item -Times 0 -Exactly
    }
    It 'rejects missing files' {
        { Resolve-MaintenanceVhdPath -Path (Join-Path $TestDrive 'missing.vhdx') } | Should -Throw
    }
    It 'rejects directories and non-VHD files' {
        $directory = New-Item -Path (Join-Path $TestDrive 'directory.vhdx') -ItemType Directory
        $file = New-Item -Path (Join-Path $TestDrive 'ordinary.txt') -ItemType File
        { Resolve-MaintenanceVhdPath -Path $directory.FullName } | Should -Throw '*Not a VHD*'
        { Resolve-MaintenanceVhdPath -Path $file.FullName } | Should -Throw '*Not a VHD*'
    }
    It 'rejects reparse-point images without creating real links' {
        Mock Get-Item {
            [pscustomobject]@{
                PSProvider = @{ Name = 'FileSystem' }; PSIsContainer = $false
                Extension = '.vhdx'; Attributes = [IO.FileAttributes]::ReparsePoint
            }
        }
        { Resolve-MaintenanceVhdPath -Path $script:Image } | Should -Throw '*Reparse-point*'
    }
    It 'opens without creating, truncating or changing content and releases its handle' {
        Assert-MaintenanceVhdExclusiveAccess -Path $script:Image
        [IO.File]::ReadAllText($script:Image) | Should -Be 'not a real VHD; never mounted'
        $handle = [IO.File]::Open($script:Image, 'Open', 'ReadWrite', 'None')
        try { $handle | Should -Not -BeNullOrEmpty } finally { $handle.Dispose() }
    }
    It 'rejects an exclusively locked file without stopping its owner' {
        $handle = [IO.File]::Open($script:Image, 'Open', 'ReadWrite', 'None')
        try {
            { Assert-MaintenanceVhdExclusiveAccess -Path $script:Image } | Should -Throw '*opened exclusively*'
        }
        finally { $handle.Dispose() }
    }
    It 'does not create a missing file during the exclusive probe' {
        $missing = Join-Path $TestDrive 'not-created.vhdx'
        { Assert-MaintenanceVhdExclusiveAccess -Path $missing } | Should -Throw
        Test-Path -LiteralPath $missing | Should -BeFalse
    }
}

Describe 'Storage API availability' {
    It 'accepts supported Storage-style parameter metadata without invoking any command' {
        Assert-MaintenanceStorageCommands
    }
    It 'fails closed when a Storage command is unavailable' {
        Mock Get-Command { throw 'Storage not installed' }
        { Assert-MaintenanceStorageCommands } | Should -Throw '*Storage not installed*'
    }
    It 'fails closed when read-only access is not supported' {
        Mock Get-Command {
            [pscustomobject]@{ Parameters = @{
                ImagePath = $null; NoDriveLetter = $null; PassThru = $null
                ErrorAction = $null; Confirm = $null
            } }
        }
        { Assert-MaintenanceStorageCommands } | Should -Throw '*Mount-DiskImage -Access*'
    }
}

Describe 'Native result propagation without launching executables' {
    BeforeEach {
        $script:FakeExitCode = 0
        Mock Get-Command { [pscustomobject]@{ Source = 'Invoke-TestNative' } }
    }
    It 'returns output only for an explicit zero exit code' {
        $result = Invoke-MaintenanceNativeCommand -FileName diskpart.exe -ArgumentList @('/s', 'synthetic.txt') -Confirm:$false
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Be 'synthetic native output'
        Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'diskpart.exe' -and $CommandType -eq 'Application'
        }
    }
    It 'propagates nonzero status for DiskPart, DISM and powercfg including negative Windows errors' {
        foreach ($name in @('diskpart.exe', 'dism.exe', 'powercfg.exe')) {
            $script:FakeExitCode = -2147024809
            $caught = $null
            try { Invoke-MaintenanceNativeCommand -FileName $name -ArgumentList @('synthetic') -Confirm:$false }
            catch { $caught = $_ }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Data['NativeExitCode'] | Should -Be -2147024809
            $caught.Exception.Message | Should -Match 'synthetic native output'
        }
    }
    It 'does not accept stale or missing native status' {
        $script:FakeExitCode = $null
        { Invoke-MaintenanceNativeCommand -FileName dism.exe -ArgumentList @('synthetic') -Confirm:$false } |
            Should -Throw '*dism.exe exit=*'
    }
    It 'does not resolve or invoke a native command under WhatIf' {
        Invoke-MaintenanceNativeCommand -FileName dism.exe -ArgumentList @('synthetic') -WhatIf
        Should -Invoke Get-Command -Times 0 -Exactly
    }
}

Describe 'VHD compaction attachment ownership' {
    BeforeEach {
        $script:Image = Join-Path $TestDrive 'disk [literal] {id}.vhdx'
        [IO.File]::WriteAllText($script:Image, 'synthetic VHD')
        $script:Mounted = $false
        $script:GeneratedFile = $null
        $script:GeneratedScript = $null
        Mock Assert-MaintenanceStorageCommands {}
        Mock Assert-MaintenanceVhdExclusiveAccess {}
        Mock Get-DiskImage {
            param($ImagePath)
            [pscustomobject]@{ ImagePath = $ImagePath; Attached = $script:Mounted }
        }
        Mock Mount-DiskImage { $script:Mounted = $true }
        Mock Dismount-DiskImage { $script:Mounted = $false }
        Mock New-TemporaryFile {
            New-Item -Path (Join-Path $TestDrive (([guid]::NewGuid().ToString()) + '.txt')) -ItemType File
        }
        Mock Invoke-MaintenanceNativeCommand {
            param($FileName, $ArgumentList)
            if (-not $script:Mounted) { throw 'Compaction must run only after attachment.' }
            $script:GeneratedFile = $ArgumentList[1]
            $script:GeneratedScript = [IO.File]::ReadAllText($script:GeneratedFile, [Text.Encoding]::Unicode)
            [pscustomobject]@{ ExitCode = 0; Output = 'DiskPart successfully compacted the virtual disk file.' }
        }
    }

    It 'mounts the exact validated path read-only, compacts once, and dismounts its own image' {
        $result = Invoke-VhdCompaction -Path $script:Image -Confirm:$false
        $result.Path | Should -Be $script:Image
        $result.Length | Should -BeGreaterThan 0
        $script:Mounted | Should -BeFalse
        Should -Invoke Mount-DiskImage -Times 1 -Exactly -ParameterFilter {
            $ImagePath -eq $script:Image -and $Access -eq 'ReadOnly' -and $NoDriveLetter -and
            $PassThru -and $ErrorAction -eq 'Stop' -and $Confirm -eq $false
        }
        Should -Invoke Assert-MaintenanceVhdExclusiveAccess -Times 1 -Exactly -ParameterFilter { $Path -eq $script:Image }
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly -ParameterFilter {
            $ImagePath -eq $script:Image -and $Confirm -eq $false
        }
        $script:GeneratedScript | Should -Be ((@(
            ('select vdisk file="{0}"' -f $script:Image), 'compact vdisk', 'exit', ''
        )) -join [Environment]::NewLine)
        $script:GeneratedScript | Should -Not -Match '(?i)noerr|attach vdisk|detach vdisk'
        Test-Path -LiteralPath $script:GeneratedFile | Should -BeFalse
    }
    It 'supports exact non-ASCII paths without lossy script encoding' {
        $unicodeImage = Join-Path $TestDrive (([string][char]0x865a) + '.vhdx')
        [IO.File]::WriteAllText($unicodeImage, 'synthetic VHD')
        $null = Invoke-VhdCompaction -Path $unicodeImage -Confirm:$false
        $script:GeneratedScript | Should -Match ([regex]::Escape($unicodeImage))
    }
    It 'releases the owned attachment when compaction throws' {
        Mock Invoke-MaintenanceNativeCommand { throw 'synthetic compact failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*synthetic compact failure*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
        $script:Mounted | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.txt').Count | Should -Be 0
    }
    It 'rejects a nonzero compact result and still cleans up' {
        Mock Invoke-MaintenanceNativeCommand { [pscustomobject]@{ ExitCode = 5; Output = 'synthetic failure' } }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*exit=5*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'rejects zero exit without explicit compact success (selection/progress is insufficient)' {
        Mock Invoke-MaintenanceNativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = "DiskPart successfully selected the virtual disk file.`r`n100 percent completed`r`nDiskPart encountered an error" }
        }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*not positively acknowledged*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'rejects error output even if a compact acknowledgement also appears' {
        Mock Invoke-MaintenanceNativeCommand {
            [pscustomobject]@{ ExitCode = 0; Output = "DiskPart successfully compacted the virtual disk file.`r`nVirtual Disk Service error: synthetic failure" }
        }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*not positively acknowledged*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'rejects Simplified Chinese errors even alongside a success acknowledgement' {
        Mock Invoke-MaintenanceNativeCommand {
            $errorText = [string]::Concat([char]0x9519, [char]0x8bef)
            [pscustomobject]@{ ExitCode = 0; Output = ($script:ChineseSuccess + "`r`n" + $errorText) }
        }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*not positively acknowledged*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'accepts this machines explicit Simplified Chinese compact acknowledgement' {
        Mock Invoke-MaintenanceNativeCommand { [pscustomobject]@{ ExitCode = 0; Output = $script:ChineseSuccess } }
        (Invoke-VhdCompaction -Path $script:Image -Confirm:$false).Output | Should -Be $script:ChineseSuccess
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'fails closed for unknown locales and still dismounts' {
        Mock Invoke-MaintenanceNativeCommand { [pscustomobject]@{ ExitCode = 0; Output = 'unrecognized localized acknowledgement' } }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*unrecognized localized*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'rejects preattached images without opening, mounting, compacting or detaching them' {
        $script:Mounted = $true
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*already attached*'
        Should -Invoke Assert-MaintenanceVhdExclusiveAccess -Times 0 -Exactly
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke New-TemporaryFile -Times 0 -Exactly
    }
    It 'rejects unknown or mismatched Get-DiskImage state' {
        Mock Get-DiskImage { [pscustomobject]@{ ImagePath = 'C:\different.vhdx'; Attached = $false } }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*exactly this image*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
    }
    It 'rechecks attachment state immediately before mounting without stealing a new owners attachment' {
        $script:StateReads = 0
        Mock Get-DiskImage {
            param($ImagePath)
            $script:StateReads++
            [pscustomobject]@{ ImagePath = $ImagePath; Attached = ($script:StateReads -gt 1) }
        }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*already attached*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.txt').Count | Should -Be 0
    }
    It 'never mounts or detaches when the exclusive access check fails' {
        Mock Assert-MaintenanceVhdExclusiveAccess { throw 'synthetic exclusive access failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*exclusive access failure*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
    }
    It 'does not mount if the required Storage APIs are unavailable' {
        Mock Assert-MaintenanceStorageCommands { throw 'synthetic Storage unavailable' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*Storage unavailable*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
    }
    It 'never detaches an attachment whose mount call failed' {
        Mock Mount-DiskImage { throw 'synthetic mount failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*mount failure*'
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.txt').Count | Should -Be 0
    }
    It 'cleans up a successful mount even when post-mount state verification fails' {
        Mock Mount-DiskImage {} # Get-DiskImage still reports detached.
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*could not be verified*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
    }
    It 'treats dismount failure as failure instead of reporting successful compaction' {
        Mock Dismount-DiskImage { throw 'synthetic dismount failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false -WarningAction SilentlyContinue } | Should -Throw '*dismount failure*'
        Test-Path -LiteralPath $script:GeneratedFile | Should -BeFalse
    }
    It 'preserves the primary failure when both compact and cleanup fail' {
        Mock Invoke-MaintenanceNativeCommand { throw 'primary compact failure' }
        Mock Dismount-DiskImage { throw 'secondary cleanup failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false -WarningAction SilentlyContinue } | Should -Throw '*primary compact failure*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
    }
    It 'still removes the temporary script and preserves the error with WarningAction Stop' {
        Mock Invoke-MaintenanceNativeCommand { throw 'primary compact failure' }
        Mock Dismount-DiskImage { throw 'secondary cleanup failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false -WarningAction Stop } | Should -Throw '*primary compact failure*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.txt').Count | Should -Be 0
    }
    It 'cleans up when the post-compact size query throws' {
        $script:ImageItem = Get-Item -LiteralPath $script:Image
        $script:ItemReads = 0
        Mock Get-Item {
            $script:ItemReads++
            if ($script:ItemReads -gt 1) { throw 'synthetic size query failure' }
            $script:ImageItem
        } -ParameterFilter { $LiteralPath -eq $script:Image }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*size query failure*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
        Test-Path -LiteralPath $script:GeneratedFile | Should -BeFalse
    }
    It 'does not report success when temporary script removal fails after dismount' {
        Mock Remove-Item { throw 'synthetic temporary cleanup failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*temporary cleanup failure*'
        Should -Invoke Dismount-DiskImage -Times 1 -Exactly
        $script:Mounted | Should -BeFalse
        # Pester owns the remaining TestDrive fixture; no real temp path was used.
    }
    It 'does not mount when temporary script allocation fails' {
        Mock New-TemporaryFile { throw 'synthetic temp failure' }
        { Invoke-VhdCompaction -Path $script:Image -Confirm:$false } | Should -Throw '*temp failure*'
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
    }
    It 'performs no file probes, temporary writes, mounts or native calls under WhatIf' {
        Invoke-VhdCompaction -Path 'C:\nonexistent.vhdx' -WhatIf
        Should -Invoke Assert-MaintenanceStorageCommands -Times 0 -Exactly
        Should -Invoke Assert-MaintenanceVhdExclusiveAccess -Times 0 -Exactly
        Should -Invoke Get-DiskImage -Times 0 -Exactly
        Should -Invoke New-TemporaryFile -Times 0 -Exactly
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
    }
}

Describe 'WMI C: pagefile targeting, validation and rollback' {
    BeforeEach {
        Mock Assert-MaintenanceWmiAvailable {} # Only synthetic WMI records on both engines.
        $script:System = New-TestWmiRecord @{ AutomaticManagedPagefile = $true }
        $script:CPage = New-TestWmiRecord @{ Name = 'C:\pagefile.sys'; InitialSize = 4096; MaximumSize = 8192 }
        $script:DPage = New-TestWmiRecord @{ Name = 'D:\pagefile.sys'; InitialSize = 1024; MaximumSize = 2048 }
        $script:Pages = @($script:DPage, $script:CPage)
        Mock Get-WmiObject {
            param($Class)
            if ($Class -eq 'Win32_ComputerSystem') { return $script:System }
            if ($Class -eq 'Win32_PageFileSetting') { return $script:Pages }
            throw "Unexpected WMI class: $Class"
        }
    }
    It 'updates just the C: instance, not a pagefile array or the D: instance' {
        $null = Set-CPageFileSize -Confirm:$false
        $script:CPage.InitialSize | Should -Be 16384
        $script:CPage.MaximumSize | Should -Be 32768
        $script:CPage.PutCount | Should -Be 1
        $script:System.AutomaticManagedPagefile | Should -BeFalse
        $script:DPage.InitialSize | Should -Be 1024
        $script:DPage.MaximumSize | Should -Be 2048
        $script:DPage.PutCount | Should -Be 0
    }
    It 'matches the C: pagefile case-insensitively and exactly' {
        $script:CPage.Name = 'c:\PAGEFILE.SYS'
        $extra = New-TestWmiRecord @{ Name = 'C:\other\pagefile.sys'; InitialSize = 100; MaximumSize = 200 }
        $script:Pages += $extra
        $null = Set-CPageFileSize -Confirm:$false
        $extra.PutCount | Should -Be 0
        $script:CPage.PutCount | Should -Be 1
    }
    It 'validates a missing C: setting before disabling automatic management' {
        $script:Pages = @($script:DPage)
        { Set-CPageFileSize -Confirm:$false } | Should -Throw '*exactly one existing C:*'
        $script:System.PutCount | Should -Be 0
        $script:System.AutomaticManagedPagefile | Should -BeTrue
        $script:DPage.PutCount | Should -Be 0
    }
    It 'rejects ambiguous C: targets before any changes' {
        $script:Pages = @($script:CPage, $script:CPage)
        { Set-CPageFileSize -Confirm:$false } | Should -Throw '*exactly one existing C:*'
        $script:System.PutCount | Should -Be 0
        $script:CPage.PutCount | Should -Be 0
    }
    It 'rejects invalid requested sizes before WMI access' {
        { Set-CPageFileSize -InitialSizeMB 40000 -MaximumSizeMB 32768 -Confirm:$false } | Should -Throw '*must not exceed*'
        { Set-CPageFileSize -InitialSizeMB 0 -Confirm:$false } | Should -Throw
        Should -Invoke Get-WmiObject -Times 0 -Exactly
    }
    It 'rolls back target sizes and automatic management when target Put fails' {
        $script:CPage.FailOnPut = 1
        { Set-CPageFileSize -Confirm:$false } | Should -Throw '*synthetic Put failure*'
        $script:CPage.InitialSize | Should -Be 4096
        $script:CPage.MaximumSize | Should -Be 8192
        $script:CPage.PutCount | Should -Be 2
        $script:System.AutomaticManagedPagefile | Should -BeTrue
        $script:System.PutCount | Should -Be 2
        $script:DPage.PutCount | Should -Be 0
    }
    It 'attempts automatic-management rollback even when its first Put fails' {
        $script:System.FailOnPut = 1
        { Set-CPageFileSize -Confirm:$false } | Should -Throw '*synthetic Put failure*'
        $script:System.AutomaticManagedPagefile | Should -BeTrue
        $script:System.PutCount | Should -Be 2
        $script:CPage.PutCount | Should -Be 0
    }
    It 'rolls back on read-back mismatch' {
        $script:Reads = 0
        Mock Get-WmiObject {
            param($Class)
            if ($Class -eq 'Win32_ComputerSystem') { return $script:System }
            $script:Reads++
            if ($script:Reads -eq 1) { return $script:Pages }
            [pscustomobject]@{ Name = 'C:\pagefile.sys'; InitialSize = 1; MaximumSize = 2 }
        }
        { Set-CPageFileSize -Confirm:$false } | Should -Throw '*read-back verification failed*'
        $script:CPage.InitialSize | Should -Be 4096
        $script:System.AutomaticManagedPagefile | Should -BeTrue
        $script:DPage.PutCount | Should -Be 0
    }
    It 'does not replace a primary error if a rollback Put also fails' {
        $script:CPage.FailOnPut = 2
        $script:Reads = 0
        Mock Get-WmiObject {
            param($Class)
            if ($Class -eq 'Win32_ComputerSystem') { return $script:System }
            $script:Reads++
            if ($script:Reads -gt 1) { throw 'primary read-back failure' }
            $script:Pages
        }
        { Set-CPageFileSize -Confirm:$false -WarningAction SilentlyContinue } | Should -Throw '*primary read-back failure*'
        $script:System.AutomaticManagedPagefile | Should -BeTrue
        $script:System.PutCount | Should -Be 2
    }
    It 'does not access WMI under WhatIf' {
        Set-CPageFileSize -WhatIf
        Should -Invoke Get-WmiObject -Times 0 -Exactly
    }
}

Describe 'Registry alternative preserves all other pagefiles' {
    BeforeEach {
        $script:RegistryPages = [string[]]@('D:\pagefile.sys 1024 2048', 'C:\pagefile.sys 4096 8192', 'E:\pagefile.sys 0 0')
        $script:OriginalPages = $script:RegistryPages.Clone()
        $script:RegistryWrites = 0
        $script:RegistryKind = [Microsoft.Win32.RegistryValueKind]::MultiString
        $script:RegistryKey = [pscustomobject]@{}
        $script:RegistryKey | Add-Member -MemberType ScriptMethod -Name GetValueKind -Value { param($Name) $script:RegistryKind }
        Mock Get-Item { $script:RegistryKey } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
        Mock Get-ItemProperty { [pscustomobject]@{ PagingFiles = $script:RegistryPages.Clone() } }
        # This mock blocks ALL real registry writes, including any bad path.
        Mock Set-ItemProperty {
            param($Value)
            $script:RegistryWrites++
            $script:RegistryPages = [string[]]$Value.Clone()
        }
    }
    It 'replaces only the existing C: entry and retains REG_MULTI_SZ' {
        $null = Set-CPageFileRegistrySize -Confirm:$false
        $script:RegistryPages[0] | Should -BeExactly $script:OriginalPages[0]
        $script:RegistryPages[1] | Should -BeExactly 'C:\pagefile.sys 16384 32768'
        $script:RegistryPages[2] | Should -BeExactly $script:OriginalPages[2]
        Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PagingFiles' -and $Type -eq 'MultiString' -and $Value.Count -eq 3 -and
            $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        }
    }
    It 'handles a quoted case-insensitive C: entry without touching others' {
        $script:RegistryPages[1] = '"c:\PAGEFILE.SYS" 4096 8192'
        $null = Set-CPageFileRegistrySize -Confirm:$false
        $script:RegistryPages[1] | Should -Be 'C:\pagefile.sys 16384 32768'
        $script:RegistryPages[0] | Should -BeExactly $script:OriginalPages[0]
    }
    It 'rejects a missing C: entry without replacing other pagefiles' {
        $script:RegistryPages = [string[]]@('D:\pagefile.sys 1024 2048')
        { Set-CPageFileRegistrySize -Confirm:$false } | Should -Throw '*exactly one existing C:*'
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }
    It 'rejects duplicate C: entries' {
        $script:RegistryPages = [string[]]@('C:\pagefile.sys 1 2', 'c:\pagefile.sys 3 4')
        { Set-CPageFileRegistrySize -Confirm:$false } | Should -Throw '*exactly one existing C:*'
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }
    It 'validates the registry type before writing' {
        $script:RegistryKind = [Microsoft.Win32.RegistryValueKind]::String
        { Set-CPageFileRegistrySize -Confirm:$false } | Should -Throw '*REG_MULTI_SZ*'
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }
    It 'attempts rollback even when a write partially succeeds then throws' {
        Mock Set-ItemProperty {
            param($Value)
            $script:RegistryWrites++
            $script:RegistryPages = [string[]]$Value.Clone()
            if ($script:RegistryWrites -eq 1) { throw 'synthetic registry failure' }
        }
        { Set-CPageFileRegistrySize -Confirm:$false } | Should -Throw '*synthetic registry failure*'
        $script:RegistryWrites | Should -Be 2
        ($script:RegistryPages -join '|') | Should -BeExactly ($script:OriginalPages -join '|')
    }
    It 'rolls back on registry read-back mismatch' {
        Mock Get-ItemProperty { [pscustomobject]@{ PagingFiles = $script:OriginalPages.Clone() } }
        { Set-CPageFileRegistrySize -Confirm:$false } | Should -Throw '*read-back verification failed*'
        $script:RegistryWrites | Should -Be 2
        ($script:RegistryPages -join '|') | Should -BeExactly ($script:OriginalPages -join '|')
    }
    It 'rejects invalid sizes before registry access' {
        { Set-CPageFileRegistrySize -InitialSizeMB 100 -MaximumSizeMB 1 -Confirm:$false } | Should -Throw '*must not exceed*'
        Should -Invoke Get-ItemProperty -Times 0 -Exactly
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }
    It 'does not access or write registry values under WhatIf' {
        Set-CPageFileRegistrySize -WhatIf
        Should -Invoke Get-ItemProperty -Times 0 -Exactly
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }
}

Describe 'Guarded administrator entrypoints' {
    BeforeAll {
        $script:WrapperNames = @('Invoke-VhdCompaction.ps1', 'Invoke-UbuntuMaintenance.ps1', 'Invoke-SystemCleanup.ps1', 'Set-PagefileAndCompact.ps1')
        # Preserve the real two-level layout and import expression, with an empty
        # dependency so copied entrypoints inherit our mocked library functions.
        $script:FixtureRoot = Join-Path $TestDrive 'wrappers'
        $script:WrapperRoot = Join-Path $script:FixtureRoot 'scripts\maintenance'
        $null = New-Item -Path $script:WrapperRoot -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $script:FixtureRoot 'src') -ItemType Directory -Force
        [IO.File]::WriteAllText((Join-Path $script:FixtureRoot 'src\VhdMaintenance.ps1'), '# Test dependency supplied by Pester mocks.')
        foreach ($name in $script:WrapperNames) {
            Copy-Item -LiteralPath (Join-Path $ProjectRoot "scripts\maintenance\$name") -Destination (Join-Path $script:WrapperRoot $name)
        }
    }
    BeforeEach {
        $script:Log = Join-Path $TestDrive (([guid]::NewGuid().ToString()) + ' [literal].log')
        Mock Get-MaintenanceVhdPreflight { param($Path) $Path }
        Mock Assert-MaintenanceWmiAvailable {}
        Mock Invoke-VhdCompaction { [pscustomobject]@{ Path = 'C:\synthetic.vhdx'; Length = 1GB; Output = 'synthetic compact success' } }
        Mock Invoke-MaintenanceNativeCommand { [pscustomobject]@{ ExitCode = 0; Output = 'synthetic native success' } }
        Mock Set-CPageFileSize { 'synthetic WMI success' }
        Mock Set-CPageFileRegistrySize { 'synthetic registry success' }
        # Fail-safe guards: unexpected fall-through cannot reach real mutations.
        Mock Mount-DiskImage { throw 'SAFETY: unexpected mount' }
        Mock Dismount-DiskImage { throw 'SAFETY: unexpected dismount' }
        Mock Get-WmiObject { throw 'SAFETY: unexpected WMI' }
        Mock Set-ItemProperty { throw 'SAFETY: unexpected registry write' }
    }
    It 'all four wrappers declare ShouldProcess and high confirmation impact' {
        foreach ($name in $script:WrapperNames) {
            $source = Get-Content -LiteralPath (Join-Path $ProjectRoot "scripts\maintenance\$name") -Raw
            $source | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
            $source | Should -Match "ConfirmImpact\s*=\s*'High'"
        }
    }
    It 'all four wrappers WhatIf without logs, native commands, pagefile changes, or attachments' {
        foreach ($name in $script:WrapperNames) {
            & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -WhatIf
        }
        Test-Path -LiteralPath $script:Log | Should -BeFalse
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Set-CPageFileSize -Times 0 -Exactly
        Should -Invoke Set-CPageFileRegistrySize -Times 0 -Exactly
        Should -Invoke Mount-DiskImage -Times 0 -Exactly
        Should -Invoke Dismount-DiskImage -Times 0 -Exactly
    }
    It 'all four wrappers log Done only after successful mocked operations' {
        foreach ($name in $script:WrapperNames) {
            & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false
            [IO.File]::ReadAllText($script:Log) | Should -Match '=== Done '
            [IO.File]::ReadAllText($script:Log) | Should -Not -Match 'FAILED'
        }
        Should -Invoke Invoke-VhdCompaction -Times 4 -Exactly -ParameterFilter {
            $Confirm -eq $false -and $VhdPath -eq 'C:\synthetic.vhdx'
        }
    }
    It 'all four wrappers throw and log FAILED rather than Done on compaction failure' {
        Mock Invoke-VhdCompaction { throw 'synthetic compact failure' }
        foreach ($name in $script:WrapperNames) {
            { & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } |
                Should -Throw '*synthetic compact failure*'
            [IO.File]::ReadAllText($script:Log) | Should -Match 'FAILED'
            [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
        }
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly -ParameterFilter { $FileName -eq 'dism.exe' }
    }
    It 'stops before pagefile or compaction steps when powercfg fails' {
        Mock Invoke-MaintenanceNativeCommand { throw 'powercfg.exe exit=5' }
        { & (Join-Path $script:WrapperRoot 'Invoke-SystemCleanup.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } | Should -Throw '*powercfg.exe exit=5*'
        Should -Invoke Set-CPageFileSize -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
    }
    It 'stops before compaction when the WMI pagefile update fails' {
        Mock Set-CPageFileSize { throw 'synthetic WMI failure' }
        { & (Join-Path $script:WrapperRoot 'Invoke-SystemCleanup.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } | Should -Throw '*synthetic WMI failure*'
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
    }
    It 'stops before compaction when the registry pagefile update fails' {
        Mock Set-CPageFileRegistrySize { throw 'synthetic registry failure' }
        { & (Join-Path $script:WrapperRoot 'Set-PagefileAndCompact.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } | Should -Throw '*synthetic registry failure*'
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
    }
    It 'propagates DISM analysis failure and never attempts cleanup afterward' {
        Mock Invoke-MaintenanceNativeCommand { throw 'dism.exe analysis exit=87' }
        { & (Join-Path $script:WrapperRoot 'Invoke-UbuntuMaintenance.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } | Should -Throw '*analysis exit=87*'
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 1 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains '/startcomponentcleanup' }
        [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
    }
    It 'propagates DISM cleanup failure without Done' {
        Mock Invoke-MaintenanceNativeCommand { throw 'dism.exe cleanup exit=5' } -ParameterFilter { $ArgumentList -contains '/startcomponentcleanup' }
        { & (Join-Path $script:WrapperRoot 'Invoke-UbuntuMaintenance.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } | Should -Throw '*cleanup exit=5*'
        [IO.File]::ReadAllText($script:Log) | Should -Match 'FAILED'
        [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
    }
    It 'preserves a primary error if writing its failure log also fails' {
        Mock Invoke-VhdCompaction { throw 'primary compact failure' }
        Mock Write-MaintenanceLog {}
        Mock Write-MaintenanceLog { throw 'synthetic log failure' } -ParameterFilter { $Message -like '*FAILED*' }
        { & (Join-Path $script:WrapperRoot 'Invoke-VhdCompaction.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false -WarningAction SilentlyContinue } |
            Should -Throw '*primary compact failure*'
    }
    It 'preflights the WMI engine before VHD checks, logging, powercfg or pagefiles' {
        Mock Get-MaintenanceVhdPreflight {
            Should -Invoke Assert-MaintenanceWmiAvailable -Times 1 -Exactly
            'C:\synthetic.vhdx'
        }
        Mock New-MaintenanceLogPath {
            param($LogPath)
            Should -Invoke Get-MaintenanceVhdPreflight -Times 1 -Exactly
            $LogPath
        }
        Mock Invoke-MaintenanceNativeCommand {
            Should -Invoke New-MaintenanceLogPath -Times 1 -Exactly
            [pscustomobject]@{ ExitCode = 0; Output = 'ok' }
        }
        Mock Set-CPageFileSize {
            Should -Invoke Invoke-MaintenanceNativeCommand -Times 1 -Exactly
            'ok'
        }
        & (Join-Path $script:WrapperRoot 'Invoke-SystemCleanup.ps1') -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false
        Should -Invoke Set-CPageFileSize -Times 1 -Exactly
    }
    It 'rejects unavailable WMI before every VHD probe, log creation, or mutation' {
        Mock Assert-MaintenanceWmiAvailable { throw 'requires Windows PowerShell 5.1 and Get-WmiObject' }
        Mock New-MaintenanceLogPath { throw 'must not allocate log' }
        { & (Join-Path $script:WrapperRoot 'Invoke-SystemCleanup.ps1') -VhdPath 'C:\synthetic.vhdx' -Confirm:$false } |
            Should -Throw '*Windows PowerShell 5.1*'
        Should -Invoke Get-MaintenanceVhdPreflight -Times 0 -Exactly
        Should -Invoke New-MaintenanceLogPath -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Set-CPageFileSize -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
    }
    It 'rejects every VHD preflight failure before hibernation, pagefiles or logs' {
        Mock New-MaintenanceLogPath { throw 'must not allocate log' }
        foreach ($failure in @('bad VHD format', 'Storage unavailable', 'already attached', 'not exclusive')) {
            Mock Get-MaintenanceVhdPreflight -MockWith ([scriptblock]::Create("throw '$failure'"))
            foreach ($name in $script:WrapperNames) {
                { & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false } |
                    Should -Throw "*$failure*"
            }
        }
        Test-Path -LiteralPath $script:Log | Should -BeFalse
        Should -Invoke New-MaintenanceLogPath -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Set-CPageFileSize -Times 0 -Exactly
        Should -Invoke Set-CPageFileRegistrySize -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
    }
    It 'does not even allocate default log paths under WhatIf' {
        Mock New-MaintenanceLogPath { throw 'must not allocate log' }
        foreach ($name in $script:WrapperNames) {
            & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -WhatIf
        }
        Should -Invoke New-MaintenanceLogPath -Times 0 -Exactly
        Should -Invoke Assert-MaintenanceWmiAvailable -Times 0 -Exactly
        Should -Invoke Get-MaintenanceVhdPreflight -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $script:FixtureRoot '.local') | Should -BeFalse
    }
    It 'fails before native operations when creating the log fails' {
        Mock New-MaintenanceLogPath { throw 'synthetic log directory failure' }
        foreach ($name in $script:WrapperNames) {
            { & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -Confirm:$false } |
                Should -Throw '*log directory failure*'
        }
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Set-CPageFileSize -Times 0 -Exactly
        Should -Invoke Set-CPageFileRegistrySize -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
    }
    It 'never writes Done or mutates when the initial log write fails' {
        Mock Write-MaintenanceLog { throw 'synthetic initial log failure' }
        foreach ($name in $script:WrapperNames) {
            { & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -LogPath $script:Log -Confirm:$false -WarningAction SilentlyContinue } |
                Should -Throw '*initial log failure*'
        }
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Invoke-VhdCompaction -Times 0 -Exactly
        Should -Invoke Write-MaintenanceLog -Times 0 -Exactly -ParameterFilter { $Message -like '*=== Done *' }
    }
    It 'uses distinct default log files for successive approved runs' {
        Mock New-MaintenanceLogPath {
            Join-Path $TestDrive ('generated-' + ([guid]::NewGuid().ToString('N')) + '.log')
        }
        foreach ($name in $script:WrapperNames) {
            & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -Confirm:$false
            & (Join-Path $script:WrapperRoot $name) -VhdPath 'C:\synthetic.vhdx' -Confirm:$false
        }
        $logs = @(Get-ChildItem -LiteralPath $TestDrive -Filter 'generated-*.log')
        $logs.Count | Should -Be 8
        foreach ($log in $logs) { [IO.File]::ReadAllText($log.FullName) | Should -Match '=== Done ' }
        Should -Invoke New-MaintenanceLogPath -Times 8 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($LogPath) }
    }
    It 'raw reference templates cannot attach or detach and contain no error suppression' {
        foreach ($name in @('compact_docker.txt', 'compact_ubuntu.txt')) {
            $lines = @(Get-Content -LiteralPath (Join-Path $ProjectRoot "docs\reference\$name") |
                Where-Object { $_ -notmatch '^rem\s' -and $_.Trim().Length -gt 0 })
            ($lines -join '|') | Should -Be 'select vdisk file="__VALIDATED_VHD_PATH__"|compact vdisk|exit'
        }
    }
}

Describe 'Preflight ordering and engine support' {
    BeforeEach {
        $script:Order = New-Object 'System.Collections.Generic.List[string]'
        Mock Resolve-MaintenanceVhdPath { $script:Order.Add('path'); 'C:\synthetic.vhdx' }
        Mock Assert-MaintenanceStorageCommands { $script:Order.Add('storage') }
        Mock Assert-MaintenanceVhdDetached { $script:Order.Add('detached') }
        Mock Assert-MaintenanceVhdExclusiveAccess { $script:Order.Add('exclusive') }
    }
    It 'validates the literal format before Storage, ownership and exclusive access' {
        Get-MaintenanceVhdPreflight -Path 'C:\synthetic.vhdx' | Should -Be 'C:\synthetic.vhdx'
        ($script:Order -join '|') | Should -Be 'path|storage|detached|exclusive'
    }
    It 'does not probe Storage or ownership for an invalid image path' {
        Mock Resolve-MaintenanceVhdPath { throw 'invalid path' }
        { Get-MaintenanceVhdPreflight -Path 'invalid' } | Should -Throw '*invalid path*'
        Should -Invoke Assert-MaintenanceStorageCommands -Times 0 -Exactly
        Should -Invoke Assert-MaintenanceVhdDetached -Times 0 -Exactly
        Should -Invoke Assert-MaintenanceVhdExclusiveAccess -Times 0 -Exactly
    }
    It 'does not probe attachment or open the image without supported Storage APIs' {
        Mock Assert-MaintenanceStorageCommands { throw 'missing Storage' }
        { Get-MaintenanceVhdPreflight -Path 'C:\synthetic.vhdx' } | Should -Throw '*missing Storage*'
        Should -Invoke Assert-MaintenanceVhdDetached -Times 0 -Exactly
        Should -Invoke Assert-MaintenanceVhdExclusiveAccess -Times 0 -Exactly
    }
    It 'rejects PS7 even if a Get-WmiObject function happens to be defined' {
        if ($PSVersionTable.PSVersion.Major -eq 5) {
            Assert-MaintenanceWmiAvailable # Our safety stub is discoverable, never invoked.
        }
        else {
            { Assert-MaintenanceWmiAvailable } | Should -Throw '*Windows PowerShell 5.1*PowerShell 7*'
        }
        # The stub throws on any real WMI access; this guard only resolves metadata.
    }
    It 'fails clearly for missing Get-WmiObject without querying WMI' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-WmiObject' }
        { Assert-MaintenanceWmiAvailable } | Should -Throw '*Get-WmiObject*'
    }
    It 'checks the WMI engine guard before attempting pagefile queries' {
        Mock Assert-MaintenanceWmiAvailable { throw 'synthetic unsupported engine' }
        Mock Get-WmiObject { throw 'must not query' }
        { Set-CPageFileSize -Confirm:$false } | Should -Throw '*unsupported engine*'
        Should -Invoke Get-WmiObject -Times 0 -Exactly
    }
}

Describe 'Default log naming and literal custom paths' {
    It 'allocates unique repository-local log names without opening a file' {
        Mock Test-Path { $false }
        Mock New-Item {}
        $first = New-MaintenanceLogPath -Operation 'synthetic-test'
        $second = New-MaintenanceLogPath -Operation 'synthetic-test'
        $first | Should -Not -Be $second
        $first | Should -Match '\\.local\\logs\\synthetic-test-\d{8}-\d{6}-\d{3}-[a-f0-9]{32}\.log$'
        (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $first))) | Should -Be $ProjectRoot
        Should -Invoke New-Item -Times 2 -Exactly -ParameterFilter { $ItemType -eq 'Directory' }
    }
    It 'creates a custom log parent and preserves brackets as literal file characters' {
        $log = Join-Path $TestDrive 'new-log-parent\literal [one].log'
        New-MaintenanceLogPath -Operation 'synthetic-test' -LogPath $log | Should -Be $log
        Write-MaintenanceLog -LogPath $log -Start -Message 'exact log'
        [IO.File]::ReadAllText($log).Trim() | Should -Be 'exact log'
    }
    It 'does not replace primary errors when log failure warnings are configured to Stop' {
        Mock Write-MaintenanceLog { throw 'synthetic log failure' }
        { Write-MaintenanceFailure -LogPath 'synthetic.log' -Failure 'primary error' -WarningAction Stop } | Should -Not -Throw
    }
}

Describe 'Standalone hibernation and Handle diagnostic' {
    BeforeAll {
        $script:StandaloneRoot = Join-Path $TestDrive 'standalone'
        $script:MaintenanceRoot = Join-Path $script:StandaloneRoot 'scripts\maintenance'
        $script:DiagnosticRoot = Join-Path $script:StandaloneRoot 'scripts\diagnostics'
        $null = New-Item -Path $script:MaintenanceRoot -ItemType Directory -Force
        $null = New-Item -Path $script:DiagnosticRoot -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $script:StandaloneRoot 'src') -ItemType Directory -Force
        [IO.File]::WriteAllText((Join-Path $script:StandaloneRoot 'src\VhdMaintenance.ps1'), '# Pester supplies dependencies.')
        $script:HibernateScript = Join-Path $script:MaintenanceRoot 'Disable-Hibernation.ps1'
        $script:HandleScript = Join-Path $script:DiagnosticRoot 'Find-OpenHandles.ps1'
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts\maintenance\Disable-Hibernation.ps1') -Destination $script:HibernateScript
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'scripts\diagnostics\Find-OpenHandles.ps1') -Destination $script:HandleScript
    }
    BeforeEach {
        $script:Log = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.log')
        Mock Invoke-MaintenanceNativeCommand { [pscustomobject]@{ ExitCode = 0; Output = 'synthetic success' } }
        Mock Resolve-MaintenanceHandleExecutable { param($Path) $Path }
        Mock Get-WmiObject { throw 'SAFETY: unexpected WMI' }
        Mock Set-ItemProperty { throw 'SAFETY: unexpected registry' }
    }
    It 'hibernation WhatIf performs no logging, native commands or system reads' {
        Mock New-MaintenanceLogPath { throw 'must not allocate log' }
        & $script:HibernateScript -LogPath $script:Log -WhatIf
        Test-Path -LiteralPath $script:Log | Should -BeFalse
        Should -Invoke New-MaintenanceLogPath -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke Get-WmiObject -Times 0 -Exactly
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }
    It 'hibernation can run without creating a log' {
        Mock New-MaintenanceLogPath { throw 'must not allocate log' }
        (& $script:HibernateScript -Confirm:$false).ExitCode | Should -Be 0
        Should -Invoke New-MaintenanceLogPath -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 1 -Exactly -ParameterFilter {
            $FileName -eq 'powercfg.exe' -and ($ArgumentList -join '|') -eq '/h|off' -and $Confirm -eq $false
        }
    }
    It 'hibernation logs only successful completion with an explicit log' {
        $null = & $script:HibernateScript -LogPath $script:Log -Confirm:$false
        [IO.File]::ReadAllText($script:Log) | Should -Match '=== Done '
    }
    It 'hibernation propagates native failure and never logs Done' {
        Mock Invoke-MaintenanceNativeCommand { throw 'powercfg.exe exit=5' }
        { & $script:HibernateScript -LogPath $script:Log -Confirm:$false } | Should -Throw '*powercfg.exe exit=5*'
        [IO.File]::ReadAllText($script:Log) | Should -Match 'FAILED'
        [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
    }
    It 'Handle WhatIf cannot accept EULA, probe executables, or allocate logs' {
        Mock New-MaintenanceLogPath { throw 'must not allocate log' }
        & $script:HandleScript -Search 'synthetic volume' -AcceptEula -LogPath $script:Log -WhatIf
        Test-Path -LiteralPath $script:Log | Should -BeFalse
        Should -Invoke Resolve-MaintenanceHandleExecutable -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Should -Invoke New-MaintenanceLogPath -Times 0 -Exactly
    }
    It 'Handle requires explicit EULA consent before binary inspection or logs' {
        { & $script:HandleScript -Search 'synthetic volume' -LogPath $script:Log -Confirm:$false } |
            Should -Throw '*-AcceptEula*'
        Should -Invoke Resolve-MaintenanceHandleExecutable -Times 0 -Exactly
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Test-Path -LiteralPath $script:Log | Should -BeFalse
    }
    It 'Handle uses the vendor-local default executable and exact search argument' {
        $null = & $script:HandleScript -Search 'F:\ [literal]' -AcceptEula -LogPath $script:Log -Confirm:$false
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 1 -Exactly -ParameterFilter {
            $FileName -eq 'handle64.exe' -and
            $ExecutablePath -eq (Join-Path $script:StandaloneRoot '.local\vendor\sysinternals\handle64.exe') -and
            ($ArgumentList -join '|') -eq '-accepteula|-a|-nobanner|F:\ [literal]' -and $Confirm -eq $false
        }
        [IO.File]::ReadAllText($script:Log) | Should -Match '=== Done '
    }
    It 'Handle honors an explicit executable path without falling back to PATH' {
        $null = & $script:HandleScript -Search 'volume-guid' -ExecutablePath 'C:\synthetic\signed handle.exe' -AcceptEula -LogPath $script:Log -Confirm:$false
        Should -Invoke Resolve-MaintenanceHandleExecutable -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\synthetic\signed handle.exe' }
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 1 -Exactly -ParameterFilter { $ExecutablePath -eq 'C:\synthetic\signed handle.exe' }
    }
    It 'Handle rejects option-shaped and control-character search text' {
        foreach ($search in @('-c', "bad`ntext")) {
            { & $script:HandleScript -Search $search -AcceptEula -LogPath $script:Log -Confirm:$false } | Should -Throw '*Search must be literal*'
        }
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Test-Path -LiteralPath $script:Log | Should -BeFalse
    }
    It 'Handle rejects untrusted executables before logging or execution' {
        Mock Resolve-MaintenanceHandleExecutable { throw 'invalid Microsoft signature' }
        { & $script:HandleScript -Search 'volume' -AcceptEula -LogPath $script:Log -Confirm:$false } | Should -Throw '*signature*'
        Should -Invoke Invoke-MaintenanceNativeCommand -Times 0 -Exactly
        Test-Path -LiteralPath $script:Log | Should -BeFalse
    }
    It 'Handle preserves native failure and does not write Done' {
        Mock Invoke-MaintenanceNativeCommand { throw 'handle64.exe exit=5' }
        { & $script:HandleScript -Search 'volume' -AcceptEula -LogPath $script:Log -Confirm:$false } | Should -Throw '*handle64.exe exit=5*'
        [IO.File]::ReadAllText($script:Log) | Should -Match 'FAILED'
        [IO.File]::ReadAllText($script:Log) | Should -Not -Match '=== Done '
    }
}

Describe 'Signed Handle executable validation' {
    BeforeEach {
        $script:Executable = Join-Path $TestDrive 'synthetic handle.exe'
        [IO.File]::WriteAllText($script:Executable, 'not an executable; never run')
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US' } }
        }
    }
    It 'accepts only a validated local Microsoft signature' {
        Resolve-MaintenanceHandleExecutable -Path $script:Executable | Should -Be $script:Executable
        Should -Invoke Get-AuthenticodeSignature -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $script:Executable }
    }
    It 'rejects remote, relative, ADS and wildcard executable paths before reading files' {
        Mock Get-Item { throw 'must not read rejected paths' }
        foreach ($path in @('handle64.exe', '\\server\share\handle.exe', 'C:\handle.exe:stream', 'C:\*.exe')) {
            { Resolve-MaintenanceHandleExecutable -Path $path } | Should -Throw '*absolute local executable*'
        }
        Should -Invoke Get-Item -Times 0 -Exactly
        Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
    }
    It 'rejects invalid signatures even with a Microsoft-looking subject' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation' } }
        }
        { Resolve-MaintenanceHandleExecutable -Path $script:Executable } | Should -Throw '*valid Microsoft Corporation*'
    }
    It 'rejects a valid but non-Microsoft publisher' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Untrusted Microsoft Corporation Impersonator' } }
        }
        { Resolve-MaintenanceHandleExecutable -Path $script:Executable } | Should -Throw '*valid Microsoft Corporation*'
    }
    It 'rejects unsigned files and missing signer certificates' {
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
        { Resolve-MaintenanceHandleExecutable -Path $script:Executable } | Should -Throw '*valid Microsoft Corporation*'
    }
    It 'rejects reparse point executables without inspecting their signature' {
        Mock Get-Item {
            [pscustomobject]@{ PSProvider = @{ Name = 'FileSystem' }; PSIsContainer = $false; Extension = '.exe'; Attributes = [IO.FileAttributes]::ReparsePoint }
        }
        { Resolve-MaintenanceHandleExecutable -Path $script:Executable } | Should -Throw '*Reparse-point*'
        Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
    }
    It 'propagates signed Handle native errors using only a synthetic function boundary' {
        $script:FakeExitCode = 5
        Mock Resolve-MaintenanceHandleExecutable { 'Invoke-TestNative' }
        { Invoke-MaintenanceNativeCommand -FileName handle64.exe -ExecutablePath $script:Executable -ArgumentList @('synthetic') -Confirm:$false } |
            Should -Throw '*handle64.exe exit=5*synthetic native output*'
    }
    It 'does not resolve Handle executables under native WhatIf' {
        Mock Resolve-MaintenanceHandleExecutable { throw 'must not inspect' }
        Invoke-MaintenanceNativeCommand -FileName handle64.exe -ExecutablePath $script:Executable -ArgumentList @('synthetic') -WhatIf
        Should -Invoke Resolve-MaintenanceHandleExecutable -Times 0 -Exactly
    }
}

Describe 'Reconstructed maintenance source contracts' {
    It 'all compaction scripts require VhdPath without account or distro defaults' {
        foreach ($name in @('Invoke-VhdCompaction', 'Invoke-UbuntuMaintenance', 'Invoke-SystemCleanup', 'Set-PagefileAndCompact')) {
            $path = Join-Path $ProjectRoot "scripts\maintenance\$name.ps1"
            $command = Get-Command -Name $path
            $parameter = $command.Parameters['VhdPath']
            @($parameter.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1
            $source = Get-Content -LiteralPath $path -Raw
            $source | Should -Not -Match '\$VhdPath\s*=|C:\\Users\\|AppData|\{ddda|docker_data'
        }
    }
    It 'all six entrypoints import src using the real two-level layout and declare confirmation' {
        $paths = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts\maintenance') -Filter '*.ps1') +
            @(Get-Item -LiteralPath (Join-Path $ProjectRoot 'scripts\diagnostics\Find-OpenHandles.ps1'))
        foreach ($path in $paths) {
            $source = Get-Content -LiteralPath $path.FullName -Raw
            $source | Should -Match 'Join-Path \(Split-Path -Parent \(Split-Path -Parent \$PSScriptRoot\)\) ''src\\VhdMaintenance.ps1'''
            $source | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
            $source | Should -Match "ConfirmImpact\s*=\s*'High'"
            $source | Should -Not -Match 'C:\\Users\\|Start-Sleep|Stop-Process|wsl\.exe'
        }
    }
    It 'Handle Search is mandatory and AcceptEula is an explicit switch' {
        $command = Get-Command -Name (Join-Path $ProjectRoot 'scripts\diagnostics\Find-OpenHandles.ps1')
        @($command.Parameters['Search'].Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1
        $command.Parameters['AcceptEula'].ParameterType | Should -Be ([Management.Automation.SwitchParameter])
    }
    It 'reference templates name existing reconstructed scripts without historical absolute paths' {
        foreach ($name in @('compact_docker.txt', 'compact_ubuntu.txt')) {
            $source = Get-Content -LiteralPath (Join-Path $ProjectRoot "docs\reference\$name") -Raw
            $source | Should -Match 'scripts\\maintenance\\Invoke-.*\.ps1 with explicit -VhdPath'
            $source | Should -Not -Match 'C:\\Users\\|admin_compact|default:|noerr|attach vdisk|detach vdisk'
        }
    }
}
