# Reports filesystem metadata only; skipped paths produce incomplete-scan warnings.
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$RootPath,
    [ValidateRange(1, 1000)][int]$Top = 25,
    [ValidateRange(0, [long]::MaxValue)][long]$MinimumFileBytes = 100MB
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'src\DirectoryScan.ps1')
if (-not $PSBoundParameters.ContainsKey('RootPath')) {
    $RootPath = Get-DirectoryReportDefaultPath -Kind Root
}

Show-DirectorySizeReport -Label 'Top-level folders' -Path $RootPath -Top $Top -IncludeRootFiles -MinimumFileBytes $MinimumFileBytes
