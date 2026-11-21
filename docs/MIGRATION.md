# Layout migration — 2026-10-20

[README](../README.md) · [Current commands](COMMANDS.md) · [Architecture](ARCHITECTURE.md)

Use the mapping below to update commands and shortcuts from the original layout. A source checkout contains the supported scripts and reference templates. Any operator's `archive/` directory is local and excluded from Git.

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
- The VHD and Handle commands create a new log after approval. Standalone hibernation writes a log only when given `-LogPath`.
- Hibernation is guarded and checked rather than an immediate mutation.
- LAN diagnostics require an explicit private subnet target; there is no automatic two-subnet sweep.
- Handle requires explicit search and EULA acceptance. No vendor executable is downloaded or run automatically.
- Tests use the exact locked Pester version; they do not pick the newest global module or install missing dependencies.

## Local assets

- Historical results and copy logs belong under the ignored `archive/` directory.
- Installer downloads: `.local/downloads`.
- Original Sysinternals files and EULA: `.local/vendor/sysinternals`.
- Development dependencies and verified download staging: `.tools`.
- Test/lint/coverage outputs: `artifacts`.

Development setup creates the pinned test dependencies under `.tools` on a fresh checkout or CI runner. Operators supply their own optional vendor tools. Keep archives, captured results, and machine-specific settings local.

## Later local additions

The root Defender startup/verification scripts were added separately from this layout migration. They are tracked source, not legacy aliases or part of standard cleanup. Their JSON outputs remain local, ignored evidence. See the [Defender startup guide](DEFENDER-STARTUP.md) for task persistence, verification limits, and removal.

## Version 0.0.3 interface additions

Version 0.0.3 introduced `Project.psd1` and the explicit-root object/JSON report. Its threshold is inclusive and equal-size candidates sort by path. The legacy large-file report uses a strict threshold for ordinary files and retains earlier entries at an equal-size cutoff. Existing report names remain available. Read the field contract before migrating a consumer. [Structured report](COMMANDS.md#structured-cleanup-review)
