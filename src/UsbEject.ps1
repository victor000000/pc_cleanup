# Windows PowerShell 5.1. Dot-sourcing defines functions only; it does not eject anything.
# Internal helpers are separate so tests can replace every inventory/native boundary.

function Get-UsbEjectInventory {
    [CmdletBinding()]
    param()

    Get-Disk -ErrorAction Stop
}

function Get-UsbEjectValidatedDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('UniqueId', 'SerialNumber')]
        [string] $IdentityProperty,
        [Parameter(Mandatory = $true)]
        [string] $Identity
    )

    # Exact identity comparison, never wildcard matching or selection by drive letter/number.
    $matches = @(Get-UsbEjectInventory | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string] $_.$IdentityProperty) -and
        [string]::Equals(([string] $_.$IdentityProperty).Trim(), $Identity,
            [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one disk matching $IdentityProperty '$Identity'; found $($matches.Count)."
    }

    $disk = $matches[0]
    if ([string] $disk.BusType -ne 'USB') {
        throw 'Refusing eject: the selected disk is not USB.'
    }
    # Unknown/missing safety flags must fail closed, not become false by coercion.
    if ($disk.IsBoot -isnot [bool] -or $disk.IsSystem -isnot [bool] -or
        $disk.IsBoot -or $disk.IsSystem) {
        throw 'Refusing eject: the disk is boot/system, or its safety flags are unknown.'
    }
    [uint32] $number = 0
    if (-not [uint32]::TryParse([string] $disk.Number, [ref] $number)) {
        throw 'Refusing eject: invalid disk inventory number.'
    }
    $disk
}

function Assert-UsbEjectDiskInstanceId {
    [CmdletBinding()]
    param([string] $InstanceId)

    # Only a disk node obtained from Win32_DiskDrive is supported. In particular,
    # USB VID enclosures, ROOT_HUB, PCI and ACPI nodes cannot enter this path.
    # Choosing the disk itself avoids any parent traversal or multi-device enclosure eject.
    if ([string]::IsNullOrWhiteSpace($InstanceId) -or $InstanceId.Length -ge 200 -or
        $InstanceId -notmatch '\A(?:USBSTOR|SCSI)\\DISK&[^\\\s\x00-\x1f\x7f]+\\[^\\\s\x00-\x1f\x7f]+\z') {
        throw "Refusing eject: unsupported or invalid disk device instance ID '$InstanceId'."
    }
}

function Get-UsbEjectDiskInstanceId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] $Disk)

    # The current number is only a read-only join key AFTER stable-identity validation.
    [uint32] $number = 0
    if (-not [uint32]::TryParse([string] $Disk.Number, [ref] $number)) {
        throw 'Refusing eject: invalid disk inventory number.'
    }
    $devices = @(Get-CimInstance -ClassName Win32_DiskDrive -Filter "Index = $number" -ErrorAction Stop)
    if ($devices.Count -ne 1 -or [string] $devices[0].Index -ne [string] $number) {
        throw 'Refusing eject: cannot uniquely map the selected disk to a PnP disk node.'
    }
    $instanceId = [string] $devices[0].PNPDeviceID
    Assert-UsbEjectDiskInstanceId -InstanceId $instanceId
    $instanceId
}

function Invoke-UsbEjectCm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Locate', 'GetDeviceId', 'RequestEject')]
        [string] $Operation,
        [string] $InstanceId,
        [uint32] $DevInst
    )

    # No native code is loaded until the public function's ShouldProcess is accepted.
    if (-not ('PcCleanup.UsbEject.NativeMethodsV1' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
namespace PcCleanup.UsbEject {
    public static class NativeMethodsV1 {
        // DEVINST and CONFIGRET are 32-bit ULONGs, including in a 64-bit process.
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        public static extern uint CM_Locate_DevNodeW(out uint devInst, string deviceId, uint flags);
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        public static extern uint CM_Get_Device_IDW(uint devInst, StringBuilder buffer, uint length, uint flags);
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        public static extern uint CM_Request_Device_EjectW(uint devInst, out uint vetoType,
            StringBuilder vetoName, uint length, uint flags);
    }
}
'@
    }

    switch ($Operation) {
        'Locate' {
            [uint32] $located = 0
            $code = [PcCleanup.UsbEject.NativeMethodsV1]::CM_Locate_DevNodeW([ref] $located, $InstanceId, 0)
            [pscustomobject]@{ ReturnCode = $code; DevInst = $located }
        }
        'GetDeviceId' {
            $buffer = New-Object System.Text.StringBuilder 200
            $code = [PcCleanup.UsbEject.NativeMethodsV1]::CM_Get_Device_IDW($DevInst, $buffer, 200, 0)
            [pscustomobject]@{ ReturnCode = $code; InstanceId = $buffer.ToString() }
        }
        'RequestEject' {
            [uint32] $veto = 0
            $buffer = New-Object System.Text.StringBuilder 260
            $code = [PcCleanup.UsbEject.NativeMethodsV1]::CM_Request_Device_EjectW($DevInst, [ref] $veto, $buffer, 260, 0)
            [pscustomobject]@{ ReturnCode = $code; VetoType = $veto; VetoName = $buffer.ToString() }
        }
    }
}

