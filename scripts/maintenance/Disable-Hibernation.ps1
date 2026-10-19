[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string]$LogPath)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

if (-not $PSCmdlet.ShouldProcess('Windows hibernation', 'Disable hibernation with powercfg /h off')) { return }
# Standalone hibernation disabling does not require WMI or touch pagefiles.
# Logging is optional; an explicit log path may be supplied by the caller.
if ($LogPath) { $LogPath = New-MaintenanceLogPath -Operation 'disable-hibernation' -LogPath $LogPath }
try {
    if ($LogPath) { Write-MaintenanceLog -LogPath $LogPath -Start -Message "=== Started $(Get-Date) ===" }
    $result = Invoke-MaintenanceNativeCommand -FileName 'powercfg.exe' -ArgumentList @('/h', 'off') -Confirm:$false
    if ($LogPath) {
        Write-MaintenanceLog -LogPath $LogPath -Message "powercfg exit=$($result.ExitCode)`r`n$($result.Output)"
        Write-MaintenanceLog -LogPath $LogPath -Message "=== Done $(Get-Date) ==="
    }
    return $result
}
catch {
    if ($LogPath) { Write-MaintenanceFailure -LogPath $LogPath -Failure $_ }
    throw
}
