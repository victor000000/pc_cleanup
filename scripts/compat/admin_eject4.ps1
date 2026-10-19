<#
.SYNOPSIS
Compatibility alias for scripts/storage/Eject-UsbDisk.ps1; no target is assumed.
.PARAMETER UniqueId
Exact stable disk UniqueId from Get-Disk; use this or SerialNumber, not both.
.PARAMETER SerialNumber
Exact serial number identifying one USB disk. Preview with WhatIf first.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string] $UniqueId,
    [string] $SerialNumber
)

& (Join-Path (Split-Path $PSScriptRoot -Parent) 'storage\Eject-UsbDisk.ps1') @PSBoundParameters
