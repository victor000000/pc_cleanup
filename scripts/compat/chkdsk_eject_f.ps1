<#
.SYNOPSIS
Retired repair alias: forwards only orderly eject to scripts/storage/Eject-UsbDisk.ps1.
.DESCRIPTION
Warns that repairs require separate review and explicit consent. Never runs chkdsk.
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

Write-Warning 'Automatic chkdsk/repair and forced dismount are retired. Run repairs separately only after reviewing the target and obtaining explicit consent.'
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'storage\Eject-UsbDisk.ps1') @PSBoundParameters
