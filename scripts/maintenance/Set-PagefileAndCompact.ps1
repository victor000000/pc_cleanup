[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VhdPath,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Registry alternative: preserve every non-C: PagingFiles entry. Reboot required;
# automatic-management policy can override explicit registry sizes.
if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Set only the C: pagefile registry entry to 16/32 GB, compact the explicit VHD, and write result log')) { return }
$null = Get-MaintenanceVhdPreflight -Path $VhdPath
$LogPath = New-MaintenanceLogPath -Operation 'pagefile-and-compact' -LogPath $LogPath
try {
    Write-MaintenanceLog -LogPath $LogPath -Start -Message "=== Pagefile and compaction started $(Get-Date) ==="
    $pagefile = Set-CPageFileRegistrySize -InitialSizeMB 16384 -MaximumSizeMB 32768 -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $pagefile

    $result = Invoke-VhdCompaction -VhdPath $VhdPath -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $result.Output
    Write-MaintenanceLog -LogPath $LogPath -Message ('VHD now: {0:N2} GB' -f ($result.Length / 1GB))
    Write-MaintenanceLog -LogPath $LogPath -Message "=== Done $(Get-Date) ==="
}
catch {
    Write-MaintenanceFailure -LogPath $LogPath -Failure $_
    throw
}
