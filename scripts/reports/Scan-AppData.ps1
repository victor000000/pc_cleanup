# Discover application directories from AppData; no application/terminal IDs or
# cleanability assumptions are built in. AppPath adds explicit literal locations.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$ProfilePath,
    [ValidateNotNullOrEmpty()][string[]]$AppPath = @(),
    [ValidateRange(1, 1000)][int]$Top = 25
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'src\DirectoryScan.ps1')
if (-not $PSBoundParameters.ContainsKey('ProfilePath')) {
    $ProfilePath = Get-DirectoryReportDefaultPath -Kind Profile
}

foreach ($relativePath in 'AppData\Local', 'AppData\Roaming', 'AppData\LocalLow') {
    Show-DirectorySizeReport -Label $relativePath -Path (Join-Path $ProfilePath $relativePath) -Top $Top -IncludeRootFiles
}
foreach ($path in $AppPath) {
    Show-DirectorySizeReport -Label 'Explicit application directory (metadata only)' -Path $path -Top $Top -IncludeRootFiles
}
