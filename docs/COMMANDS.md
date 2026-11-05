# Command reference

[README](../README.md) · [Safety](SAFETY.md) · [Troubleshooting](TROUBLESHOOTING.md)

Run the PowerShell examples from the project root on Windows. Imports resolve relative to each script, so absolute script paths also work from another directory. Optional arguments use the defaults below; script parameter blocks are the source of truth. `Get-Help <script> -Full` includes detailed descriptions where comment-based help exists.

## Reports

Reports require no elevation and emit formatted text, not CSV/JSON records. They skip links, offline files, and cloud recall placeholders; warnings mean totals are partial. Displayed `GB` values divide logical byte lengths by PowerShell's `1GB` constant (1,073,741,824 bytes). Allocated space and reclaimable space can differ.

| Script in `scripts/reports/` | Parameters and defaults | Scope |
|---|---|---|
| [Scan-TopLevel.ps1](../scripts/reports/Scan-TopLevel.ps1) | `-RootPath` = system-drive root; `-Top 25`; `-MinimumFileBytes 100MB` | Immediate subdirectories measured recursively; files directly under the root above the threshold |
| [Scan-UserProfile.ps1](../scripts/reports/Scan-UserProfile.ps1) | `-ProfilePath` = current profile; `-Top 40` | Profile overview plus Local/Roaming/LocalLow AppData, Downloads, Documents, Desktop, Videos, and Pictures |
| [Scan-LargeFiles.ps1](../scripts/reports/Scan-LargeFiles.ps1) | `-ProfilePath` = current profile; `-MinimumFileBytes 1GB`; `-Top 40` | One recursive traversal; disk/VM images regardless of size, plus other files above the threshold |
| [Scan-AppData.ps1](../scripts/reports/Scan-AppData.ps1) | `-ProfilePath` = current profile; `-AppPath` = no extra locations; `-Top 25` | All three AppData branches plus each supplied application directory |
| [Get-DiskUsage.ps1](../scripts/reports/Get-DiskUsage.ps1) | `-RootPath` = system-drive root; `-ProfilePath` = current profile; `-Top 25` | Combined root/profile overview, selected Windows/temp/recycle locations, and profile files over 1GB |

`-Top` accepts 1–1000 and limits rows in each section after scanning/sorting. It does not cap traversal. Thresholds use **strictly greater than**, not greater than or equal to. In `Scan-TopLevel`, the threshold filters root files, not directories. Profile/AppData root-file sections use the shared 50MB default. `Get-DiskUsage` uses 100MB for system-root files and 50MB for profile-root files.

`Get-DiskUsage -RootPath ...` still scans the current profile unless `-ProfilePath` is also supplied. Use `Scan-TopLevel` when only one root should be scanned. Combined reports can traverse overlapping trees repeatedly; prefer a focused report when speed matters.

```powershell
.\scripts\reports\Scan-TopLevel.ps1 -RootPath "$env:USERPROFILE\Downloads" -Top 15
.\scripts\reports\Scan-LargeFiles.ps1 -ProfilePath $env:USERPROFILE -MinimumFileBytes 2GB -Top 20
.\scripts\reports\Scan-AppData.ps1 -ProfilePath $env:USERPROFILE -AppPath 'C:\path\application-data' -Top 15
```

To save a report, redirect its text to a deliberately chosen file. This caller-requested write is separate from scanning. Review warnings in the console; a saved table alone may omit partial-scan diagnostics.

## USB storage

Inspect inventory before selecting a target:

```powershell
Get-Disk | Format-List Number, FriendlyName, UniqueId, SerialNumber, BusType, IsBoot, IsSystem, IsOffline
```

| Script in `scripts/storage/` | Required target | Effect |
|---|---|---|
| [Eject-UsbDisk.ps1](../scripts/storage/Eject-UsbDisk.ps1) | Exactly one of `-UniqueId` or `-SerialNumber` | Orderly eject of the validated disk PnP node |
| [Set-UsbDiskOnline.ps1](../scripts/storage/Set-UsbDiskOnline.ps1) | `-ExpectedDiskUniqueId` | Bring one non-system USB disk online, then verify readback |
| [Set-UsbDriveLetter.ps1](../scripts/storage/Set-UsbDriveLetter.ps1) | `-ExpectedDiskUniqueId` and `-PartitionNumber` (1–128) | Assign `-DriveLetter` (D–Z, default F) to a non-system Basic data partition on an online USB disk |

These commands support `-WhatIf` and high-impact confirmation. Use a stable identity, never a drive letter or disk number as the identity. Disk numbers may be used for read-only partition inventory after matching the intended disk; mutation rechecks the mapping. Occupied letters are refused. An eject veto stops the operation without a force fallback.

```powershell
.\scripts\storage\Eject-UsbDisk.ps1 -UniqueId 'COPY-EXACT-USB-UNIQUE-ID' -WhatIf
.\scripts\storage\Set-UsbDiskOnline.ps1 -ExpectedDiskUniqueId 'COPY-EXACT-USB-UNIQUE-ID' -WhatIf
.\scripts\storage\Set-UsbDriveLetter.ps1 -ExpectedDiskUniqueId 'COPY-EXACT-USB-UNIQUE-ID' -PartitionNumber 1 -DriveLetter G -WhatIf
```

