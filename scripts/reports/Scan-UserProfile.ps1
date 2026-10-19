# File sizes are metadata, not estimates of reclaimable space.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$ProfilePath,
    [ValidateRange(1, 1000)][int]$Top = 40
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'src\DirectoryScan.ps1')
if (-not $PSBoundParameters.ContainsKey('ProfilePath')) {
    $ProfilePath = Get-DirectoryReportDefaultPath -Kind Profile
}

Show-DirectorySizeReport -Label 'User profile' -Path $ProfilePath -Top $Top -IncludeRootFiles
foreach ($relativePath in 'AppData\Local', 'AppData\Roaming', 'AppData\LocalLow', 'Downloads', 'Documents', 'Desktop', 'Videos', 'Pictures') {
    Show-DirectorySizeReport -Label $relativePath -Path (Join-Path $ProfilePath $relativePath) -Top $Top -IncludeRootFiles
}
