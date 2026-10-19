# Windows PowerShell 5.1 compatible. Dot-sourcing this file only defines functions.

function Resolve-MaintenanceVhdPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    # DiskPart has its own parser: never allow quotes, control characters, ADS,
    # wildcard expansion, device paths, relative paths, or remote image paths.
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or
        $Path -match '[\x00-\x1f"*?<>|]' -or $Path.Substring(2).Contains(':')) {
        throw 'Specify one absolute local VHD/VHDX file path without wildcards or command characters.'
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem' -or $item.PSIsContainer -or
        $item.Extension -notin @('.vhd', '.vhdx')) {
        throw "Not a VHD/VHDX file: $Path"
    }
    # Reject junction/symlink traversal as well as a reparse-point image itself.
    $entry = $item
    while ($null -ne $entry) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse-point VHD paths are not supported: $Path"
        }
        if ($entry -is [IO.FileInfo]) { $entry = $entry.Directory }
        else { $entry = $entry.Parent }
    }
    return $item.FullName
}

function Assert-MaintenanceStorageCommands {
    [CmdletBinding()]
    param()

    $required = @{
        'Get-DiskImage' = @('ImagePath', 'ErrorAction')
        'Mount-DiskImage' = @('ImagePath', 'Access', 'NoDriveLetter', 'PassThru', 'ErrorAction', 'Confirm')
        'Dismount-DiskImage' = @('ImagePath', 'ErrorAction', 'Confirm')
    }
    foreach ($name in $required.Keys) {
        $command = Get-Command -Name $name -ErrorAction Stop
        foreach ($parameter in $required[$name]) {
            if (-not $command.Parameters.ContainsKey($parameter)) {
                throw "Required Storage API unavailable: $name -$parameter. No DiskPart attachment fallback is used."
            }
        }
    }
}

function Assert-MaintenanceVhdDetached {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $images = @(Get-DiskImage -ImagePath $Path -ErrorAction Stop)
    if ($images.Count -ne 1 -or $images[0].ImagePath -ine $Path -or
        $null -eq $images[0].Attached) {
        throw "Cannot establish attachment state for exactly this image: $Path"
    }
    if ($images[0].Attached) {
        throw "Image is already attached; it will NOT be compacted or detached: $Path. Stop its owner manually and retry."
    }
}

function Assert-MaintenanceVhdExclusiveAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    try {
        # Open, never create/truncate/write. Release before the Storage mount.
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch {
        throw "VHD is in use or cannot be opened exclusively: $Path. Stop WSL/Docker yourself; nothing will be killed. $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-MaintenanceVhdPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $imagePath = Resolve-MaintenanceVhdPath -Path $Path
    Assert-MaintenanceStorageCommands
    Assert-MaintenanceVhdDetached -Path $imagePath
    Assert-MaintenanceVhdExclusiveAccess -Path $imagePath
    return $imagePath
}

function Assert-MaintenanceWmiAvailable {
    [CmdletBinding()]
    param()

    # Real WMI maintenance is supported only by Windows PowerShell 5.1.
    # Unit tests may mock this guard as well as the WMI boundary on either engine.
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -lt 1 -or
        $PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'WMI pagefile maintenance requires Windows PowerShell 5.1 and Get-WmiObject; PowerShell 7 is not supported. No system changes made.'
    }
    if ($null -eq (Get-Command -Name Get-WmiObject -ErrorAction SilentlyContinue)) {
        throw 'Windows PowerShell 5.1 Get-WmiObject is unavailable. No system changes made.'
    }
}

function Resolve-MaintenanceHandleExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or
        $Path -match '[\x00-\x1f"*?<>|]' -or $Path.Substring(2).Contains(':')) {
        throw 'Handle requires an absolute local executable path without wildcards or command characters.'
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem' -or $item.PSIsContainer -or $item.Extension -ine '.exe') {
        throw 'Handle requires a local .exe file.'
    }
    $entry = $item
    while ($null -ne $entry) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Reparse-point Handle executable paths are not supported.'
        }
        if ($entry -is [IO.FileInfo]) { $entry = $entry.Directory }
        else { $entry = $entry.Parent }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $item.FullName -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Microsoft Corporation(,|$)') {
        throw 'Handle must have a valid Microsoft Corporation Authenticode signature. No executable was run.'
    }
    return $item.FullName
}

