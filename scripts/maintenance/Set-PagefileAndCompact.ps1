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
$log = $null
try {
    $log = Open-MaintenanceLog -LogPath (New-MaintenanceLogPath -Operation 'pagefile-and-compact' -LogPath $LogPath)
    Write-MaintenanceLog -Log $log -Start -Message "=== Pagefile and compaction started $(Get-Date) ==="
    $pagefile = Set-CPageFileRegistrySize -InitialSizeMB 16384 -MaximumSizeMB 32768 -Confirm:$false
    Write-MaintenanceLog -Log $log -Message $pagefile

    $result = Invoke-VhdCompaction -VhdPath $VhdPath -Confirm:$false
    Write-MaintenanceLog -Log $log -Message $result.Output
    Write-MaintenanceLog -Log $log -Message ('VHD now: {0:N2} GB' -f ($result.Length / 1GB))
    Write-MaintenanceLog -Log $log -Message "=== Done $(Get-Date) ==="
}
catch {
    if ($null -ne $log) { Write-MaintenanceFailure -Log $log -Failure $_ }
    throw
}
finally {
    if ($null -ne $log) { Close-MaintenanceLog -Log $log }
}
