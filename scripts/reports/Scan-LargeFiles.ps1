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

$imageExtensions = @('.vhdx', '.vhd', '.vmdk', '.vmem', '.vmss', '.iso', '.ova', '.qcow2', '.img')
$profileFiles = @(Get-DirectoryScanFiles -Path $ProfilePath | ConvertTo-DirectoryReportFileRow |
    Where-Object { $imageExtensions -contains $_.Extension -or $_.Bytes -gt $MinimumFileBytes })
$images = @($profileFiles | Where-Object { $imageExtensions -contains $_.Extension })
$otherFiles = @($profileFiles | Where-Object { $imageExtensions -notcontains $_.Extension -and $_.Bytes -gt $MinimumFileBytes })
Show-DirectoryFileReport -Label "Disk images / ISO / VM files under $ProfilePath" -Rows $images -Top $Top
Show-DirectoryFileReport -Label "Other files over $MinimumFileBytes bytes under $ProfilePath" -Rows $otherFiles -Top $Top