function Invoke-MaintenanceNativeCommand {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('diskpart.exe', 'dism.exe', 'powercfg.exe', 'handle64.exe')][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$ExecutablePath
    )

    if (-not $PSCmdlet.ShouldProcess($FileName, ($ArgumentList -join ' '))) { return }
    if ($FileName -eq 'handle64.exe') {
        if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { throw 'Handle requires an explicit local ExecutablePath.' }
        $source = Resolve-MaintenanceHandleExecutable -Path $ExecutablePath
    }
    else {
        if ($ExecutablePath) { throw 'ExecutablePath is supported only for the signed Handle diagnostic.' }
        $command = Get-Command -Name $FileName -CommandType Application -ErrorAction Stop
        $source = $command.Source
    }
    # This is the sole native-process boundary, so tests replace it rather
    # than run tools. A parent approval suppresses only the redundant prompt.
    $LASTEXITCODE = $null
    $output = @(& $source @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($null -eq $exitCode -or $exitCode -ne 0) {
        $exception = New-Object System.InvalidOperationException(
            "$FileName exit=$exitCode`r`n$text")
        $exception.Data['NativeExitCode'] = $exitCode
        throw $exception
    }
    [pscustomobject]@{ ExitCode = $exitCode; Output = $text }
}

function Invoke-VhdCompaction {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory = $true)][Alias('Path')][ValidateNotNullOrEmpty()][string]$VhdPath)

    if (-not $PSCmdlet.ShouldProcess($VhdPath, 'Exclusively check, attach read-only, compact VHD, and release owned attachment')) {
        return
    }
    # Reject other owners before opening the file. Repeat this full preflight
    # even when a combined entrypoint already checked before earlier changes.
    $imagePath = Get-MaintenanceVhdPreflight -Path $VhdPath

    $ownsAttachment = $false
    $scriptFile = $null
    $failure = $null
    $result = $null
    try {
        # Generate a per-operation script from the exact literal validated path.
        # UTF-16 preserves non-ASCII Windows file names. No 'noerr': fail closed.
        $scriptFile = New-TemporaryFile -ErrorAction Stop
        [IO.File]::WriteAllLines($scriptFile.FullName, [string[]]@(
            ('select vdisk file="{0}"' -f $imagePath),
            'compact vdisk',
            'exit'
        ), [Text.Encoding]::Unicode)
        Assert-MaintenanceVhdDetached -Path $imagePath
        $null = Mount-DiskImage -ImagePath $imagePath -Access ReadOnly -NoDriveLetter `
            -PassThru -ErrorAction Stop -Confirm:$false
        # Ownership is acquired ONLY when our mount call returns successfully.
        $ownsAttachment = $true
        $attached = @(Get-DiskImage -ImagePath $imagePath -ErrorAction Stop)
        if ($attached.Count -ne 1 -or $attached[0].ImagePath -ine $imagePath -or
            -not $attached[0].Attached) {
            throw "Read-only attachment could not be verified: $imagePath"
        }
        $native = Invoke-MaintenanceNativeCommand -FileName 'diskpart.exe' `
            -ArgumentList @('/s', $scriptFile.FullName) -Confirm:$false
        # DiskPart can report command errors with exit 0. Require an explicit
        # compact success acknowledgement, not merely selection or 100% progress.
        # English and this machine's Simplified Chinese are supported; other
        # locales fail closed with the complete output for review.
        $chineseSuccess = 'DiskPart ' + [string]::Concat(
            [char]0x5df2, [char]0x6210, [char]0x529f, [char]0x538b, [char]0x7f29,
            [char]0x865a, [char]0x62df, [char]0x78c1, [char]0x76d8,
            [char]0x6587, [char]0x4ef6, [char]0x3002)
        $englishSuccess = 'DiskPart successfully compacted the virtual disk file.'
        $successLines = @($native.Output -split '\r?\n' | ForEach-Object { $_.Trim() })
        $errorPattern = '\b(error|failed|failure)\b|' +
            [regex]::Escape([string]::Concat([char]0x9519, [char]0x8bef)) + '|' +
            [regex]::Escape([string]::Concat([char]0x5931, [char]0x8d25))
        if ($native.ExitCode -ne 0 -or $native.Output -match $errorPattern -or
            ($successLines -inotcontains $englishSuccess -and $successLines -notcontains $chineseSuccess)) {
            throw "DiskPart compaction was not positively acknowledged (exit=$($native.ExitCode)).`r`n$($native.Output)"
        }
        $result = [pscustomobject]@{
            Path = $imagePath
            Length = (Get-Item -LiteralPath $imagePath -Force -ErrorAction Stop).Length
            Output = $native.Output
        }
    }
    catch { $failure = $_ }
    finally {
        # Cleanup must run even when compaction, verification, or logging fails.
        # A failed/pre-existing mount is NEVER detached by this operation.
        if ($ownsAttachment) {
            try {
                $null = Dismount-DiskImage -ImagePath $imagePath -ErrorAction Stop -Confirm:$false
            }
            catch {
                # WarningPreference=Stop must not interrupt the remaining cleanup
                # or replace the primary error. Cleanup diagnostics stay visible.
                Write-Warning "Owned VHD attachment cleanup failed for ${imagePath}: $($_.Exception.Message)" -WarningAction Continue
                if ($null -eq $failure) { $failure = $_ }
            }
        }
        if ($null -ne $scriptFile) {
            try { Remove-Item -LiteralPath $scriptFile.FullName -Force -ErrorAction Stop }
            catch {
                Write-Warning "Temporary DiskPart script cleanup failed: $($_.Exception.Message)" -WarningAction Continue
                if ($null -eq $failure) { $failure = $_ }
            }
        }
    }
    if ($null -ne $failure) { $PSCmdlet.ThrowTerminatingError($failure) }
    return $result
}

