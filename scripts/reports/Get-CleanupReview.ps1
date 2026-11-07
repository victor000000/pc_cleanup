# Returns review data only. Never writes a report or modifies candidate files.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RootPath,
    [ValidateRange(0, [long]::MaxValue)][long]$MinimumFileBytes = 100MB,
    [ValidateRange(1, 1000)][int]$Top = 40,
    [ValidateRange(0, 1000)][int]$WarningLimit = 20,
    [ValidateSet('Object', 'Json')][string]$Format = 'Object'
)
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'src\DirectoryScan.ps1')
. (Join-Path $projectRoot 'src\DirectoryReview.ps1')
$report = Get-DirectoryReviewReport -RootPath $RootPath -MinimumFileBytes $MinimumFileBytes -Top $Top -WarningLimit $WarningLimit
if ($Format -eq 'Json') { $report | ConvertTo-Json -Depth 6 }
else { $report }
