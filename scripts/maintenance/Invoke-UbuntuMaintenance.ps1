[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VhdPath,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Stop the WSL distribution yourself. No distro discovery or automatic shutdown.
if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Compact the explicit VHD, run DISM analysis and component cleanup, and write result log')) { return }
$null = Get-MaintenanceVhdPreflight -Path $VhdPath
$LogPath = New-MaintenanceLogPath -Operation 'ubuntu-maintenance' -LogPath $LogPath
try {
    Write-MaintenanceLog -LogPath $LogPath -Start -Message "=== Started $(Get-Date) ==="
    $result = Invoke-VhdCompaction -VhdPath $VhdPath -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $result.Output
    Write-MaintenanceLog -LogPath $LogPath -Message ('VHD now: {0:N2} GB' -f ($result.Length / 1GB))

    Write-MaintenanceLog -LogPath $LogPath -Message '--- DISM AnalyzeComponentStore ---'
    $analysis = Invoke-MaintenanceNativeCommand -FileName 'dism.exe' `
        -ArgumentList @('/online', '/cleanup-image', '/analyzecomponentstore') -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $analysis.Output
    Write-MaintenanceLog -LogPath $LogPath -Message '--- DISM StartComponentCleanup ---'
    $cleanup = Invoke-MaintenanceNativeCommand -FileName 'dism.exe' `
        -ArgumentList @('/online', '/cleanup-image', '/startcomponentcleanup') -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $cleanup.Output
    Write-MaintenanceLog -LogPath $LogPath -Message "=== Done $(Get-Date) ==="
}
catch {
    Write-MaintenanceFailure -LogPath $LogPath -Failure $_
    throw
}
