# Read metadata only. Never descend into links or hydrate cloud placeholders.
function Get-DirectoryScanFileSystemInfos {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$Directory)

    # Keep this non-recursive boundary separate so directory failures can be tested.
    foreach ($entry in $Directory.EnumerateFileSystemInfos()) {
        $entry
    }
}

function Get-DirectoryScanChildren {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    # Recall flags are numeric because they are not named on all PS5.1 runtimes.
    $excludedAttributes = [long][System.IO.FileAttributes]::ReparsePoint -bor
        [long][System.IO.FileAttributes]::Offline -bor 0x40000 -bor 0x400000
    try {
        # Check even the root, and check queued directories again before opening them.
        # DirectoryInfo.Exists would silently turn access failures into "not found".
        $attributes = [System.IO.File]::GetAttributes($Path)
        if (([long]$attributes -band $excludedAttributes) -ne 0) {
            Write-Warning "Directory scan incomplete: skipped reparse point or cloud placeholder '$Path'." -WarningAction Continue
            return
        }
        if (($attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
            Write-Warning "Directory scan incomplete: '$Path' is not a directory." -WarningAction Continue
            return
        }
        $directory = [System.IO.DirectoryInfo]::new($Path)
        Get-DirectoryScanFileSystemInfos -Directory $directory -ErrorAction Stop | ForEach-Object {
            $entry = $_
            try {
                $entryAttributes = $entry.Attributes
                if ($null -eq $entryAttributes) {
                    throw [System.IO.IOException]::new('Entry attributes are unavailable.')
                }
                if (([long]$entryAttributes -band $excludedAttributes) -ne 0) {
                    Write-Warning "Directory scan incomplete: skipped reparse point or cloud placeholder '$($entry.FullName)'." -WarningAction Continue
                } else {
                    $entry
                }
            } catch {
                Write-Warning "Directory scan incomplete: cannot inspect an entry in '$Path': $($_.Exception.Message)" -WarningAction Continue
            }
        }
    } catch {
        # Only this directory failed. Entries already emitted are not rescanned or added twice.
        Write-Warning "Directory scan incomplete: cannot enumerate '$Path': $($_.Exception.Message)" -WarningAction Continue
    }
}

function Get-DirectoryScanFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        # Stream each directory so a late failure retains its readable entries and
        # already queued siblings. Never retry recursively with a second traversal.
        Get-DirectoryScanChildren -Path $current | ForEach-Object {
            if (($_.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                $stack.Push($_.FullName)
            } else {
                $_
            }
        }
    }
}

function Get-DirSize {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $sum = 0L
    Get-DirectoryScanFiles -Path $Path | ForEach-Object {
        $file = $_
        try {
            $length = $file.Length
            if ($null -eq $length) {
                throw [System.IO.IOException]::new('File length is unavailable.')
            }
            $sum += $length
        } catch {
            Write-Warning "Directory scan incomplete: cannot read length of '$($file.FullName)': $($_.Exception.Message)" -WarningAction Continue
        }
    }
    return $sum
}

# Report helpers deliberately share the scanner's metadata-only, literal-path
# boundary. No report labels a directory as safe to delete.
function Get-DirectoryReportDefaultPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateSet('Root', 'Profile')][string]$Kind)

    if ($Kind -eq 'Profile') {
        $path = [Environment]::GetFolderPath('UserProfile')
        if ([string]::IsNullOrWhiteSpace($path)) { $path = $env:USERPROFILE }
    } else {
        $path = $env:SystemDrive
        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = [System.IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))
        } else {
            $path += [System.IO.Path]::DirectorySeparatorChar
        }
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Cannot discover the current $Kind path. Supply an explicit path parameter."
    }
    $path
}

function ConvertTo-DirectoryReportFileRow {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)][object]$File)

    process {
        try {
            $length = $File.Length
            if ($null -eq $length) { throw [System.IO.IOException]::new('File length is unavailable.') }
            [pscustomobject]@{
                Name = $File.Name
                Path = $File.FullName
                Bytes = [long]$length
                GB = [math]::Round($length / 1GB, 2)
                Extension = $File.Extension
                LastWriteTime = $File.LastWriteTime
            }
        } catch {
            Write-Warning "Directory scan incomplete: cannot read metadata of '$($File.FullName)': $($_.Exception.Message)" -WarningAction Continue
        }
    }
}

function Show-DirectoryFileReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowEmptyCollection()][object[]]$Rows = @(),
        [ValidateRange(1, 1000)][int]$Top = 30
    )

    "`n=== $Label ==="
    $Rows | Sort-Object Bytes -Descending | Select-Object -First $Top |
        Format-Table GB, Path, LastWriteTime -AutoSize | Out-String -Width 240
}

function Show-DirectorySizeReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateRange(1, 1000)][int]$Top = 30,
        [switch]$IncludeRootFiles,
        [ValidateRange(0, [long]::MaxValue)][long]$MinimumFileBytes = 50MB
    )

    "`n=== $Label ($Path) ==="
    $entries = @(Get-DirectoryScanChildren -Path $Path)
    $rows = foreach ($entry in $entries) {
        if (($entry.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            $bytes = Get-DirSize -Path $entry.FullName
            [pscustomobject]@{ Path = $entry.FullName; Bytes = $bytes; GB = [math]::Round($bytes / 1GB, 2) }
        }
    }
    # Sort by the exact byte count, not the rounded display value.
    $rows | Sort-Object Bytes -Descending | Select-Object -First $Top |
        Format-Table GB, Path -AutoSize | Out-String -Width 240
    if ($IncludeRootFiles) {
        $files = @($entries |
            Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 } |
            ConvertTo-DirectoryReportFileRow | Where-Object { $_.Bytes -gt $MinimumFileBytes })
        Show-DirectoryFileReport -Label "Root files over $MinimumFileBytes bytes" -Rows $files -Top $Top
    }
}
