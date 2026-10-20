[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Search,
    [string]$ExecutablePath,
    [switch]$AcceptEula,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    $ExecutablePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.local\vendor\sysinternals\handle64.exe'
}
if ([string]::IsNullOrWhiteSpace($Search) -or $Search.TrimStart().StartsWith('-') -or
    $Search.TrimStart().StartsWith('/') -or $Search -match '[\p{Cc}"]') {
    throw 'Search must be literal nonempty text, not a Handle switch, quotes, or control characters.'
}
# Handle's EULA acceptance can persist user state. Never accept it implicitly.
if (-not $PSCmdlet.ShouldProcess($ExecutablePath, "Accept the Sysinternals EULA and search open handles for '$Search'")) { return }
if (-not $AcceptEula) { throw 'Explicit -AcceptEula is required to run Handle; review the Sysinternals license first.' }
# Fail before creating logs if the local executable is missing or untrusted.
$ExecutablePath = Resolve-MaintenanceHandleExecutable -Path $ExecutablePath
$log = $null
try {
    $log = Open-MaintenanceLog -LogPath (New-MaintenanceLogPath -Operation 'open-handles' -LogPath $LogPath)
    Write-MaintenanceLog -Log $log -Start -Message "=== Handle search $(Get-Date): $Search ==="
    $result = Invoke-MaintenanceNativeCommand -FileName 'handle64.exe' -ExecutablePath $ExecutablePath `
        -ArgumentList @('-accepteula', '-a', '-nobanner', $Search) -Confirm:$false
    Write-MaintenanceLog -Log $log -Message $result.Output
    Write-MaintenanceLog -Log $log -Message "=== Done $(Get-Date) ==="
}
catch {
    if ($null -ne $log) { Write-MaintenanceFailure -Log $log -Failure $_ }
    throw
}
finally {
    if ($null -ne $log) { Close-MaintenanceLog -Log $log }
}
return $result