function Set-CPageFileSize {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [ValidateRange(1, 2147483647)][int]$InitialSizeMB = 16384,
        [ValidateRange(1, 2147483647)][int]$MaximumSizeMB = 32768
    )

    if ($InitialSizeMB -gt $MaximumSizeMB) { throw 'Initial pagefile size must not exceed maximum size.' }
    if (-not $PSCmdlet.ShouldProcess('C:\pagefile.sys', "Set WMI pagefile to $InitialSizeMB/$MaximumSizeMB MB and disable automatic management (reboot required)")) {
        return
    }
    Assert-MaintenanceWmiAvailable
    # Resolve and validate ONE target before changing AutomaticManagedPagefile.
    # Never assign properties on the array returned for multiple pagefiles.
    $systems = @(Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop)
    $settings = @(Get-WmiObject -Class Win32_PageFileSetting -ErrorAction Stop)
    $targets = @($settings | Where-Object { $_.Name -ieq 'C:\pagefile.sys' })
    if ($systems.Count -ne 1 -or $targets.Count -ne 1 -or
        $systems[0].AutomaticManagedPagefile -isnot [bool]) {
        throw 'Expected one computer system and exactly one existing C:\pagefile.sys setting; no pagefile changes made.'
    }
    $system = $systems[0]
    $target = $targets[0]
    if ($null -eq $target.InitialSize -or $null -eq $target.MaximumSize) {
        throw 'Cannot snapshot the existing C: pagefile sizes; no pagefile changes made.'
    }
    $oldAutomatic = $system.AutomaticManagedPagefile
    $oldInitial = $target.InitialSize
    $oldMaximum = $target.MaximumSize
    $systemAttempted = $false
    $targetAttempted = $false
    try {
        $systemAttempted = $true
        $system.AutomaticManagedPagefile = $false
        $null = $system.Put()
        $targetAttempted = $true
        $target.InitialSize = $InitialSizeMB
        $target.MaximumSize = $MaximumSizeMB
        $null = $target.Put()
        $verifySystem = @(Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop)
        $verifyTarget = @(Get-WmiObject -Class Win32_PageFileSetting -ErrorAction Stop |
            Where-Object { $_.Name -ieq 'C:\pagefile.sys' })
        if ($verifySystem.Count -ne 1 -or $verifySystem[0].AutomaticManagedPagefile -ne $false -or
            $verifyTarget.Count -ne 1 -or $verifyTarget[0].InitialSize -ne $InitialSizeMB -or
            $verifyTarget[0].MaximumSize -ne $MaximumSizeMB) {
            throw 'Pagefile WMI read-back verification failed.'
        }
    }
    catch {
        $originalFailure = $_
        if ($targetAttempted) {
            try {
                $target.InitialSize = $oldInitial
                $target.MaximumSize = $oldMaximum
                $null = $target.Put()
            }
            catch { Write-Warning "C: pagefile rollback failed: $($_.Exception.Message)" -WarningAction Continue }
        }
        if ($systemAttempted) {
            try {
                $system.AutomaticManagedPagefile = $oldAutomatic
                $null = $system.Put()
            }
            catch { Write-Warning "Automatic pagefile management rollback failed: $($_.Exception.Message)" -WarningAction Continue }
        }
        $PSCmdlet.ThrowTerminatingError($originalFailure)
    }
    'C:\pagefile.sys updated; other pagefile settings were not modified. Reboot required.'
}

