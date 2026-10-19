[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VhdPath,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Stop the image's WSL/Docker owner manually. No processes are stopped here.
if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Compact the explicit VHD using a temporary read-only attachment; write result log')) { return }
$null = Get-MaintenanceVhdPreflight -Path $VhdPath
$LogPath = New-MaintenanceLogPath -Operation 'vhd-compaction' -LogPath $LogPath
try {
    Write-MaintenanceLog -LogPath $LogPath -Start -Message "=== Compact started $(Get-Date) ==="
    $result = Invoke-VhdCompaction -VhdPath $VhdPath -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $result.Output
    Write-MaintenanceLog -LogPath $LogPath -Message ('VHD now: {0:N2} GB' -f ($result.Length / 1GB))
    Write-MaintenanceLog -LogPath $LogPath -Message "=== Done $(Get-Date) ==="
}
catch {
    Write-MaintenanceFailure -LogPath $LogPath -Failure $_
    throw
}
