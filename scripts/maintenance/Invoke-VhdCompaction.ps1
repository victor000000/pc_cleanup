[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VhdPath,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Stop the image's WSL/Docker owner manually. No processes are stopped here.
if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Compact the explicit VHD using a temporary read-only attachment; write result log')) { return }
$null = Get-MaintenanceVhdPreflight -Path $VhdPath
$log = $null
try {
    $log = Open-MaintenanceLog -LogPath (New-MaintenanceLogPath -Operation 'vhd-compaction' -LogPath $LogPath)
    Write-MaintenanceLog -Log $log -Start -Message "=== Compact started $(Get-Date) ==="
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
