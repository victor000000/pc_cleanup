[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$lock = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'Dependencies.psd1')
if ($lock.SchemaVersion -ne 1) { throw 'Unsupported development dependency lock format.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem

foreach ($name in ($lock.Modules.Keys | Sort-Object)) {
    $dependency = $lock.Modules[$name]
    $version = [version]$dependency.Version
    $destination = Join-Path $root ".tools\modules\$name\$version"
    $manifest = Join-Path $destination "$name.psd1"
    $stamp = Join-Path $destination '.package-sha512'
    if ((Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $stamp) -and
        (Get-Content -LiteralPath $stamp -Raw).Trim() -ceq $dependency.SHA512) {
        Write-Output "$name $version already installed locally."
        continue
    }
    if (Test-Path -LiteralPath $destination) {
        throw "Incomplete or unrecognized dependency at '$destination'. Inspect it before removing and retrying."
    }
    if (-not $PSCmdlet.ShouldProcess($destination, "Download and SHA512-verify $name $version from PowerShell Gallery")) { continue }

    $downloadDirectory = Join-Path $root ('.tools\downloads\' + $name + '-' + $version + '-' + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $downloadDirectory -ErrorAction Stop
    $package = Join-Path $downloadDirectory 'package.nupkg'
    $staging = Join-Path $downloadDirectory 'extracted'
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $dependency.Uri -OutFile $package -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        $hex = (Get-FileHash -LiteralPath $package -Algorithm SHA512).Hash
        $expected = ([BitConverter]::ToString([Convert]::FromBase64String($dependency.SHA512))).Replace('-', '')
        if ($hex -cne $expected) { throw "SHA512 verification failed for $name $version. The package was not extracted or imported." }

        $boundary = [IO.Path]::GetFullPath($staging) + [IO.Path]::DirectorySeparatorChar
        $archive = [IO.Compression.ZipFile]::OpenRead($package)
        try {
            foreach ($entry in $archive.Entries) {
                $target = [IO.Path]::GetFullPath((Join-Path $staging $entry.FullName))
                if (-not $target.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Dependency archive contains a path outside its extraction directory.'
                }
            }
        } finally { $archive.Dispose() }
        [IO.Compression.ZipFile]::ExtractToDirectory($package, $staging)
        $stagedManifest = Join-Path $staging "$name.psd1"
        $metadata = Import-PowerShellDataFile -LiteralPath $stagedManifest -ErrorAction Stop
        if ([version]$metadata.ModuleVersion -ne $version) { throw "Module version mismatch for $name." }
        Set-Content -LiteralPath (Join-Path $staging '.package-sha512') -Value $dependency.SHA512 -Encoding ASCII
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
        Move-Item -LiteralPath $staging -Destination $destination -ErrorAction Stop
        Write-Output "Installed $name $version into project-local .tools/modules."
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}
