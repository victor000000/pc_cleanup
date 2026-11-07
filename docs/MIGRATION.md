# Layout migration — 2026-10-20

[README](../README.md) · [Current commands](COMMANDS.md) · [Architecture](ARCHITECTURE.md)

Original text/source files were copied into `archive/2026-10-20/source-before-restructure` with a `.txt` suffix and a SHA-256 manifest before moving or modifying them. Snapshots are non-executable references and ignored by Git. Historical results and binaries were moved, not deleted.

## Command map

| Previous root path | Supported location |
|---|---|
| `scan_top.ps1` | `scripts/reports/Scan-TopLevel.ps1` |
| `scan_users.ps1` | `scripts/reports/Scan-UserProfile.ps1` |
| `scan_big.ps1` | `scripts/reports/Scan-LargeFiles.ps1` |
| `scan_details.ps1` | `scripts/reports/Scan-AppData.ps1` |
| `rescan.ps1` | `scripts/reports/Get-DiskUsage.ps1` |
| `scan_lan.ps1` | `scripts/diagnostics/Scan-Lan.ps1` — explicit target required |
| `online_f.ps1` | `scripts/storage/Set-UsbDiskOnline.ps1` |
| `fix_f_letter.ps1` | `scripts/storage/Set-UsbDriveLetter.ps1` |
| Seven `eject_*`, `admin_eject*`, and `chkdsk_eject_f.ps1` aliases | `scripts/compat/` forwards to `scripts/storage/Eject-UsbDisk.ps1` |
| `admin_compact.ps1` | `scripts/maintenance/Invoke-VhdCompaction.ps1` |
| `admin_compact_ubuntu_dism.ps1` | `scripts/maintenance/Invoke-UbuntuMaintenance.ps1` |
| `admin_cleanup.ps1` | `scripts/maintenance/Invoke-SystemCleanup.ps1` |
| `admin_cleanup2.ps1` | `scripts/maintenance/Set-PagefileAndCompact.ps1` |
| `disable_hibernate.ps1` | `scripts/maintenance/Disable-Hibernation.ps1` |
| `admin_handle.ps1` | `scripts/diagnostics/Find-OpenHandles.ps1` |
| `lib/*.ps1` | `src/*.ps1` |
| `compact_*.txt` | `docs/reference/compact_*.txt` — not runnable directly |
| `Test.ps1` | Still at root; now uses exact local dependencies and complete validation |

Preserving alias names under `scripts/compat` does **not** preserve old root invocation paths. Update shortcuts, saved commands, or external automation accordingly. Imports are script-relative and work independently of the current directory.

## Intentional interface changes

- Reports accept profile/root/app overrides instead of assuming a particular user's paths, terminal hash, or WSL distribution ID. If omitted, root/profile targets come from the current Windows environment; see the [current defaults and scan scope](COMMANDS.md#reports).
- All compaction entrypoints require `-VhdPath`; no machine-specific default image is selected.
- Default logs are unique `.local/logs` files created only after approval, not overwrites of historical evidence.
- Hibernation is guarded and checked rather than an immediate mutation.
- LAN diagnostics require an explicit private subnet target; there is no automatic two-subnet sweep.
- Handle requires explicit search and EULA acceptance. No vendor executable is downloaded or run automatically.
- Tests use the exact locked Pester version; they do not pick the newest global module or install missing dependencies.

## Local assets

- Historical text results and robocopy logs: `archive/2026-10-18/results`.
- Installer downloads: `.local/downloads`.
- Original Sysinternals files and EULA: `.local/vendor/sysinternals`.
- Development dependencies and verified download staging: `.tools`.
- Test/lint/coverage outputs: `artifacts`.

These ignored assets are intentionally absent from a clean clone and from CI. Tests must not depend on them. No personal course files, market data, databases, backups, or external disks were cleaned during this restructuring.

## Later local additions

The root Defender startup/verification scripts were added separately from this layout migration. They are tracked source, not legacy aliases or part of standard cleanup. Their JSON outputs remain local, ignored evidence. See the [Defender startup guide](DEFENDER-STARTUP.md) for task persistence, verification limits, and removal.

## Version 0.0.3 interface additions

`Project.psd1` now declares version 0.0.3. Existing report names remain supported. `Get-CleanupReview.ps1` adds an explicit-root object/JSON interface; it is not a replacement with identical output. Its threshold is inclusive and ties sort by path, while `Scan-LargeFiles` preserves strict ordinary-file thresholds and encounter-order ties. See the [structured contract](COMMANDS.md#structured-cleanup-review-003) before migrating consumers. There is no persistent database or configuration schema to migrate. Ignored local archives are historical assets, not distributed backups.
