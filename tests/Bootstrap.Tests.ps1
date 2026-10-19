BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function New-BootstrapFixture {
        param([string]$Directory, [switch]$Traversal, [string]$ManifestVersion = '5.5.0')
        $tools = Join-Path $Directory 'tools'
        $null = New-Item -ItemType Directory -Path $tools -Force
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\Install-DevDependencies.ps1') -Destination (Join-Path $tools 'Install-DevDependencies.ps1')
        $content = Join-Path $Directory 'payload'
        $null = New-Item -ItemType Directory -Path $content
        Set-Content -LiteralPath (Join-Path $content 'Pester.psd1') -Value "@{ ModuleVersion = '$ManifestVersion'; RootModule = 'Pester.psm1' }"
        Set-Content -LiteralPath (Join-Path $content 'Pester.psm1') -Value "throw 'Installing dependencies must not import their code.'"
        $package = Join-Path $Directory 'fixture.nupkg'
        [IO.Compression.ZipFile]::CreateFromDirectory($content, $package)
        if ($Traversal) {
            $zip = [IO.Compression.ZipFile]::Open($package, [IO.Compression.ZipArchiveMode]::Update)
            try {
                $entry = $zip.CreateEntry('../escape.ps1')
                $writer = [IO.StreamWriter]::new($entry.Open())
                try { $writer.Write('unsafe payload') } finally { $writer.Dispose() }
            } finally { $zip.Dispose() }
        }
        $bytes = [IO.File]::ReadAllBytes($package)
        $sha = [Security.Cryptography.SHA512]::Create()
        try { $hash = [Convert]::ToBase64String($sha.ComputeHash($bytes)) } finally { $sha.Dispose() }
        $lock = "@{ SchemaVersion = 1; Modules = @{ Pester = @{ Version = '5.5.0'; Uri = 'https://example.invalid/fixture'; SHA512 = '$hash' } } }"
        Set-Content -LiteralPath (Join-Path $tools 'Dependencies.psd1') -Value $lock
        [pscustomobject]@{
            Root = $Directory; Package = $package; Hash = $hash
            Script = (Join-Path $tools 'Install-DevDependencies.ps1')
            Destination = (Join-Path $Directory '.tools\modules\Pester\5.5.0')
        }
    }
}

Describe 'Development dependency bootstrap' {
    BeforeEach {
        $script:Fixture = New-BootstrapFixture -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        Mock Invoke-WebRequest {
            $fixtureRoot = $OutFile
            foreach ($level in 1..4) { $fixtureRoot = Split-Path -Parent $fixtureRoot }
            Copy-Item -LiteralPath (Join-Path $fixtureRoot 'fixture.nupkg') -Destination $OutFile
        }
    }
    It 'installs only a verified local package without importing module code' {
        & $script:Fixture.Script -Confirm:$false
        Test-Path -LiteralPath (Join-Path $script:Fixture.Destination 'Pester.psd1') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $script:Fixture.Destination '.package-sha512') -Raw).Trim() | Should -Be $script:Fixture.Hash
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
    It 'does not download or create local tooling during WhatIf' {
        & $script:Fixture.Script -WhatIf
        Test-Path -LiteralPath (Join-Path $script:Fixture.Root '.tools') | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Times 0
    }
    It 'rejects mismatched package bytes before extraction' {
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'corrupted response' }
        { & $script:Fixture.Script -Confirm:$false } | Should -Throw '*SHA512 verification failed*'
        Test-Path -LiteralPath $script:Fixture.Destination | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Join-Path $script:Fixture.Root '.tools\downloads') -Directory |
            ForEach-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'extracted') }) | Should -Not -Contain $true
    }
    It 'rejects archive entries outside the extraction root' {
        $script:Fixture = New-BootstrapFixture -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -Traversal
        { & $script:Fixture.Script -Confirm:$false } | Should -Throw '*outside its extraction directory*'
        Test-Path -LiteralPath $script:Fixture.Destination | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:Fixture.Root -Recurse -File | Where-Object { $_.Name -eq 'escape.ps1' }).Count | Should -Be 0
    }
    It 'rejects unexpected module versions' {
        $script:Fixture = New-BootstrapFixture -Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -ManifestVersion '6.0.0'
        { & $script:Fixture.Script -Confirm:$false } | Should -Throw '*version mismatch*'
        Test-Path -LiteralPath $script:Fixture.Destination | Should -BeFalse
    }
    It 'reuses an installed pinned package without downloading again' {
        & $script:Fixture.Script -Confirm:$false
        & $script:Fixture.Script -Confirm:$false
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }
    It 'refuses to overwrite an incomplete or unrecognized installation' {
        $null = New-Item -ItemType Directory -Path $script:Fixture.Destination -Force
        { & $script:Fixture.Script -Confirm:$false } | Should -Throw '*Incomplete or unrecognized*'
        Should -Invoke Invoke-WebRequest -Times 0
    }
    It 'restores the process TLS setting when download fails' {
        $previous = [Net.ServicePointManager]::SecurityProtocol
        Mock Invoke-WebRequest { throw 'synthetic download failure' }
        { & $script:Fixture.Script -Confirm:$false } | Should -Throw '*synthetic download failure*'
        [Net.ServicePointManager]::SecurityProtocol | Should -Be $previous
    }
}

Describe 'CI safety contract' {
    BeforeAll { $workflow = Get-Content -LiteralPath (Join-Path $ProjectRoot '.github\workflows\ci.yml') -Raw }
    It 'uses immutable official action revisions' {
        $actions = [regex]::Matches($workflow, 'uses:\s*(\S+)')
        $actions.Count | Should -Be 2
        foreach ($action in $actions) { $action.Groups[1].Value | Should -Match '^actions/(checkout|upload-artifact)@[a-f0-9]{40}$' }
    }
    It 'tests both engines with minimal permissions and bounded execution' {
        $workflow | Should -Match 'shell:\s*\[powershell, pwsh\]'
        $workflow | Should -Match 'contents:\s*read'
        $workflow | Should -Match 'persist-credentials:\s*false'
        $workflow | Should -Match 'timeout-minutes:\s*20'
        $workflow | Should -Not -Match 'pull_request_target|secrets\.|contents:\s*write'
    }
    It 'invokes development validation only, not machine maintenance' {
        $workflow | Should -Match '\./tools/Install-DevDependencies\.ps1'
        $workflow | Should -Match '\./Test\.ps1 -Coverage'
        $workflow | Should -Not -Match 'diskpart|powercfg|chkdsk|Set-Disk|schtasks|Scan-Lan|Invoke-SystemCleanup'
        $workflow | Should -Match 'if:\s*always\(\)'
    }
}
