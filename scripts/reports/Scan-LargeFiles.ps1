# One metadata-only traversal supplies both lists. Image extensions are a
# reporting category, not permission to modify, compact or delete anything.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$ProfilePath,
    [ValidateRange(0, [long]::MaxValue)][long]$MinimumFileBytes = 1GB,
    [ValidateRange(1, 1000)][int]$Top = 40
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'src\DirectoryScan.ps1')
if (-not $PSBoundParameters.ContainsKey('ProfilePath')) {
    $ProfilePath = Get-DirectoryReportDefaultPath -Kind Profile
}

$report = Get-DirectoryLargeFileReport -Path $ProfilePath -MinimumFileBytes $MinimumFileBytes -Top $Top
Show-DirectoryFileReport -Label "Disk images / ISO / VM files under $ProfilePath" -Rows $report.Images -Top $Top
Show-DirectoryFileReport -Label "Other files over $MinimumFileBytes bytes under $ProfilePath" -Rows $report.OtherFiles -Top $Top
