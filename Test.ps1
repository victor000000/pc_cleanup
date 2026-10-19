[CmdletBinding()]
param(
    [switch]$Coverage,
    [switch]$SkipLint,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot ('artifacts\ps-' + $PSVersionTable.PSVersion.Major)
}
. (Join-Path $PSScriptRoot 'tools\ProjectTools.ps1')
try {
    $null = Invoke-ProjectValidation -ProjectRoot $PSScriptRoot -OutputPath $OutputPath -Coverage:$Coverage -SkipLint:$SkipLint
} catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    exit 1
}
