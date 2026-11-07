# Metadata-only review records; caller loads DirectoryScan.ps1 first.
function Add-DirectoryReviewWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Message, [int]$Limit)
    $State.Count++
    if ($State.Messages.Count -lt $Limit) { $State.Messages.Add($Message) }
}

function Get-DirectoryReviewReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RootPath,
        [ValidateRange(0, [long]::MaxValue)][long]$MinimumFileBytes = 100MB,
        [ValidateRange(1, 1000)][int]$Top = 40,
        [ValidateRange(0, 1000)][int]$WarningLimit = 20
    )

    $provider = $null
    $drive = $null
    $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $RootPath, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') { throw 'Review requires a filesystem path.' }
    $started = [datetime]::UtcNow
    $version = Import-PowerShellDataFile -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Project.psd1')
    $warnings = [pscustomobject]@{ Count = 0L; Messages = [Collections.Generic.List[string]]::new() }
    $candidates = [Collections.Generic.List[object]]::new()
    $filesScanned = 0L
    $bytesScanned = 0L
    $matches = 0L
    # Stream files and warnings together so partial results remain explicit in
    # serialized output. Never accumulate the complete file or warning stream.
    Get-DirectoryScanFiles -Path $root 3>&1 | ForEach-Object {
        $file = $_
        if ($file -is [System.Management.Automation.WarningRecord]) {
            Add-DirectoryReviewWarning -State $warnings -Message $file.Message -Limit $WarningLimit
        } else {
            $path = '<unknown>'
            try {
                $path = $file.FullName
                $length = $file.Length
                if ($null -eq $length -or $length -lt 0) { throw 'File length is unavailable or invalid.' }
                $modified = $file.LastWriteTimeUtc
                if ($null -eq $modified) { throw 'File modification time is unavailable.' }
                $modifiedUtc = ([datetime]$modified).ToUniversalTime().ToString('o')
                $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
                $filesScanned++
                $bytesScanned += [long]$length
                if ($length -ge $MinimumFileBytes) {
                    $matches++
                    $category = 'Other'
                    $note = 'Review ownership and retention before considering removal.'
                    if ($extension -in @('.vhd', '.vhdx', '.vmdk', '.qcow2', '.vmem', '.vmss', '.img')) {
                        $category = 'VirtualDisk'
                        $note = 'May contain a live environment; verify its owner and activity.'
                    } elseif ($extension -in @('.db', '.sqlite', '.sqlite3', '.duckdb', '.mdb', '.accdb', '.wal')) {
                        $category = 'Database'
                        $note = 'May contain live or unrecoverable data; verify writers, backups and retention.'
                    } elseif ($extension -in @('.exe', '.msi', '.msix')) {
                        $category = 'InstallerOrExecutable'
                        $note = 'May be an installed program rather than a disposable installer.'
                    } elseif ($extension -in @('.zip', '.7z', '.rar', '.tar', '.gz', '.iso', '.ova')) {
                        $category = 'ArchiveOrImage'
                        $note = 'May be a unique backup or source archive; verify contents and retention.'
                    } elseif ($extension -in @('.log', '.dmp')) {
                        $category = 'LogOrDump'
                        $note = 'May be needed for diagnostics; verify retention and active writers.'
                    }
                    $candidates.Add([pscustomobject]@{
                        Path = $path
                        Bytes = [long]$length
                        GiB = [math]::Round($length / 1GB, 3)
                        LastWriteTimeUtc = $modifiedUtc
                        Category = $category
                        ReviewNote = $note
                    })
                    if ($candidates.Count -gt $Top) {
                        $ranked = @($candidates | Sort-Object @{ Expression = 'Bytes'; Descending = $true }, Path)
                        $candidates.Clear()
                        foreach ($row in ($ranked | Select-Object -First $Top)) { $candidates.Add($row) }
                    }
                }
            } catch {
                Add-DirectoryReviewWarning -State $warnings -Limit $WarningLimit -Message (
                    "Cannot inspect file metadata '$path': $($_.Exception.Message)")
            }
        }
    }
    $status = 'Complete'
    if ($warnings.Count -gt 0) { $status = 'Partial' }
    [pscustomobject]@{
        SchemaVersion = 1
        ToolVersion = $version.Version
        RootPath = $root
        StartedAtUtc = $started.ToString('o')
        CompletedAtUtc = [datetime]::UtcNow.ToString('o')
        ScanStatus = $status
        WarningCount = $warnings.Count
        Warnings = @($warnings.Messages.ToArray())
        WarningsTruncated = ($warnings.Count -gt $warnings.Messages.Count)
        FilesScanned = $filesScanned
        LogicalBytesScanned = $bytesScanned
        MinimumFileBytes = $MinimumFileBytes
        MatchingFileCount = $matches
        CandidateLimit = $Top
        CandidatesTruncated = ($matches -gt $Top)
        Candidates = @($candidates | Sort-Object @{ Expression = 'Bytes'; Descending = $true }, Path)
        SizeMeaning = 'Logical file lengths, not allocated or reclaimable space; hard links may be counted more than once.'
        ReviewRequired = $true
    }
}
