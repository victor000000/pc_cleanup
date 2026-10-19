[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Search,
    [string]$ExecutablePath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.local\vendor\sysinternals\handle64.exe'),
    [switch]$AcceptEula,
    [string]$LogPath
)

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\VhdMaintenance.ps1')

# Handle's EULA acceptance can persist user state. Never accept it implicitly.
if (-not $PSCmdlet.ShouldProcess($ExecutablePath, "Accept the Sysinternals EULA and search open handles for '$Search'")) { return }
if (-not $AcceptEula) { throw 'Explicit -AcceptEula is required to run Handle; review the Sysinternals license first.' }
if ($Search.StartsWith('-') -or $Search -match '[\x00-\x1f]') {
    throw 'Search must be literal nonempty text, not a Handle switch or control characters.'
}
# Fail before creating logs if the local executable is missing or untrusted.
$ExecutablePath = Resolve-MaintenanceHandleExecutable -Path $ExecutablePath
$LogPath = New-MaintenanceLogPath -Operation 'open-handles' -LogPath $LogPath
try {
    Write-MaintenanceLog -LogPath $LogPath -Start -Message "=== Handle search $(Get-Date): $Search ==="
    $result = Invoke-MaintenanceNativeCommand -FileName 'handle64.exe' -ExecutablePath $ExecutablePath `
        -ArgumentList @('-accepteula', '-a', '-nobanner', $Search) -Confirm:$false
    Write-MaintenanceLog -LogPath $LogPath -Message $result.Output
    Write-MaintenanceLog -LogPath $LogPath -Message "=== Done $(Get-Date) ==="
    return $result
}
catch {
    Write-MaintenanceFailure -LogPath $LogPath -Failure $_
    throw
}
