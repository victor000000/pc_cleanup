[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string]$LogPath)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

if (-not $PSCmdlet.ShouldProcess('Windows hibernation', 'Disable hibernation with powercfg /h off')) { return }
# Standalone hibernation disabling does not require WMI or touch pagefiles.
# Logging is optional; an explicit log path may be supplied by the caller.
$log = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $log = Open-MaintenanceLog -LogPath (New-MaintenanceLogPath -Operation 'disable-hibernation' -LogPath $LogPath)
        Write-MaintenanceLog -Log $log -Start -Message "=== Started $(Get-Date) ==="
    }
    $result = Invoke-MaintenanceNativeCommand -FileName 'powercfg.exe' -ArgumentList @('/h', 'off') -Confirm:$false
    if ($null -ne $log) {
        Write-MaintenanceLog -Log $log -Message "powercfg exit=$($result.ExitCode)`r`n$($result.Output)"
        Write-MaintenanceLog -Log $log -Message "=== Done $(Get-Date) ==="
    }
}
catch {
    if ($null -ne $log) { Write-MaintenanceFailure -Log $log -Failure $_ }
    throw
}
finally {
    if ($null -ne $log) { Close-MaintenanceLog -Log $log }
}
return $result
