# All inventory/mutation boundaries are suite-local throwing stubs before mocking.
Describe 'USB disk identity and recovery (no actual storage operations)' {
BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:ProjectRoot 'src\DiskRecovery.ps1')
    function Get-Disk {
        [CmdletBinding()]
        param()
        throw 'Unmocked disk inventory is forbidden.'
    }
    function Get-Volume {
        [CmdletBinding()]
        param()
        throw 'Unmocked volume inventory is forbidden.'
    }
    function Set-Disk {
        [CmdletBinding()]
        param($InputObject, [bool]$IsOffline)
        throw 'Unmocked disk mutation is forbidden.'
    }
    function Set-Partition {
        [CmdletBinding()]
        param($InputObject, [string]$NewDriveLetter)
        throw 'Unmocked partition mutation is forbidden.'
    }
    function Get-Partition {
        [CmdletBinding()]
        param($DiskNumber, $PartitionNumber)
        throw 'Unmocked partition inventory is forbidden.'
    }
}

    BeforeEach {
        $script:disk = [pscustomobject]@{
            Number = 7; UniqueId = 'usb-stable-id'; BusType = 'USB'; Size = 1TB
            IsBoot = $false; IsSystem = $false; IsOffline = $false; FriendlyName = 'Test USB'
        }
        $script:partition = [pscustomobject]@{
            DiskNumber = 7; PartitionNumber = 2; DriveLetter = 'E'; Type = 'Basic'
            IsBoot = $false; IsSystem = $false
        }
        Mock Get-Disk { $script:disk }
        Mock Get-Partition { $script:partition }
        Mock Get-Volume { @() }
        Mock Set-Disk { $script:disk.IsOffline = $false } -RemoveParameterType InputObject
        Mock Set-Partition {} -RemoveParameterType InputObject
    }

    It 'refuses missing or ambiguous identities' {
        Mock Get-Disk { @() }
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*found 0*'
        Mock Get-Disk { @($script:disk, $script:disk) }
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*found 2*'
    }

    It 'rejects a whitespace-only identity' {
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId '   ' } | Should -Throw '*stable disk UniqueId*'
    }

    It 'rejects non-USB, boot, system, or empty disks' {
        $script:disk.BusType = 'NVMe'
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*non-system USB*'
        $script:disk.BusType = 'USB'; $script:disk.IsBoot = $true
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*non-system USB*'
        $script:disk.IsBoot = $false; $script:disk.IsSystem = $true
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*non-system USB*'
        $script:disk.IsSystem = $false; $script:disk.Size = 0
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*non-system USB*'
    }

    It 'brings the identified disk online regardless of disk number' {
        $script:disk.IsOffline = $true
        $result = Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false
        $result.Number | Should -Be 7
        Should -Invoke Set-Disk -Times 1 -Exactly -ParameterFilter { $InputObject.UniqueId -eq 'usb-stable-id' -and -not $IsOffline }
    }

    It 'does not change an already online disk' {
        Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false
        Should -Invoke Set-Disk -Times 0
    }

    It 'does not bring a disk online during WhatIf' {
        $script:disk.IsOffline = $true
        Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -WhatIf
        Should -Invoke Set-Disk -Times 0
    }

    It 'propagates an online operation failure' {
        $script:disk.IsOffline = $true
        Mock Set-Disk { throw 'online failed' }
        { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw '*online failed*'
    }

    It 'accepts an already-correct drive mapping without changing it' {
        $script:partition.DriveLetter = 'F'
        Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false
        Should -Invoke Set-Partition -Times 0
    }

    It 'refuses a drive letter held by a zero-size unpartitioned volume' {
        Mock Get-Volume { [pscustomobject]@{ DriveLetter = 'F'; Size = 0 } }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*occupied*'
        Should -Invoke Set-Partition -Times 0
    }

    It 'refuses a drive letter held by another partition' {
        Mock Get-Partition { $script:partition } -ParameterFilter { $DiskNumber -eq 7 }
        Mock Get-Partition { [pscustomobject]@{ DriveLetter = 'F'; DiskNumber = 9 } } -ParameterFilter { $null -eq $DiskNumber }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*occupied*'
        Should -Invoke Set-Partition -Times 0
    }

    It 'assigns only the selected USB data partition' {
        Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false
        Should -Invoke Set-Partition -Times 1 -Exactly -ParameterFilter { $InputObject.DiskNumber -eq 7 -and $InputObject.PartitionNumber -eq 2 -and $NewDriveLetter -eq 'F' }
    }

    It 'does not assign a drive letter during WhatIf' {
        Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -WhatIf
        Should -Invoke Set-Partition -Times 0
    }

    It 'refuses offline disks and system partitions' {
        $script:disk.IsOffline = $true
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*Bring*online*'
        $script:disk.IsOffline = $false; $script:partition.IsSystem = $true
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*basic data partition*'
        Should -Invoke Set-Partition -Times 0
    }

    It 'does not remove any mount point when assignment fails' {
        Mock Set-Partition { throw 'assignment failed' }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*assignment failed*'
        Should -Invoke Set-Partition -Times 1 -Exactly
    }

    It 'rejects unknown or invalid disk <Property> = <Value>' -ForEach @(
        @{ Property = 'IsBoot'; Value = $null }
        @{ Property = 'IsSystem'; Value = $null }
        @{ Property = 'IsOffline'; Value = $null }
        @{ Property = 'IsBoot'; Value = 'False' }
        @{ Property = 'IsSystem'; Value = 0 }
        @{ Property = 'IsOffline'; Value = 'False' }
        @{ Property = 'Size'; Value = $null }
        @{ Property = 'Size'; Value = 'unknown' }
        @{ Property = 'Size'; Value = -1 }
        @{ Property = 'Number'; Value = $null }
        @{ Property = 'Number'; Value = -1 }
        @{ Property = 'Number'; Value = 4294967296 }
    ) {
        $script:disk.$Property = $Value
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-stable-id' } | Should -Throw '*non-system USB*'
        Should -Invoke Set-Disk -Times 0 -Exactly
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'matches identity exactly with trim/case normalization but not wildcards' {
        (Get-RecoveryUsbDisk -ExpectedDiskUniqueId ' USB-STABLE-ID ').UniqueId | Should -Be 'usb-stable-id'
        { Get-RecoveryUsbDisk -ExpectedDiskUniqueId 'usb-*' } | Should -Throw '*found 0*'
    }

    It 'fails closed when disk inventory fails' {
        Mock Get-Disk { throw 'inventory unavailable' }
        { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw '*inventory unavailable*'
        Should -Invoke Set-Disk -Times 0 -Exactly
    }

    It 'rejects disappearance during <Operation> confirmation' -ForEach @(
        @{ Operation = 'Online' }; @{ Operation = 'Letter' }
    ) {
        $script:disk.IsOffline = $Operation -eq 'Online'
        $script:DiskReads = 0
        Mock Get-Disk {
            $script:DiskReads++
            if ($script:DiskReads -eq 1) { $script:disk }
        }
        if ($Operation -eq 'Online') {
            { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw '*found 0*'
        }
        else {
            { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*found 0*'
        }
        Should -Invoke Set-Disk -Times 0 -Exactly
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'revalidates <Property> during confirmation for both recovery operations' -ForEach @(
        @{ Property = 'BusType'; Value = 'SATA' }
        @{ Property = 'IsBoot'; Value = $true }
        @{ Property = 'IsSystem'; Value = $true }
        @{ Property = 'IsBoot'; Value = $null }
        @{ Property = 'IsSystem'; Value = 'False' }
        @{ Property = 'IsOffline'; Value = $null }
    ) {
        $script:ChangedProperty = $Property
        $script:ChangedValue = $Value
        foreach ($operation in @('Online', 'Letter')) {
            $script:disk.BusType = 'USB'
            $script:disk.IsBoot = $false
            $script:disk.IsSystem = $false
            $script:disk.IsOffline = $operation -eq 'Online'
            $script:DiskReads = 0
            Mock Get-Disk {
                $script:DiskReads++
                if ($script:DiskReads -eq 2) { $script:disk.($script:ChangedProperty) = $script:ChangedValue }
                $script:disk
            }
            if ($operation -eq 'Online') {
                { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw '*non-system USB*'
            }
            else {
                { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*non-system USB*'
            }
        }
        Should -Invoke Set-Disk -Times 0 -Exactly
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'rejects number changes during <Operation> confirmation, including reused objects' -ForEach @(
        @{ Operation = 'Online' }; @{ Operation = 'Letter' }
    ) {
        $script:disk.IsOffline = $Operation -eq 'Online'
        $script:DiskReads = 0
        Mock Get-Disk {
            $script:DiskReads++
            if ($script:DiskReads -eq 2) { $script:disk.Number = 8 }
            $script:disk
        }
        if ($Operation -eq 'Online') {
            { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw '*number changed*'
        }
        else {
            { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*number changed*'
        }
        Should -Invoke Set-Disk -Times 0 -Exactly
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'does not mutate if the disk becomes online during confirmation' {
        $script:disk.IsOffline = $true
        $script:DiskReads = 0
        Mock Get-Disk {
            $script:DiskReads++
            if ($script:DiskReads -eq 2) { $script:disk.IsOffline = $false }
            $script:disk
        }
        (Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false).IsOffline | Should -BeFalse
        Should -Invoke Set-Disk -Times 0 -Exactly
    }

    It 'throws if online readback is still offline without retry' {
        $script:disk.IsOffline = $true
        Mock Set-Disk { }
        { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw '*still offline*'
        Should -Invoke Set-Disk -Times 1 -Exactly
    }

    It 'rejects changed or missing online readback (<Change>)' -ForEach @(
        @{ Change = 'number' }; @{ Change = 'missing' }; @{ Change = 'unsafe' }
    ) {
        $script:disk.IsOffline = $true
        $script:ReadbackChange = $Change
        $script:DiskReads = 0
        Mock Get-Disk {
            $script:DiskReads++
            if ($script:DiskReads -eq 3) {
                switch ($script:ReadbackChange) {
                    'number' { $script:disk.Number = 8 }
                    'missing' { return }
                    'unsafe' { $script:disk.IsBoot = $true }
                }
            }
            $script:disk
        }
        { Set-RecoveryUsbDiskOnline -ExpectedDiskUniqueId 'usb-stable-id' -Confirm:$false } | Should -Throw
        Should -Invoke Set-Disk -Times 1 -Exactly
    }

    It 'refuses a disk that goes offline during letter confirmation' {
        $script:DiskReads = 0
        Mock Get-Disk {
            $script:DiskReads++
            if ($script:DiskReads -eq 2) { $script:disk.IsOffline = $true }
            $script:disk
        }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*went offline*'
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'rejects missing, ambiguous, unsafe, or mismapped partitions (<Change>)' -ForEach @(
        @{ Change = 'missing' }; @{ Change = 'ambiguous' }
        @{ Change = 'unknown boot' }; @{ Change = 'unknown system' }
        @{ Change = 'string safety flag' }; @{ Change = 'boot' }; @{ Change = 'not basic' }
        @{ Change = 'wrong disk' }; @{ Change = 'wrong partition' }
    ) {
        switch ($Change) {
            'missing' { Mock Get-Partition { @() } }
            'ambiguous' { Mock Get-Partition { @($script:partition, $script:partition) } }
            'unknown boot' { $script:partition.IsBoot = $null }
            'unknown system' { $script:partition.IsSystem = $null }
            'string safety flag' { $script:partition.IsBoot = 'False' }
            'boot' { $script:partition.IsBoot = $true }
            'not basic' { $script:partition.Type = 'Reserved' }
            'wrong disk' { $script:partition.DiskNumber = 8 }
            'wrong partition' { $script:partition.PartitionNumber = 3 }
        }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*basic data partition*'
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'rechecks partition safety and existence after confirmation (<Change>)' -ForEach @(
        @{ Change = 'unsafe' }; @{ Change = 'unknown' }; @{ Change = 'missing' }; @{ Change = 'wrong disk' }
    ) {
        $script:PartitionChange = $Change
        $script:PartitionReads = 0
        Mock Get-Partition {
            $script:PartitionReads++
            if ($script:PartitionReads -eq 2) {
                switch ($script:PartitionChange) {
                    'unsafe' { $script:partition.IsSystem = $true }
                    'unknown' { $script:partition.IsBoot = $null }
                    'missing' { return }
                    'wrong disk' { $script:partition.DiskNumber = 8 }
                }
            }
            $script:partition
        } -ParameterFilter { $null -ne $DiskNumber }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*basic data partition*'
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'rejects a letter occupied on the second <Inventory> read' -ForEach @(
        @{ Inventory = 'volume' }; @{ Inventory = 'partition' }
    ) {
        $script:OccupancyReads = 0
        if ($Inventory -eq 'volume') {
            Mock Get-Volume {
                $script:OccupancyReads++
                if ($script:OccupancyReads -eq 2) { [pscustomobject]@{ DriveLetter = 'F'; Size = 0 } }
            }
        }
        else {
            Mock Get-Partition {
                $script:OccupancyReads++
                if ($script:OccupancyReads -eq 2) { [pscustomobject]@{ DriveLetter = 'F'; DiskNumber = 9 } }
            } -ParameterFilter { $null -eq $DiskNumber }
        }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*occupied*'
        $script:OccupancyReads | Should -Be 2
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'fails closed when occupancy inventory fails' {
        Mock Get-Volume { throw 'occupancy unavailable' }
        { Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -Confirm:$false } | Should -Throw '*occupancy unavailable*'
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'uses freshly read partition objects and normalizes an explicit letter' {
        Set-RecoveryUsbDriveLetter -ExpectedDiskUniqueId 'usb-stable-id' -PartitionNumber 2 -DriveLetter 'r' -Confirm:$false
        Should -Invoke Get-Partition -Times 2 -Exactly -ParameterFilter { $DiskNumber -eq 7 -and $PartitionNumber -eq 2 }
        Should -Invoke Set-Partition -Times 1 -Exactly -ParameterFilter { $NewDriveLetter -eq 'R' }
    }

    It 'loads <Name> from a different working directory and forwards WhatIf' -ForEach @(
        @{ Name = 'Set-UsbDiskOnline.ps1' }; @{ Name = 'Set-UsbDriveLetter.ps1' }
    ) {
        $arguments = @{ ExpectedDiskUniqueId = 'usb-stable-id'; WhatIf = $true }
        if ($Name -eq 'Set-UsbDiskOnline.ps1') { $script:disk.IsOffline = $true }
        else { $arguments.PartitionNumber = 2 }
        # Entry scripts have their own script scope. Capture state explicitly rather
        # than accidentally resolving $script:disk in the invoked script's scope.
        $entryDisk = $script:disk
        $entryPartition = $script:partition
        Mock Get-Disk ({ $entryDisk }.GetNewClosure())
        Mock Get-Partition ({ $entryPartition }.GetNewClosure())
        Push-Location $TestDrive
        try { @(& (Join-Path $script:ProjectRoot "scripts\storage\$Name") @arguments).Count | Should -Be 0 }
        finally { Pop-Location }
        Should -Invoke Get-Disk -Times 1 -Exactly
        Should -Invoke Set-Disk -Times 0 -Exactly
        Should -Invoke Set-Partition -Times 0 -Exactly
    }

    It 'forwards Confirm false to <Name> without a second prompt' -ForEach @(
        @{ Name = 'Set-UsbDiskOnline.ps1' }; @{ Name = 'Set-UsbDriveLetter.ps1' }
    ) {
        $ConfirmPreference = 'High'
        $arguments = @{ ExpectedDiskUniqueId = 'usb-stable-id'; Confirm = $false }
        if ($Name -eq 'Set-UsbDiskOnline.ps1') { $script:disk.IsOffline = $true }
        else { $arguments.PartitionNumber = 2; $arguments.DriveLetter = 'r' }
        $entryDisk = $script:disk
        $entryPartition = $script:partition
        Mock Get-Disk ({ $entryDisk }.GetNewClosure())
        Mock Get-Partition ({ $entryPartition }.GetNewClosure())
        Mock Set-Disk ({ $entryDisk.IsOffline = $false }.GetNewClosure())
        Push-Location $TestDrive
        try { & (Join-Path $script:ProjectRoot "scripts\storage\$Name") @arguments }
        finally { Pop-Location }
        if ($Name -eq 'Set-UsbDiskOnline.ps1') { Should -Invoke Set-Disk -Times 1 -Exactly }
        else { Should -Invoke Set-Partition -Times 1 -Exactly -ParameterFilter { $NewDriveLetter -eq 'R' } }
    }
}