Replace all placeholders from fresh inventory. Omit `-WhatIf` only after reviewing the intended operation; elevated access may be required. The seven [compatibility aliases](MIGRATION.md) forward to `Eject-UsbDisk`; they do not run CHKDSK, elevate automatically, or use broader eject strategies despite their old names.

## Maintenance

All scripts in this table support `-WhatIf`, high-impact confirmation, and optional `-LogPath`. Plan to run approved changes in an elevated Windows session. Every command except `Disable-Hibernation` requires an explicit `-VhdPath`; none discovers or shuts down a WSL/Docker owner.

| Script in `scripts/maintenance/` | Order of effects after approval | Engine requirement |
|---|---|---|
| [Invoke-VhdCompaction.ps1](../scripts/maintenance/Invoke-VhdCompaction.ps1) | Compact the selected image using an owned read-only attachment | Windows PowerShell 5.1 or PowerShell 7, required Storage APIs |
| [Invoke-UbuntuMaintenance.ps1](../scripts/maintenance/Invoke-UbuntuMaintenance.ps1) | Compact the selected image, then run Windows DISM component-store analysis and cleanup | Same; DISM available |
| [Invoke-SystemCleanup.ps1](../scripts/maintenance/Invoke-SystemCleanup.ps1) | Disable hibernation, set C: pagefile initial/maximum to 16384/32768MB via WMI, then compact the selected image | **Windows PowerShell 5.1**, WMI and Storage APIs |
| [Set-PagefileAndCompact.ps1](../scripts/maintenance/Set-PagefileAndCompact.ps1) | Replace only the C: `PagingFiles` registry entry with 16384/32768MB, then compact the selected image | Windows PowerShell 5.1 or PowerShell 7, required Storage APIs |
| [Disable-Hibernation.ps1](../scripts/maintenance/Disable-Hibernation.ps1) | Run checked `powercfg /h off` | Windows PowerShell 5.1 or PowerShell 7 |

The Ubuntu-named command runs DISM against the **Windows host**, not inside Ubuntu. Combined commands are not transactional: completed independent changes remain when a later step fails. Pagefile changes require a reboot; these scripts do not reboot the PC. Pagefile sizes in these entrypoints are fixed, not exposed as command-line parameters.

For a real compaction, use one absolute local `.vhd`/`.vhdx` path. The helper rejects unsafe paths, reparse-point traversal, missing Storage capabilities, and attached/busy images. It releases only its own successful attachment. English and Simplified Chinese DiskPart success acknowledgements are supported; other output is treated as failure. `-WhatIf` returns before full VHD preflight, so a successful preview does not prove the path or capabilities are valid.

```powershell
.\scripts\maintenance\Invoke-VhdCompaction.ps1 -VhdPath 'C:\path\reviewed-image.vhdx' -WhatIf
.\scripts\maintenance\Disable-Hibernation.ps1 -WhatIf
```

Logs default to unique files under `.local/logs`. An explicit `-LogPath` must name a new absolute local file; existing files and reparse-point parent paths are refused. Logs begin only after approval and relevant preflight. `-WhatIf` creates no logs. The [DiskPart templates](reference/compact_docker.txt) and [Ubuntu template](reference/compact_ubuntu.txt) are reference material; use the guarded wrappers instead of executing the templates.

## Diagnostics

| Script in `scripts/diagnostics/` | Parameters and behavior |
|---|---|
| [Scan-Lan.ps1](../scripts/diagnostics/Scan-Lan.ps1) | Required `-SubnetPrefix`: three IPv4 octets in an RFC1918 private range; `-FirstHost 1`, `-LastHost 254`, `-TimeoutMs 500`, `-Ports @(3389, 445)` by default |
| [Find-OpenHandles.ps1](../scripts/diagnostics/Find-OpenHandles.ps1) | Required literal `-Search`; optional `-ExecutablePath` defaults to `.local/vendor/sysinternals/handle64.exe`; actual execution requires `-AcceptEula`; optional `-LogPath` follows maintenance logging rules |

LAN scanning is an active network probe: explicitly choose a subnet you are authorized to scan. It has no `-WhatIf` or confirmation. Hosts that do not answer ICMP are omitted, even if they have open ports. TCP checks run only after a successful ping. Output objects contain `Address` and `OpenPorts`; a missing row does not prove a host is offline.

The Handle wrapper supports `-WhatIf` and confirmation. Real execution verifies a local Microsoft-signed executable, records output, and accepts the vendor EULA only with the explicit switch. It does not close handles or kill processes. Vendor executables are not bundled in Git or downloaded automatically.

```powershell
.\scripts\diagnostics\Find-OpenHandles.ps1 -Search 'C:\path\reviewed-image.vhdx' -WhatIf
```

## Local Defender setup

The root `configure-defender-startup.ps1` and `verify-defender-startup.ps1` are separate local scripts with no parameters, `-WhatIf`, or confirmation. They are not called by reports, maintenance, or the test runner. Use the [Defender startup guide](DEFENDER-STARTUP.md) for the exact task behavior, verification, local outputs, and removal procedure.
