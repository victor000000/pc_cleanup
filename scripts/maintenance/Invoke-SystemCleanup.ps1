[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$VhdPath,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Review the whole plan before approving. Earlier successful operations are not
# undone when a later independent step fails. No reboot or WSL shutdown is done.
if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Disable hibernation, set only C: pagefile to 16/32 GB via WMI, compact the explicit VHD, and write result log')) { return }
# Reject an unsupported engine, unavailable WMI, bad path, missing Storage APIs,
# attached or busy image BEFORE powercfg, pagefile updates, or log creation.
Assert-MaintenanceWmiAvailable
$null = Get-MaintenanceVhdPreflight -Path $VhdPath
$log = $null
try {
    $log = Open-MaintenanceLog -LogPath (New-MaintenanceLogPath -Operation 'system-cleanup' -LogPath $LogPath)
    Write-MaintenanceLog -Log $log -Start -Message "=== System cleanup started $(Get-Date) ==="
    $power = Invoke-MaintenanceNativeCommand -FileName 'powercfg.exe' -ArgumentList @('/h', 'off') -Confirm:$false
    Write-MaintenanceLog -Log $log -Message "powercfg exit=$($power.ExitCode)`r`n$($power.Output)"

    $pagefile = Set-CPageFileSize -InitialSizeMB 16384 -MaximumSizeMB 32768 -Confirm:$false
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
