[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VhdPath,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Stop the WSL distribution yourself. No distro discovery or automatic shutdown.
if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Compact the explicit VHD, run DISM analysis and component cleanup, and write result log')) { return }
$null = Get-MaintenanceVhdPreflight -Path $VhdPath
$log = $null
try {
    $log = Open-MaintenanceLog -LogPath (New-MaintenanceLogPath -Operation 'ubuntu-maintenance' -LogPath $LogPath)
    Write-MaintenanceLog -Log $log -Start -Message "=== Started $(Get-Date) ==="
    $result = Invoke-VhdCompaction -VhdPath $VhdPath -Confirm:$false
    Write-MaintenanceLog -Log $log -Message $result.Output
    Write-MaintenanceLog -Log $log -Message ('VHD now: {0:N2} GB' -f ($result.Length / 1GB))

    Write-MaintenanceLog -Log $log -Message '--- DISM AnalyzeComponentStore ---'
    $analysis = Invoke-MaintenanceNativeCommand -FileName 'dism.exe' `
        -ArgumentList @('/online', '/cleanup-image', '/analyzecomponentstore') -Confirm:$false
    Write-MaintenanceLog -Log $log -Message $analysis.Output
    Write-MaintenanceLog -Log $log -Message '--- DISM StartComponentCleanup ---'
    $cleanup = Invoke-MaintenanceNativeCommand -FileName 'dism.exe' `
        -ArgumentList @('/online', '/cleanup-image', '/startcomponentcleanup') -Confirm:$false
    Write-MaintenanceLog -Log $log -Message $cleanup.Output
    Write-MaintenanceLog -Log $log -Message "=== Done $(Get-Date) ==="
}
catch {
    if ($null -ne $log) { Write-MaintenanceFailure -Log $log -Failure $_ }
    throw
}
finally {
    if ($null -ne $log) { Close-MaintenanceLog -Log $log }
}