function Invoke-UsbEjectNativeRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string] $InstanceId)

    Assert-UsbEjectDiskInstanceId -InstanceId $InstanceId
    $located = Invoke-UsbEjectCm -Operation Locate -InstanceId $InstanceId
    [uint32] $devInst = 0
    if ($null -eq $located -or $null -eq $located.ReturnCode -or $located.ReturnCode -ne 0 -or
        -not [uint32]::TryParse([string] $located.DevInst, [ref] $devInst) -or $devInst -eq 0) {
        throw "CM_Locate_DevNodeW failed for '$InstanceId' (CONFIGRET $($located.ReturnCode))."
    }

    $actual = Invoke-UsbEjectCm -Operation GetDeviceId -DevInst $devInst
    if ($null -eq $actual -or $null -eq $actual.ReturnCode -or $actual.ReturnCode -ne 0) {
        throw "CM_Get_Device_IDW failed (CONFIGRET $($actual.ReturnCode))."
    }
    Assert-UsbEjectDiskInstanceId -InstanceId $actual.InstanceId
    if (-not [string]::Equals($InstanceId, $actual.InstanceId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing eject: located device ID differs from the validated disk ID.'
    }

    # One request, on this disk only. A veto/error is final: no retry, parent or force fallback.
    $result = Invoke-UsbEjectCm -Operation RequestEject -DevInst $devInst
    if ($null -eq $result -or $null -eq $result.ReturnCode -or $result.ReturnCode -ne 0 -or
        $null -eq $result.VetoType -or $result.VetoType -ne 0) {
        throw "Eject failed or vetoed (CONFIGRET $($result.ReturnCode), veto $($result.VetoType), name '$($result.VetoName)'). Close users of the disk yourself and review before retrying."
    }
}

function Invoke-SafeUsbEject {
    <#
    .SYNOPSIS
    Requests orderly USB disk eject using an explicit stable identity.
    .DESCRIPTION
    Supply exactly one UniqueId or SerialNumber from read-only Get-Disk inventory.
    Rejects non-USB, boot/system, ambiguous and unknown targets. Only the disk's
    validated PnP node is requested; parents/enclosures are never traversed.
    A veto throws without dismount, repair, offline, service or process changes.
    Success means Windows accepted the request, not independent proof of removal.
    .PARAMETER UniqueId
    Exact stable UniqueId from Get-Disk. Supply this or SerialNumber, never both.
    .PARAMETER SerialNumber
    Exact serial number from Get-Disk. Must match exactly one safe USB disk.
    .EXAMPLE
    Invoke-SafeUsbEject -UniqueId 'identity copied from Get-Disk' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string] $UniqueId,
        [string] $SerialNumber
    )

    if ($PSBoundParameters.ContainsKey('UniqueId') -eq $PSBoundParameters.ContainsKey('SerialNumber')) {
        throw 'Supply exactly one explicit stable disk identity: -UniqueId or -SerialNumber.'
    }
    $property = if ($PSBoundParameters.ContainsKey('UniqueId')) { 'UniqueId' } else { 'SerialNumber' }
    $identity = ([string] $PSBoundParameters[$property]).Trim()
    if ([string]::IsNullOrWhiteSpace($identity)) {
        throw 'A nonempty stable disk identity is required; drive letters and disk numbers are not identities.'
    }

    $disk = Get-UsbEjectValidatedDisk -IdentityProperty $property -Identity $identity
    # Snapshot scalar mapping data: inventory adapters may reuse mutable objects.
    $originalNumber = [uint32] $disk.Number
    $instanceId = Get-UsbEjectDiskInstanceId -Disk $disk
    # Validate here as well so even a replaced inventory adapter cannot pass a parent node.
    Assert-UsbEjectDiskInstanceId -InstanceId $instanceId
    if ($PSCmdlet.ShouldProcess("USB disk $property '$identity' ($instanceId)", 'Request orderly disk eject')) {
        # Confirmation can be left open while devices change. Re-resolve and fail closed.
        $current = Get-UsbEjectValidatedDisk -IdentityProperty $property -Identity $identity
        $currentId = Get-UsbEjectDiskInstanceId -Disk $current
        Assert-UsbEjectDiskInstanceId -InstanceId $currentId
        if ([uint32] $current.Number -ne $originalNumber -or
            -not [string]::Equals($currentId, $instanceId, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing eject: disk mapping changed during confirmation; review inventory and retry.'
        }
        Invoke-UsbEjectNativeRequest -InstanceId $currentId
        [pscustomobject]@{
            Status = 'EjectRequested'
            IdentityProperty = $property
            Identity = $identity
            DeviceInstanceId = $currentId
        }
    }
}
