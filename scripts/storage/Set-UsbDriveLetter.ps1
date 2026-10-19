<#
.SYNOPSIS
Assigns an unused letter to a selected non-system USB data partition.
.PARAMETER ExpectedDiskUniqueId
Exact stable UniqueId copied from read-only Get-Disk inventory.
.PARAMETER PartitionNumber
Explicit Basic data partition on that disk, not a disk number.
.PARAMETER DriveLetter
Desired letter D through Z (default F). Occupied letters are never removed.
.DESCRIPTION
Supports WhatIf and high-impact confirmation. Rechecks safety and occupancy
before assignment. Bring an offline target online separately after review.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedDiskUniqueId,
    [Parameter(Mandatory)][ValidateRange(1, 128)][int]$PartitionNumber,
    [ValidatePattern('^[D-Zd-z]$')][string]$DriveLetter = 'F'
)

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $projectRoot 'src\DiskRecovery.ps1')
Set-RecoveryUsbDriveLetter @PSBoundParameters
