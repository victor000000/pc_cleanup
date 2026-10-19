# Pester 5.5.0; run in a fresh powershell.exe -NoProfile process.
# All inventory/native boundaries are mocked. No real eject or system changes.
Describe 'USB eject safety (no real device operations)' {
BeforeAll {
    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:LibraryPath = Join-Path $script:ProjectRoot 'src\UsbEject.ps1'
    . $script:LibraryPath

    # Local throwing commands prevent Pester mock creation from importing Storage
    # (or touching real platform commands). Every external boundary is a tripwire.
    function Get-Disk { [CmdletBinding()] param() throw 'Unmocked disk inventory.' }
    function Get-CimInstance { [CmdletBinding()] param($ClassName, $Filter) throw 'Unmocked CIM inventory.' }
    function Add-Type { [CmdletBinding()] param($TypeDefinition) throw 'Unmocked native compilation.' }
    function Stop-Service { [CmdletBinding()] param($Name) throw 'Unmocked service stop.' }
    function Start-Service { [CmdletBinding()] param($Name) throw 'Unmocked service start.' }
    function Set-Service { [CmdletBinding()] param($Name) throw 'Unmocked service change.' }
    function Stop-Process { [CmdletBinding()] param($Id, $Name) throw 'Unmocked process stop.' }
    function Set-Disk { [CmdletBinding()] param($InputObject, $IsOffline) throw 'Unmocked disk mutation.' }
    function Write-VolumeCache { [CmdletBinding()] param($DriveLetter) throw 'Unmocked volume mutation.' }

    function New-TestUsbDisk {
        [pscustomobject]@{
            UniqueId = 'test-unique-id'
            SerialNumber = 'test-serial'
            Number = [uint32] 42
            BusType = 'USB'
            IsBoot = $false
            IsSystem = $false
        }
    }
}

BeforeEach {
    # Tripwires beneath the helpers as well as the mocks in each test group.
    Mock Get-Disk { throw 'Real inventory access is forbidden in these tests.' }
    Mock Get-CimInstance { throw 'Real CIM access is forbidden in these tests.' }
    Mock Add-Type { throw 'Loading native interop is forbidden in these tests.' }
    Mock Stop-Service { throw 'Service changes are forbidden.' }
    Mock Start-Service { throw 'Service changes are forbidden.' }
    Mock Set-Service { throw 'Service changes are forbidden.' }
    Mock Stop-Process { throw 'Process termination is forbidden.' }
    Mock Set-Disk { throw 'Disk changes are forbidden.' }
    Mock Write-VolumeCache { throw 'Cache changes are forbidden.' }
}

AfterEach {
    Should -Invoke Stop-Service -Times 0 -Exactly
    Should -Invoke Start-Service -Times 0 -Exactly
    Should -Invoke Set-Service -Times 0 -Exactly
    Should -Invoke Stop-Process -Times 0 -Exactly
    Should -Invoke Set-Disk -Times 0 -Exactly
    Should -Invoke Write-VolumeCache -Times 0 -Exactly
    Should -Invoke Add-Type -Times 0 -Exactly
}

Describe 'Stable-identity safe eject' {
    BeforeEach {
        $script:TestInventory = @(New-TestUsbDisk)
        $script:TestInstanceId = 'USBSTOR\DISK&VEN_TEST&PROD_USB\TEST_SERIAL&0'
        Mock Get-UsbEjectInventory { $script:TestInventory }
        Mock Get-UsbEjectDiskInstanceId { $script:TestInstanceId }
        Mock Invoke-UsbEjectNativeRequest { }
    }

    It 'requires explicit identity before inventory lookup' {
        { Invoke-SafeUsbEject -Confirm:$false } | Should -Throw '*exactly one*'
        Should -Invoke Get-UsbEjectInventory -Times 0 -Exactly
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects empty or whitespace <Property> identity (<Value>)' -ForEach @(
        @{ Property = 'UniqueId'; Value = '' }
        @{ Property = 'UniqueId'; Value = '   ' }
        @{ Property = 'SerialNumber'; Value = $null }
        @{ Property = 'SerialNumber'; Value = '  ' }
    ) {
        $arguments = @{ $Property = $Value; Confirm = $false }
        { Invoke-SafeUsbEject @arguments } | Should -Throw '*nonempty stable disk identity*'
        Should -Invoke Get-UsbEjectInventory -Times 0 -Exactly
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects two identity selectors' {
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -SerialNumber 'test-serial' -Confirm:$false } |
            Should -Throw '*exactly one*'
        Should -Invoke Get-UsbEjectInventory -Times 0 -Exactly
    }

    It 'rejects absent identities and does not interpret wildcards' -ForEach @(
        @{ Identity = 'unknown' }
        @{ Identity = 'test-*' }
        @{ Identity = '42' }
        @{ Identity = 'F:' }
    ) {
        { Invoke-SafeUsbEject -UniqueId $Identity -Confirm:$false } | Should -Throw '*found 0*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects ambiguous <Property>' -ForEach @(
        @{ Property = 'UniqueId'; Value = 'test-unique-id' }
        @{ Property = 'SerialNumber'; Value = 'test-serial' }
    ) {
        $script:TestInventory = @(New-TestUsbDisk; New-TestUsbDisk)
        $arguments = @{ $Property = $Value; Confirm = $false }
        { Invoke-SafeUsbEject @arguments } | Should -Throw '*found 2*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects unsafe or unknown <Property> = <Value>' -ForEach @(
        @{ Property = 'BusType'; Value = 'SATA' }
        @{ Property = 'BusType'; Value = 'NVMe' }
        @{ Property = 'BusType'; Value = $null }
        @{ Property = 'IsBoot'; Value = $true }
        @{ Property = 'IsSystem'; Value = $true }
        @{ Property = 'IsBoot'; Value = $null }
        @{ Property = 'IsSystem'; Value = $null }
        @{ Property = 'IsBoot'; Value = 'False' }
        @{ Property = 'Number'; Value = -1 }
    ) {
        $script:TestInventory[0].$Property = $Value
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*Refusing eject*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'supports WhatIf without any native call or success output' {
        $result = @(Invoke-SafeUsbEject -UniqueId 'test-unique-id' -WhatIf)
        $result.Count | Should -Be 0
        Should -Invoke Get-UsbEjectInventory -Times 1 -Exactly
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'uses High confirmation impact and SupportsShouldProcess' {
        $metadata = New-Object System.Management.Automation.CommandMetadata (Get-Command Invoke-SafeUsbEject)
        $metadata.SupportsShouldProcess | Should -BeTrue
        $metadata.ConfirmImpact | Should -Be 'High'
    }

    It 'accepts exact stable <Property> after fresh revalidation' -ForEach @(
        @{ Property = 'UniqueId'; Value = 'TEST-UNIQUE-ID' }
        @{ Property = 'SerialNumber'; Value = ' test-serial ' }
    ) {
        $arguments = @{ $Property = $Value; Confirm = $false }
        $result = Invoke-SafeUsbEject @arguments
        $result.Status | Should -Be 'EjectRequested'
        $result.IdentityProperty | Should -Be $Property
        $result.Identity | Should -Be $Value.Trim()
        $result.DeviceInstanceId | Should -Be $script:TestInstanceId
        Should -Invoke Get-UsbEjectInventory -Times 2 -Exactly
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 1 -Exactly -ParameterFilter {
            $InstanceId -eq 'USBSTOR\DISK&VEN_TEST&PROD_USB\TEST_SERIAL&0'
        }
    }

    It 'propagates a veto without retrying another node' {
        Mock Invoke-UsbEjectNativeRequest { throw 'Eject failed or vetoed: test blocker.' }
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*vetoed*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 1 -Exactly
    }

    It 'rejects disappearance during confirmation' {
        Mock Get-UsbEjectInventory {
            $script:TestInventory
            $script:TestInventory = @()
        }
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*found 0*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rechecks boot/system/USB safety after confirmation' {
        Mock Get-UsbEjectDiskInstanceId {
            $script:TestInventory[0].IsSystem = $true
            $script:TestInstanceId
        }
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*boot/system*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects disk number changes even if the inventory object is reused' {
        Mock Get-UsbEjectDiskInstanceId {
            $script:TestInventory[0].Number = [uint32]43
            $script:TestInstanceId
        }
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*mapping changed*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rechecks <Property> after confirmation (<Value>)' -ForEach @(
        @{ Property = 'BusType'; Value = 'SATA' }
        @{ Property = 'IsBoot'; Value = $true }
        @{ Property = 'IsBoot'; Value = $null }
        @{ Property = 'IsSystem'; Value = 'False' }
    ) {
        $script:ChangedProperty = $Property
        $script:ChangedValue = $Value
        Mock Get-UsbEjectDiskInstanceId {
            $script:TestInventory[0].($script:ChangedProperty) = $script:ChangedValue
            $script:TestInstanceId
        }
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*Refusing eject*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects a disk mapping change during confirmation' {
        $script:MappingCalls = 0
        Mock Get-UsbEjectDiskInstanceId {
            $script:MappingCalls++
            if ($script:MappingCalls -eq 1) { $script:TestInstanceId }
            else { 'SCSI\DISK&VEN_TEST&PROD_OTHER\OTHER_SERIAL' }
        }
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*mapping changed*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }

    It 'rejects parent or malformed ID <Id> even from the mapping helper' -ForEach @(
        @{ Id = 'USB\ROOT_HUB30\TEST' }
        @{ Id = 'USB\VID_1234&PID_5678\TEST' }
        @{ Id = 'PCI\VEN_1234&DEV_5678\TEST' }
        @{ Id = 'ACPI\TEST\TEST' }
        @{ Id = 'USBSTOR\DISK&VEN_TEST' }
        @{ Id = "USBSTOR\DISK&VEN_TEST\TEST`n" }
    ) {
        $script:TestInstanceId = $Id
        { Invoke-SafeUsbEject -UniqueId 'test-unique-id' -Confirm:$false } | Should -Throw '*invalid disk device instance ID*'
        Should -Invoke Invoke-UsbEjectNativeRequest -Times 0 -Exactly
    }
}

Describe 'Read-only disk node mapping' {
    BeforeEach {
        $script:TestDevice = [pscustomobject]@{
            Index = 42
            PNPDeviceID = 'SCSI\DISK&VEN_TEST&PROD_USB\TEST_SERIAL'
        }
        Mock Get-CimInstance { $script:TestDevice }
    }

    It 'maps only the validated current disk index to a disk PnP ID' {
        Get-UsbEjectDiskInstanceId -Disk (New-TestUsbDisk) | Should -Be $script:TestDevice.PNPDeviceID
        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_DiskDrive' -and $Filter -eq 'Index = 42' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'rejects missing, ambiguous, mismatched or non-disk mappings (<Case>)' -ForEach @(
        @{ Case = 'missing' }
        @{ Case = 'ambiguous' }
        @{ Case = 'mismatched' }
        @{ Case = 'hub' }
    ) {
        switch ($Case) {
            'missing' { $script:TestDevice = @() }
            'ambiguous' { $script:TestDevice = @($script:TestDevice, $script:TestDevice) }
            'mismatched' { $script:TestDevice.Index = 43 }
            'hub' { $script:TestDevice.PNPDeviceID = 'USB\ROOT_HUB30\TEST' }
        }
        { Get-UsbEjectDiskInstanceId -Disk (New-TestUsbDisk) } | Should -Throw '*Refusing eject*'
    }
}

Describe 'Native result validation without native calls' {
    BeforeEach {
        $script:NativeId = 'USBSTOR\DISK&VEN_TEST&PROD_USB\TEST_SERIAL&0'
        $script:LocateResult = [pscustomobject]@{ ReturnCode = [uint32] 0; DevInst = [uint32] 123 }
        $script:IdResult = [pscustomobject]@{ ReturnCode = [uint32] 0; InstanceId = $script:NativeId }
        $script:EjectResult = [pscustomobject]@{ ReturnCode = [uint32] 0; VetoType = [uint32] 0; VetoName = '' }
        Mock Invoke-UsbEjectCm {
            switch ($Operation) {
                'Locate' { $script:LocateResult }
                'GetDeviceId' { $script:IdResult }
                'RequestEject' { $script:EjectResult }
                default { throw 'Unexpected operation; parent escalation is forbidden.' }
            }
        }
    }

    It 'makes exactly one disk request with a UInt32 DEVINST' {
        Invoke-UsbEjectNativeRequest -InstanceId $script:NativeId
        Should -Invoke Invoke-UsbEjectCm -Times 3 -Exactly
        Should -Invoke Invoke-UsbEjectCm -Times 1 -Exactly -ParameterFilter {
            $Operation -eq 'RequestEject' -and $DevInst -is [uint32] -and $DevInst -eq 123
        }
    }

    It 'fails before native access for a hub ID' {
        { Invoke-UsbEjectNativeRequest -InstanceId 'USB\ROOT_HUB30\TEST' } | Should -Throw '*invalid disk device instance ID*'
        Should -Invoke Invoke-UsbEjectCm -Times 0 -Exactly
    }

    It 'rejects locate failure or invalid DEVINST (<Case>)' -ForEach @(
        @{ Case = 'CM failure'; Code = 13; Node = 123 }
        @{ Case = 'zero'; Code = 0; Node = 0 }
        @{ Case = 'negative'; Code = 0; Node = -1 }
        @{ Case = 'overflow'; Code = 0; Node = 4294967296 }
        @{ Case = 'missing result'; Code = $null; Node = $null }
    ) {
        $script:LocateResult = [pscustomobject]@{ ReturnCode = $Code; DevInst = $Node }
        { Invoke-UsbEjectNativeRequest -InstanceId $script:NativeId } | Should -Throw '*CM_Locate_DevNodeW failed*'
        Should -Invoke Invoke-UsbEjectCm -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RequestEject' }
    }

    It 'rejects failed ID read, mismatched ID, or hub ID (<Case>)' -ForEach @(
        @{ Case = 'CM failure'; Code = 13; Id = 'USBSTOR\DISK&VEN_TEST\TEST' }
        @{ Case = 'missing code'; Code = $null; Id = 'USBSTOR\DISK&VEN_TEST\TEST' }
        @{ Case = 'different disk'; Code = 0; Id = 'USBSTOR\DISK&VEN_TEST\OTHER' }
        @{ Case = 'hub'; Code = 0; Id = 'USB\ROOT_HUB30\TEST' }
    ) {
        $script:IdResult = [pscustomobject]@{ ReturnCode = $Code; InstanceId = $Id }
        { Invoke-UsbEjectNativeRequest -InstanceId $script:NativeId } | Should -Throw
        Should -Invoke Invoke-UsbEjectCm -Times 0 -Exactly -ParameterFilter { $Operation -eq 'RequestEject' }
    }

    It 'throws on veto/error without escalation or retries (<Case>)' -ForEach @(
        @{ Case = 'veto'; Code = 23; Veto = 5 }
        @{ Case = 'nonzero veto despite success code'; Code = 0; Veto = 5 }
        @{ Case = 'CM failure'; Code = 13; Veto = 0 }
        @{ Case = 'incomplete result'; Code = $null; Veto = $null }
    ) {
        $script:EjectResult = [pscustomobject]@{ ReturnCode = $Code; VetoType = $Veto; VetoName = 'test-blocker' }
        { Invoke-UsbEjectNativeRequest -InstanceId $script:NativeId } | Should -Throw '*vetoed*test-blocker*'
        Should -Invoke Invoke-UsbEjectCm -Times 3 -Exactly
        Should -Invoke Invoke-UsbEjectCm -Times 1 -Exactly -ParameterFilter { $Operation -eq 'RequestEject' }
    }
}

Describe 'Legacy entry points and source safety' {
    BeforeEach {
        Mock Get-Disk { New-TestUsbDisk }
        Mock Get-CimInstance {
            [pscustomobject]@{ Index = 42; PNPDeviceID = 'USBSTOR\DISK&VEN_TEST\TEST_SERIAL&0' }
        }
    }

    It '<Name> forwards WhatIf safely and rejects missing identity' -ForEach @(
        @{ Name = 'compat\eject_f.ps1' }
        @{ Name = 'compat\eject_f2.ps1' }
        @{ Name = 'compat\eject_f_admin.ps1' }
        @{ Name = 'compat\admin_eject2.ps1' }
        @{ Name = 'compat\admin_eject3.ps1' }
        @{ Name = 'compat\admin_eject4.ps1' }
        @{ Name = 'compat\chkdsk_eject_f.ps1' }
        @{ Name = 'storage\Eject-UsbDisk.ps1' }
    ) {
        $path = Join-Path (Join-Path $script:ProjectRoot 'scripts') $Name
        Push-Location $TestDrive
        try {
            @(& $path -UniqueId 'test-unique-id' -WhatIf -WarningAction SilentlyContinue).Count | Should -Be 0
            { & $path -Confirm:$false -WarningAction SilentlyContinue } | Should -Throw '*exactly one*'
        }
        finally { Pop-Location }
        Should -Invoke Get-Disk -Times 1 -Exactly
    }

    It 'retired repair wrapper warns that separate repairs require explicit consent' {
        $warnings = @()
        & (Join-Path $script:ProjectRoot 'scripts\compat\chkdsk_eject_f.ps1') -SerialNumber 'test-serial' -WhatIf -WarningVariable warnings -WarningAction SilentlyContinue
        ($warnings -join ' ') | Should -Match 'separately.*explicit consent'
    }

    It 'all owned files parse on Windows PowerShell 5.1 and contain no destructive commands or parent traversal' {
        $files = @('scripts\compat\eject_f.ps1', 'scripts\compat\eject_f2.ps1',
            'scripts\compat\eject_f_admin.ps1', 'scripts\compat\admin_eject2.ps1',
            'scripts\compat\admin_eject3.ps1', 'scripts\compat\admin_eject4.ps1',
            'scripts\compat\chkdsk_eject_f.ps1', 'scripts\storage\Eject-UsbDisk.ps1', 'src\UsbEject.ps1')
        foreach ($file in $files) {
            $path = Join-Path $script:ProjectRoot $file
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $parseErrors)
            $parseErrors.Count | Should -Be 0 -Because $file
            $commands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true) | ForEach-Object { $_.GetCommandName() })
            $forbidden = @($commands | Where-Object {
                $_ -match '(?i)^(Stop-Service|Start-Service|Set-Service|Stop-Process|Set-Disk|Write-VolumeCache|Dismount-Volume|fsutil(?:\.exe)?|chkdsk(?:\.exe)?)$'
            })
            $forbidden.Count | Should -Be 0 -Because $file
            $source = [System.IO.File]::ReadAllText($path)
            $source | Should -Not -Match 'CM_Get_Parent|IntPtr|CM_Query_And_Remove_SubTree'
        }
        $library = [System.IO.File]::ReadAllText($script:LibraryPath)
        $library | Should -Match 'CM_Locate_DevNodeW\(out uint devInst'
        $library | Should -Match 'CM_Get_Device_IDW\(uint devInst'
        $library | Should -Match 'CM_Request_Device_EjectW\(uint devInst'
    }
}

Describe 'Canonical and compatibility parameter delegation' {
    BeforeAll {
        # Isolated fixture: real entry scripts, deliberately fake src boundary.
        # This observes bound common switches without ever reaching native interop.
        $script:FixtureRoot = Join-Path $TestDrive 'entry-fixture'
        foreach ($directory in @('src', 'scripts\storage', 'scripts\compat')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $script:FixtureRoot $directory) -Force
        }
        Copy-Item (Join-Path $script:ProjectRoot 'scripts\storage\Eject-UsbDisk.ps1') (Join-Path $script:FixtureRoot 'scripts\storage')
        Copy-Item (Join-Path $script:ProjectRoot 'scripts\compat\*.ps1') (Join-Path $script:FixtureRoot 'scripts\compat')
        [System.IO.File]::WriteAllText((Join-Path $script:FixtureRoot 'src\UsbEject.ps1'), @'
function Invoke-SafeUsbEject {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([string]$UniqueId, [string]$SerialNumber)
    $copy = @{}
    foreach ($key in $PSBoundParameters.Keys) { $copy[$key] = $PSBoundParameters[$key] }
    [pscustomobject]@{ Parameters = $copy }
}
'@)
    }

    It '<Name> forwards both identity choices and common switches unchanged' -ForEach @(
        @{ Name = 'compat\eject_f.ps1' }
        @{ Name = 'compat\eject_f2.ps1' }
        @{ Name = 'compat\eject_f_admin.ps1' }
        @{ Name = 'compat\admin_eject2.ps1' }
        @{ Name = 'compat\admin_eject3.ps1' }
        @{ Name = 'compat\admin_eject4.ps1' }
        @{ Name = 'compat\chkdsk_eject_f.ps1' }
        @{ Name = 'storage\Eject-UsbDisk.ps1' }
    ) {
        $path = Join-Path (Join-Path $script:FixtureRoot 'scripts') $Name
        foreach ($identityProperty in @('UniqueId', 'SerialNumber')) {
            foreach ($mode in @('WhatIf', 'ConfirmTrue', 'ConfirmFalse')) {
                $arguments = @{
                    $identityProperty = 'fixture-stable-identity'
                    Verbose = $true; Debug = $false
                    ErrorAction = 'Stop'; WarningAction = 'SilentlyContinue'; InformationAction = 'Continue'
                }
                if ($mode -eq 'WhatIf') { $arguments.WhatIf = $true }
                else { $arguments.Confirm = $mode -eq 'ConfirmTrue' }
                Push-Location $TestDrive
                try { $result = & $path @arguments }
                finally { Pop-Location }
                $result.Parameters.Count | Should -Be $arguments.Count
                foreach ($key in $arguments.Keys) {
                    $result.Parameters.ContainsKey($key) | Should -BeTrue -Because "$Name must forward $key"
                    [string]$result.Parameters[$key] | Should -Be ([string]$arguments[$key])
                }
            }
        }
        Should -Invoke Get-Disk -Times 0 -Exactly
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }
}
}
