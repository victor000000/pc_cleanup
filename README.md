# PC Cleanup

Version **0.0.3** — [original release design](docs/RELEASE-0.0.3.md) and [current documentation audit](docs/DOCUMENTATION-AUDIT-2026-11-07.md).

A Windows PowerShell toolkit for storage reports, USB recovery, and selected Windows/VHD maintenance. Start with a report, inspect the target, and preview maintenance before approving it. File sizes alone do not establish what can be deleted.

## Start here

Run examples in **Windows PowerShell 5.1 or PowerShell 7 on Windows**, from the project directory. Reports and tests do not require administrator rights. Storage and maintenance operations may require an elevated session; `Invoke-SystemCleanup.ps1` requires Windows PowerShell 5.1.

For a focused, read-only report:

```powershell
.\scripts\reports\Scan-TopLevel.ps1 -RootPath "$env:USERPROFILE\Downloads" -Top 15
```

This measures immediate subdirectories recursively and lists large files directly under the selected root. `-Top` limits the displayed rows, not the amount scanned. Warnings indicate partial results; sizes are logical file lengths, not reclaimable space.

For a structured review with partial-scan warnings included in the result:

```powershell
.\scripts\reports\Get-CleanupReview.ps1 -RootPath "$env:USERPROFILE\Downloads" -MinimumFileBytes 100MB -Top 20 -Format Json
```

The new command emits data only. Its inclusive size threshold and top-N list do
not establish that any file is disposable; check `ScanStatus`, warning counts,
and truncation flags. Omit `-Format Json` for an object suitable for pipelines.

Choose the guide for your task:

| Task | Guide |
|---|---|
| Select a command, check its parameters, or preview maintenance | [Command reference](docs/COMMANDS.md) |
| Resolve partial reports, device vetoes, or validation errors | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Understand limits before changing disks or system settings | [Safety contract](docs/SAFETY.md) |
| Inspect, verify, or undo the local Defender startup configuration | [Defender startup guide](docs/DEFENDER-STARTUP.md) |
| Install development tools and validate a change | [Contributing](CONTRIBUTING.md) |
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

The guarded storage and maintenance commands support `-WhatIf` and confirmation. A preview describes intent; it does not validate every prerequisite or prove a device will accept the operation. To carry out a reviewed operation, omit `-WhatIf` and inspect the confirmation. See the command reference for prerequisites, combined-operation effects, and logs.

The two local Defender scripts have a separate contract: they do **not** support `-WhatIf` or confirmation. Their [guide](docs/DEFENDER-STARTUP.md) documents this exception and task behavior and removal procedure.

## Development quick start

Runtime reports do not need Pester or PSScriptAnalyzer. For development, explicitly install the pinned, hash-verified packages into `.tools`, then validate:

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tools\Install-DevDependencies.ps1
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
