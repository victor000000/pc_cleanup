BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'src\DirectoryScan.ps1')
    . (Join-Path $ProjectRoot 'src\DirectoryReview.ps1')
    function New-ReviewFile([string]$Name, [int]$Bytes) {
        $path = Join-Path $script:ReviewRoot $Name
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllBytes($path, (New-Object byte[] $Bytes))
        return $path
    }
}

Describe 'Read-only structured cleanup review' {
    BeforeEach {
        $script:ReviewRoot = Join-Path $TestDrive ('review [literal] ' + [guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($script:ReviewRoot)
    }
    It 'returns explicit complete empty arrays and release metadata for an empty directory' {
        $r = Get-DirectoryReviewReport -RootPath $script:ReviewRoot
        $r.ToolVersion | Should -Be '0.0.3'
        $r.SchemaVersion | Should -Be 1
        $r.ScanStatus | Should -Be 'Complete'
        $r.Candidates.Count | Should -Be 0
        $r.Warnings.Count | Should -Be 0
        $r.LogicalBytesScanned | Should -Be 0
        $r.FilesScanned | Should -Be 0
        $r.ReviewRequired | Should -BeTrue
        $r.CandidatesTruncated | Should -BeFalse
        $r.WarningsTruncated | Should -BeFalse
        $r.SizeMeaning | Should -Match 'not allocated or reclaimable'
    }
    It 'includes the exact size threshold, ranks top matches, and counts all readable files' {
        $null = New-ReviewFile 'z.bin' 10
        $null = New-ReviewFile 'a.bin' 10
        $null = New-ReviewFile 'big.bin' 20
        $null = New-ReviewFile 'small.bin' 3
        $r = Get-DirectoryReviewReport -RootPath $script:ReviewRoot -MinimumFileBytes 10 -Top 2
        $r.FilesScanned | Should -Be 4
        $r.LogicalBytesScanned | Should -Be 43
        $r.MatchingFileCount | Should -Be 3
        $r.Candidates.Count | Should -Be 2
        $r.Candidates[0].Path | Should -Be (Join-Path $script:ReviewRoot 'big.bin')
        $r.Candidates[1].Path | Should -Be (Join-Path $script:ReviewRoot 'a.bin')
        $r.CandidatesTruncated | Should -BeTrue
        $r.ScanStatus | Should -Be 'Complete'
        $r.Candidates[0].LastWriteTimeUtc | Should -Match 'Z$'
    }
    It 'keeps totals independent of a bounded candidate list across many matches' {
        foreach ($i in 1..50) { $null = New-ReviewFile ("$i.bin") $i }
        $r = Get-DirectoryReviewReport -RootPath $script:ReviewRoot -MinimumFileBytes 0 -Top 1
        $r.MatchingFileCount | Should -Be 50
        $r.Candidates.Count | Should -Be 1
        $r.Candidates[0].Bytes | Should -Be 50
        $r.LogicalBytesScanned | Should -Be 1275
    }
    It 'provides cautious extension categories without reading candidate content' -ForEach @(
        @{ Name = 'disk.VHDX'; Category = 'VirtualDisk'; Note = 'live environment' }
        @{ Name = 'data.duckdb'; Category = 'Database'; Note = 'writers' }
        @{ Name = 'program.exe'; Category = 'InstallerOrExecutable'; Note = 'installed program' }
        @{ Name = 'backup.zip'; Category = 'ArchiveOrImage'; Note = 'unique backup' }
        @{ Name = 'trace.log'; Category = 'LogOrDump'; Note = 'diagnostics' }
        @{ Name = 'notes.txt'; Category = 'Other'; Note = 'ownership' }
    ) {
        $file = New-ReviewFile $Name 17
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
        $lock = [IO.File]::Open($file, 'Open', 'ReadWrite', 'None')
        try { $r = Get-DirectoryReviewReport -RootPath $script:ReviewRoot -MinimumFileBytes 0 }
        finally { $lock.Dispose() }
        $r.ScanStatus | Should -Be 'Complete'
        $r.Candidates[0].Category | Should -Be $Category
        $r.Candidates[0].ReviewNote | Should -Match $Note
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($file)) | Should -Be $before
        @(Get-ChildItem -LiteralPath $script:ReviewRoot -Force).Count | Should -Be 1
    }
    It 'counts all skipped paths while bounding the warning sample' {
        $null = New-ReviewFile 'good.bin' 7
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            foreach ($i in 1..4) {
                [pscustomobject]@{ FullName = "unsafe-$i"; Attributes = [long]0x400 }
            }
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
        }
        $r = Get-DirectoryReviewReport -RootPath $script:ReviewRoot -MinimumFileBytes 0 -WarningLimit 2
        $r.ScanStatus | Should -Be 'Partial'
        $r.WarningCount | Should -Be 4
        $r.Warnings.Count | Should -Be 2
        $r.WarningsTruncated | Should -BeTrue
        $r.LogicalBytesScanned | Should -Be 7
        $r.Candidates.Count | Should -Be 1
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 1 -Exactly
    }
    It 'keeps missing and file roots explicitly partial even with a zero warning sample' {
        $file = New-ReviewFile 'file.bin' 3
        foreach ($path in @($file, (Join-Path $script:ReviewRoot 'missing'))) {
            $r = Get-DirectoryReviewReport -RootPath $path -WarningLimit 0
            $r.ScanStatus | Should -Be 'Partial'
            $r.WarningCount | Should -Be 1
            $r.Warnings.Count | Should -Be 0
            $r.WarningsTruncated | Should -BeTrue
            $r.FilesScanned | Should -Be 0
        }
    }
    It 'records unreadable file metadata and continues good entries' -ForEach @(
        @{ Property = 'Length'; Value = $null }
        @{ Property = 'Length'; Value = -1 }
        @{ Property = 'LastWriteTimeUtc'; Value = $null }
        @{ Property = 'LastWriteTimeUtc'; Value = 'not a timestamp' }
    ) {
        $null = New-ReviewFile 'good.bin' 7
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            $bad = [pscustomobject]@{ FullName = 'bad.bin'; Attributes = 0; Length = 4; LastWriteTimeUtc = [datetime]::UtcNow }
            $bad.$Property = $Value
            $bad
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
        }
        $r = Get-DirectoryReviewReport -RootPath $script:ReviewRoot -MinimumFileBytes 0
        $r.ScanStatus | Should -Be 'Partial'
        $r.WarningCount | Should -Be 1
        $r.FilesScanned | Should -Be 1
        $r.LogicalBytesScanned | Should -Be 7
        $r.Candidates.Count | Should -Be 1
    }
    It 'resolves relative literal paths using the PowerShell filesystem location' {
        $null = New-ReviewFile 'good.bin' 3
        Push-Location -LiteralPath (Split-Path -Parent $script:ReviewRoot)
        try { $r = Get-DirectoryReviewReport -RootPath (Split-Path -Leaf $script:ReviewRoot) -MinimumFileBytes 0 }
        finally { Pop-Location }
        $r.RootPath | Should -Be $script:ReviewRoot
        $r.FilesScanned | Should -Be 1
    }
    It 'rejects non-filesystem providers and invalid limits before scanning' {
        { Get-DirectoryReviewReport -RootPath 'Env:\' } | Should -Throw '*filesystem*'
        { Get-DirectoryReviewReport -RootPath $script:ReviewRoot -Top 0 } | Should -Throw
        { Get-DirectoryReviewReport -RootPath $script:ReviewRoot -MinimumFileBytes -1 } | Should -Throw
        { Get-DirectoryReviewReport -RootPath $script:ReviewRoot -WarningLimit -1 } | Should -Throw
    }
    It 'emits one JSON document with stable arrays and warnings inside the report' {
        $entry = Join-Path $ProjectRoot 'scripts\reports\Get-CleanupReview.ps1'
        $null = New-ReviewFile 'only.db' 3
        $json = @(& $entry -RootPath $script:ReviewRoot -MinimumFileBytes 0 -Format Json 3>&1)
        $json.Count | Should -Be 1
        $r = $json[0] | ConvertFrom-Json
        ($r.Candidates -is [array]) | Should -BeTrue
        $r.Candidates.Count | Should -Be 1
        ($r.Warnings -is [array]) | Should -BeTrue
        $r.Warnings.Count | Should -Be 0
        $r.Candidates[0].Bytes | Should -Be 3
        $partial = @(& $entry -RootPath (Join-Path $script:ReviewRoot 'missing') -Format Json 3>&1)
        $partial.Count | Should -Be 1
        ($partial[0] | ConvertFrom-Json).ScanStatus | Should -Be 'Partial'
        $object = & $entry -RootPath $script:ReviewRoot -MinimumFileBytes 0
        $object.SchemaVersion | Should -Be 1
    }
}
