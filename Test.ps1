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
$originalPathExt = $env:PATHEXT
try {
    # WSL-launched processes can inherit PATHEXT without .EXE. PowerShell then
    # treats even cmd.exe fixtures as documents instead of native applications.
    # Adjust only this validation process; restore the caller's value in finally.
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and
        '.EXE' -notin ($env:PATHEXT -split ';')) {
        $env:PATHEXT = (@($env:PATHEXT -split ';' | Where-Object { $_ }) + '.EXE') -join ';'
    }
    $null = Invoke-ProjectValidation -ProjectRoot $PSScriptRoot -OutputPath $OutputPath -Coverage:$Coverage -SkipLint:$SkipLint
} catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    exit 1
} finally {
    $env:PATHEXT = $originalPathExt
}
