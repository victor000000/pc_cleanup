<#
.SYNOPSIS
Requests orderly eject of exactly one USB disk selected by stable identity.
.DESCRIPTION
Supply exactly one UniqueId or SerialNumber copied from read-only Get-Disk
inventory. No drive letter, disk number, enclosure, or hub is an eject target.
A veto is final: no forced dismount, offline, repair, process, or service fallback.
.PARAMETER UniqueId
Exact disk UniqueId. Cannot be combined with SerialNumber.
.PARAMETER SerialNumber
Exact disk serial number. Must identify only one safe USB disk.
.EXAMPLE
.\Eject-UsbDisk.ps1 -UniqueId 'identity copied from Get-Disk' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $UniqueId,
    [string] $SerialNumber
)

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'src\UsbEject.ps1')
Invoke-SafeUsbEject @PSBoundParameters
