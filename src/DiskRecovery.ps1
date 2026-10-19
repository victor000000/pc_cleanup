# Dot-sourcing defines functions only; all mutations require explicit stable identity.
function Get-RecoveryUsbDisk {
    <#
    .SYNOPSIS
    Resolves exactly one non-system USB disk by its stable UniqueId.
    .PARAMETER ExpectedDiskUniqueId
    Exact UniqueId copied from read-only Get-Disk inventory; not a number or letter.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedDiskUniqueId)

    if ([string]::IsNullOrWhiteSpace($ExpectedDiskUniqueId)) {
        throw 'A stable disk UniqueId is required. Inspect Get-Disk before choosing a target.'
    }
    $matches = @(Get-Disk -ErrorAction Stop | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.UniqueId) -and
        [string]::Equals(([string]$_.UniqueId).Trim(), $ExpectedDiskUniqueId.Trim(),
            [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one disk with UniqueId '$ExpectedDiskUniqueId'; found $($matches.Count)."
    }
    $disk = $matches[0]
    [uint64]$size = 0
    [uint32]$number = 0
    if ($disk.BusType -ne 'USB' -or $disk.IsBoot -isnot [bool] -or
        $disk.IsSystem -isnot [bool] -or $disk.IsOffline -isnot [bool] -or
        $disk.IsBoot -or $disk.IsSystem -or
        -not [uint64]::TryParse([string]$disk.Size, [ref]$size) -or $size -eq 0 -or
        -not [uint32]::TryParse([string]$disk.Number, [ref]$number)) {
        throw 'Recovery is restricted to a non-system USB disk containing media with known safety flags and a valid inventory number.'
    }
    return $disk
}

function Set-RecoveryUsbDiskOnline {
    <#
    .SYNOPSIS
    Brings one explicitly identified USB disk online, after fresh safety checks.
    .PARAMETER ExpectedDiskUniqueId
    Exact stable UniqueId from Get-Disk. Disk numbers are never target identities.
    .DESCRIPTION
    Supports WhatIf and high-impact confirmation. Disappearance, unsafe inventory,
    or a changed disk number during confirmation cancels the operation. Readback
    must confirm the disk is online. No retry, repair, or forced operation occurs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedDiskUniqueId)

    $disk = Get-RecoveryUsbDisk -ExpectedDiskUniqueId $ExpectedDiskUniqueId
    if (-not $disk.IsOffline) { return $disk }
    $originalNumber = [uint32]$disk.Number
    if ($PSCmdlet.ShouldProcess("$($disk.FriendlyName) [$($disk.UniqueId)]", 'Bring USB disk online')) {
        $disk = Get-RecoveryUsbDisk -ExpectedDiskUniqueId $ExpectedDiskUniqueId
        if ([uint32]$disk.Number -ne $originalNumber) {
            throw 'The selected disk number changed during confirmation; operation cancelled.'
        }
        # Another actor may already have brought it online while confirmation was open.
        if (-not $disk.IsOffline) { return $disk }
        Set-Disk -InputObject $disk -IsOffline $false -ErrorAction Stop
        $disk = Get-RecoveryUsbDisk -ExpectedDiskUniqueId $ExpectedDiskUniqueId
        if ([uint32]$disk.Number -ne $originalNumber) { throw 'The selected disk number changed during online readback.' }
        if ($disk.IsOffline) { throw 'The selected disk is still offline.' }
        return $disk
    }
}

function Get-RecoveryUsbDataPartition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint32]$DiskNumber,
        [Parameter(Mandatory)][int]$PartitionNumber
    )

    $partitions = @(Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -ErrorAction Stop)
    if ($partitions.Count -ne 1) {
        throw 'Expected exactly one basic data partition on the selected USB disk.'
    }
    $partition = $partitions[0]
    [uint32]$actualDisk = 0
    [uint32]$actualPartition = 0
    if ($partition.IsBoot -isnot [bool] -or $partition.IsSystem -isnot [bool] -or
        $partition.IsBoot -or $partition.IsSystem -or $partition.Type -ne 'Basic' -or
        -not [uint32]::TryParse([string]$partition.DiskNumber, [ref]$actualDisk) -or
        -not [uint32]::TryParse([string]$partition.PartitionNumber, [ref]$actualPartition) -or
        $actualDisk -ne $DiskNumber -or $actualPartition -ne $PartitionNumber) {
        throw 'Only the selected basic data partition with known safety flags can be assigned a drive letter.'
    }
    return $partition
}

function Assert-RecoveryUsbDriveLetterAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DriveLetter)

    # An unpartitioned or zero-size volume can still reserve a drive letter.
    $owners = @(Get-Volume -ErrorAction Stop | Where-Object { [string]$_.DriveLetter -eq $DriveLetter })
    $mounts = @(Get-Partition -ErrorAction Stop | Where-Object { [string]$_.DriveLetter -eq $DriveLetter })
    if ($owners.Count -gt 0 -or $mounts.Count -gt 0) {
        throw "Drive $DriveLetter`: is occupied. No existing mount point was removed."
    }
}

function Set-RecoveryUsbDriveLetter {
    <#
    .SYNOPSIS
    Assigns an available drive letter to one explicitly selected USB data partition.
    .PARAMETER ExpectedDiskUniqueId
    Exact stable UniqueId from read-only Get-Disk inventory.
    .PARAMETER PartitionNumber
    Explicit partition on that disk. Only a non-boot, non-system Basic partition is allowed.
    .PARAMETER DriveLetter
    Desired letter D through Z (default F). Existing mount points are never removed.
    .DESCRIPTION
    Supports WhatIf and high-impact confirmation. Rechecks disk safety, disk number,
    partition safety, and letter occupancy after confirmation, before assignment.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedDiskUniqueId,
        [Parameter(Mandatory)][ValidateRange(1, 128)][int]$PartitionNumber,
        [ValidatePattern('^[D-Zd-z]$')][string]$DriveLetter = 'F'
    )

    $DriveLetter = $DriveLetter.ToUpperInvariant()
    $disk = Get-RecoveryUsbDisk -ExpectedDiskUniqueId $ExpectedDiskUniqueId
    if ($disk.IsOffline) { throw 'Bring the intended USB disk online before assigning a drive letter.' }
    $originalNumber = [uint32]$disk.Number
    $partition = Get-RecoveryUsbDataPartition -DiskNumber $originalNumber -PartitionNumber $PartitionNumber
    if ([string]$partition.DriveLetter -eq $DriveLetter) { return $partition }
    Assert-RecoveryUsbDriveLetterAvailable -DriveLetter $DriveLetter

    if ($PSCmdlet.ShouldProcess("$($disk.FriendlyName), partition $PartitionNumber", "Assign drive $DriveLetter`:")) {
        $disk = Get-RecoveryUsbDisk -ExpectedDiskUniqueId $ExpectedDiskUniqueId
        if ($disk.IsOffline) { throw 'The selected USB disk went offline during confirmation.' }
        if ([uint32]$disk.Number -ne $originalNumber) {
            throw 'The selected disk number changed during confirmation; operation cancelled.'
        }
        $partition = Get-RecoveryUsbDataPartition -DiskNumber $originalNumber -PartitionNumber $PartitionNumber
        if ([string]$partition.DriveLetter -eq $DriveLetter) { return $partition }
        Assert-RecoveryUsbDriveLetterAvailable -DriveLetter $DriveLetter
        Set-Partition -InputObject $partition -NewDriveLetter $DriveLetter -ErrorAction Stop
    }
}
