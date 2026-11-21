# PC Cleanup

Version **0.0.4**. [Release notes](docs/RELEASE-0.0.4.md) · [Changelog](CHANGELOG.md)

A Windows PowerShell toolkit for storage reports, USB recovery, and selected Windows/VHD maintenance. Start with a report, inspect the target, and preview maintenance before approving it. File sizes alone do not establish what can be deleted.

## Start here

Clone the project or extract its source archive. Keep `scripts` and `src` together under the directory containing `Project.psd1`. [Source repository](https://github.com/victor000000/pc_cleanup)

Run the examples from that directory in **Windows PowerShell 5.1 or PowerShell 7 on Windows**. Reports work with an ordinary user account. PowerShell 7 is a separate installation and supplies `pwsh.exe`.

Try the formatted report on the checkout's own documentation. To inspect another directory, substitute its absolute filesystem path.

```powershell
$reportRoot = (Get-Item -LiteralPath .\docs).FullName
.\scripts\reports\Scan-TopLevel.ps1 -RootPath $reportRoot -Top 15
```

This measures immediate subdirectories recursively and lists large files directly under the selected root. `-Top` limits the displayed rows. The report still scans the selected tree. Warnings indicate partial results. Sizes measure logical file lengths.

To inspect a machine-readable result, include files of every size from the same directory.

```powershell
$reportRoot = (Get-Item -LiteralPath .\docs).FullName
.\scripts\reports\Get-CleanupReview.ps1 -RootPath $reportRoot -MinimumFileBytes 0 -Top 5 -Format Json
```

Read `ScanStatus` and `WarningCount` to see whether any paths were skipped. `CandidatesTruncated` means more files met the inclusive threshold than fit in the list. Omit `-Format Json` to receive one PowerShell object with a `Candidates` array.

Choose the guide for your task.

| Task | Guide |
|---|---|
| Select a command, check its parameters, or preview maintenance | [Command reference](docs/COMMANDS.md) |
| Resolve partial reports, device vetoes, or validation errors | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Understand limits before changing disks or system settings | [Safety contract](docs/SAFETY.md) |
| Inspect, verify, or undo the local Defender startup configuration | [Defender startup guide](docs/DEFENDER-STARTUP.md) |
| Install development tools and validate a change | [Contributing](CONTRIBUTING.md) |
| Publish a source release or return to a known-good revision | [Release procedure](CONTRIBUTING.md#release-a-source-version) |
| Change reusable helpers or test boundaries | [Architecture](docs/ARCHITECTURE.md) |
| Find an older script name | [Migration map](docs/MIGRATION.md) |

## Configuration and supported environment

There is no central runtime configuration file, database, service, or credential store. Each entrypoint takes explicit PowerShell parameters; omitted profile/root values use the current Windows environment. `Project.psd1` declares the tool version, not runtime settings. Development pins and quality policy live in `tools/Dependencies.psd1` and `tools/Quality.psd1`. Runtime operation is supported on Windows; running Bash inside WSL does not make Windows Storage/WMI APIs available. This project does not package a Linux filesystem cleanup tool.

## Preview maintenance

Copy the exact intended USB identity from inventory before selecting an eject target:

```powershell
Get-Disk | Format-List Number, FriendlyName, UniqueId, SerialNumber, BusType, IsBoot, IsSystem, IsOffline
.\scripts\storage\Eject-UsbDisk.ps1 -UniqueId 'COPY-EXACT-USB-UNIQUE-ID' -WhatIf
```

For VHD compaction, select one image explicitly and stop its owner yourself before a real run:

```powershell
.\scripts\maintenance\Invoke-VhdCompaction.ps1 -VhdPath 'C:\path\reviewed-image.vhdx' -WhatIf
```

The guarded commands support `-WhatIf` and confirmation. A preview describes the requested change. Real storage and maintenance operations can require elevation, and `Invoke-SystemCleanup.ps1` requires Windows PowerShell 5.1. Review the command's prerequisites, order of effects, and recovery instructions before a real run. [Command reference](docs/COMMANDS.md#maintenance) · [Recovery](docs/TROUBLESHOOTING.md#maintenance)

The two root Defender scripts can change settings or write local results without a preview or confirmation. See the guide for task behavior, verification, and removal. [Defender startup guide](docs/DEFENDER-STARTUP.md)

## Development quick start

For development, the initial setup needs HTTPS access to PowerShell Gallery and write access to the checkout. It installs the pinned, hash-verified packages into `.tools`. Subsequent test runs use this local cache.

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tools\Install-DevDependencies.ps1
if ($LASTEXITCODE -ne 0) { throw 'Development dependency setup failed.' }
powershell.exe -NoProfile -NonInteractive -File .\Test.ps1 -Coverage
```

For the PowerShell 7 lane:

```powershell
pwsh.exe -NoProfile -NonInteractive -File .\Test.ps1 -Coverage
```

The runner never downloads dependencies. It fails on configured lint diagnostics, failed or empty tests, skipped/unrun tests, and coverage below the threshold in [Quality.psd1](tools/Quality.psd1), currently 90%. Results go to `artifacts/ps-5` or `artifacts/ps-7` by default. [Contributing](CONTRIBUTING.md) explains the checks, file names, and limitations.

## Project layout

| Path | Purpose |
|---|---|
| `src/` | Reusable traversal, USB, recovery, VHD, and logging helpers |
| `scripts/reports/` | Read-only storage reports |
| `scripts/storage/` | Identity-checked USB eject and recovery |
| `scripts/maintenance/` | Confirmed VHD and Windows maintenance |
| `scripts/diagnostics/` | Explicit LAN and signed Handle diagnostics |
| `scripts/compat/` | Legacy eject names forwarding to the guarded command |
| `tests/`, `tools/` | Fixtures, pinned dependencies, and validation tooling |
| `docs/` | Operational guides, design, migration, and reference templates |
| `.github/workflows/` | Windows PowerShell 5.1 and PowerShell 7 CI configuration |
| `archive/`, `.local/`, `.tools/`, `artifacts/` | Ignored local history, vendor files/logs, dependencies, and results |

The root Defender scripts are tracked source and are present in a clean clone. Their generated JSON outputs are ignored. The task embeds its action, so removing the checkout does not remove the installed task. Machine-specific results should not be published.
