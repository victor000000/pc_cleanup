# Read-only filesystem overview. Logical lengths are not reclaimable disk space.
# All paths stay beneath the explicitly selected root/profile; no OS commands run.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$RootPath,
    [ValidateNotNullOrEmpty()][string]$ProfilePath,
    [ValidateRange(1, 1000)][int]$Top = 25
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'src\DirectoryScan.ps1')
if (-not $PSBoundParameters.ContainsKey('RootPath')) {
    $RootPath = Get-DirectoryReportDefaultPath -Kind Root
}
if (-not $PSBoundParameters.ContainsKey('ProfilePath')) {
    $ProfilePath = Get-DirectoryReportDefaultPath -Kind Profile
}

Show-DirectorySizeReport -Label 'Top-level folders' -Path $RootPath -Top $Top -IncludeRootFiles -MinimumFileBytes 100MB
Show-DirectorySizeReport -Label 'User profile' -Path $ProfilePath -Top $Top -IncludeRootFiles
foreach ($relativePath in 'AppData\Local', 'AppData\Roaming', 'Documents', 'Downloads') {
    Show-DirectorySizeReport -Label $relativePath -Path (Join-Path $ProfilePath $relativePath) -Top $Top
}

"`n=== Selected system/profile locations (metadata only; not cleanup recommendations) ==="
$locations = @(
    (Join-Path $RootPath 'Windows\Temp')
    (Join-Path $RootPath 'Windows\SoftwareDistribution\Download')
    (Join-Path $RootPath '$Recycle.Bin')
    (Join-Path $ProfilePath 'AppData\Local\Temp')
)
$rows = foreach ($path in $locations) {
    $bytes = Get-DirSize -Path $path
    [pscustomobject]@{ Path = $path; Bytes = $bytes; GB = [math]::Round($bytes / 1GB, 2) }
}
$rows | Sort-Object Bytes -Descending | Format-Table GB, Path -AutoSize | Out-String -Width 240

$largeFiles = @(Get-DirectoryScanFiles -Path $ProfilePath | ConvertTo-DirectoryReportFileRow | Where-Object { $_.Bytes -gt 1GB })
Show-DirectoryFileReport -Label "Files over 1 GB under $ProfilePath" -Rows $largeFiles -Top $Top
