<#
.SYNOPSIS
Brings one non-system USB disk online by exact stable UniqueId.
.PARAMETER ExpectedDiskUniqueId
UniqueId copied from read-only Get-Disk inventory; never a disk number or letter.
.DESCRIPTION
Supports WhatIf and high-impact confirmation. Revalidates safety and mapping
before changing the disk, then verifies online readback. No repair or retry.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedDiskUniqueId)

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'src\DiskRecovery.ps1')
Set-RecoveryUsbDiskOnline @PSBoundParameters