function Set-CPageFileRegistrySize {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [ValidateRange(1, 2147483647)][int]$InitialSizeMB = 16384,
        [ValidateRange(1, 2147483647)][int]$MaximumSizeMB = 32768
    )

    if ($InitialSizeMB -gt $MaximumSizeMB) { throw 'Initial pagefile size must not exceed maximum size.' }
    if (-not $PSCmdlet.ShouldProcess('C:\pagefile.sys in PagingFiles', "Replace only the C: entry with $InitialSizeMB/$MaximumSizeMB MB (reboot required)")) {
        return
    }
    $keyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $key = Get-Item -LiteralPath $keyPath -ErrorAction Stop
    if ($key.GetValueKind('PagingFiles') -ne [Microsoft.Win32.RegistryValueKind]::MultiString) {
        throw 'PagingFiles must be an existing REG_MULTI_SZ; no registry changes made.'
    }
    $old = @((Get-ItemProperty -LiteralPath $keyPath -Name PagingFiles -ErrorAction Stop).PagingFiles)
    $indices = @()
    for ($i = 0; $i -lt $old.Count; $i++) {
        if ($old[$i] -match '^\s*"?C:\\pagefile\.sys"?\s+\d+\s+\d+\s*$') { $indices += $i }
    }
    if ($indices.Count -ne 1) {
        throw 'Expected exactly one existing C:\pagefile.sys PagingFiles entry; no registry changes made.'
    }
    $updated = [string[]]$old.Clone()
    $updated[$indices[0]] = "C:\pagefile.sys $InitialSizeMB $MaximumSizeMB"
    try {
        Set-ItemProperty -LiteralPath $keyPath -Name PagingFiles -Value $updated -Type MultiString -ErrorAction Stop
        $actual = @((Get-ItemProperty -LiteralPath $keyPath -Name PagingFiles -ErrorAction Stop).PagingFiles)
        if ($actual.Count -ne $updated.Count) { throw 'PagingFiles registry read-back verification failed.' }
        for ($i = 0; $i -lt $updated.Count; $i++) {
            if ($actual[$i] -cne $updated[$i]) { throw 'PagingFiles registry read-back verification failed.' }
        }
    }
    catch {
        $originalFailure = $_
        try {
            Set-ItemProperty -LiteralPath $keyPath -Name PagingFiles -Value ([string[]]$old) -Type MultiString -ErrorAction Stop
        }
        catch { Write-Warning "PagingFiles registry rollback failed: $($_.Exception.Message)" -WarningAction Continue }
        $PSCmdlet.ThrowTerminatingError($originalFailure)
    }
    'Only the C:\pagefile.sys registry entry was updated. Reboot required; automatic-management policy may override it.'
}

function New-MaintenanceLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Operation,
        [string]$LogPath
    )

    # Call only after the entrypoint's ShouldProcess approval and preflight.
    # Never use a fixed file name: concurrent/default invocations keep separate logs.
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $root = Split-Path -Parent $PSScriptRoot
        $LogPath = Join-Path $root ('.local\logs\{0}-{1}-{2}.log' -f
            $Operation, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N')))
    }
    $parent = Split-Path -Parent $LogPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop
    }
    return $LogPath
}

function Write-MaintenanceLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message,
        [switch]$Start
    )
    if ($Start) { $Message | Out-File -LiteralPath $LogPath -Encoding utf8 -ErrorAction Stop }
    else { $Message | Out-File -LiteralPath $LogPath -Encoding utf8 -Append -ErrorAction Stop }
}

function Write-MaintenanceFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)]$Failure
    )
    # Logging must never replace the original terminating error.
    try { Write-MaintenanceLog -LogPath $LogPath -Message "=== FAILED $(Get-Date): $Failure ===" }
    catch { Write-Warning "Failure log could not be written: $($_.Exception.Message)" -WarningAction Continue }
}
