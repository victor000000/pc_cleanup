# PC Cleanup

A Windows PowerShell toolkit for **read-only storage reports and explicitly approved maintenance**. It separates reusable safety logic, operational commands, tests, and local history.

This is not an automatic “delete everything large” tool. Databases, backups, virtual disks, and personal files are never deemed disposable merely because of their size.

## Layout

```text
src/                  Reusable traversal, USB, recovery, and VHD helpers
scripts/
  reports/            Read-only storage reports
  storage/            Identity-checked USB eject and recovery
  maintenance/        Confirmed VHD and Windows maintenance
  diagnostics/        Explicitly targeted LAN and Handle diagnostics
  compat/             Legacy eject aliases, forwarding to one safe command
tests/                Unit, contract, safety, and fixture tests
tools/                Pinned dependency bootstrap and validation tooling
docs/                 Safety, architecture, migration, and reference templates
.github/workflows/    Windows PowerShell 5.1 / PowerShell 7 CI
archive/              Ignored local historical evidence and source snapshots
.local/               Ignored installers, vendor tools, and runtime logs
.tools/               Ignored project-local development dependencies
artifacts/            Ignored test, lint, environment, and coverage results
```

Root operational paths changed. See [the migration map](docs/MIGRATION.md) rather than using an old root-level command.

## Development quick start

Requires Windows and Windows PowerShell 5.1 or PowerShell 7. No administrator rights are needed for tests.

Install the exact development packages recorded in [Dependencies.psd1](tools/Dependencies.psd1). Downloads come from PowerShell Gallery and must match the pinned SHA-512 hashes before extraction. Nothing is installed globally.

```bash
powershell -NoProfile -NonInteractive -File ./tools/Install-DevDependencies.ps1
```

Run parsing, the configured correctness/security lint rules, and all unit/contract tests:

```bash
powershell -NoProfile -NonInteractive -File ./Test.ps1
```

```bash
pwsh -NoProfile -NonInteractive -File ./Test.ps1
```

Include helper coverage:

```bash
pwsh -NoProfile -NonInteractive -File ./Test.ps1 -Coverage
```

Results are written under `artifacts/ps-5` or `artifacts/ps-7`. Keep the development checkout path free of wildcard characters such as `[` and `]`: PowerShell's module loader can re-expand these while loading manifests, so validation refuses such dependency locations rather than risk importing a different directory. This restriction does not prohibit bracketed paths as ordinary report inputs.

The runner never downloads dependencies. Missing tools, lint diagnostics, failed discovery, zero passing tests, skipped tests, and unrun tests fail the gate. `-SkipLint` is for local diagnosis only; CI uses the complete gate.

Tests use disposable files and mocked maintenance, Storage, WMI, network, and registry boundaries. A small native-process contract suite launches only fixed, harmless `cmd.exe` exit/echo fixtures; it never runs maintenance executables. Pester's registry fixture is disabled. When `-Coverage` is enabled, the runner enforces **90% command coverage** over reusable source; CI always enables it. Both engine lanes exceeded 92% when establishing this baseline. Coverage does not prove hardware behavior.

## Read-only reporting

Report commands accept explicit filesystem targets and do not require elevation. Example:

```bash
powershell -NoProfile -File ./scripts/reports/Get-DiskUsage.ps1 -RootPath "C:\Users\Public"
```

Other reports are `Scan-TopLevel.ps1`, `Scan-UserProfile.ps1`, `Scan-LargeFiles.ps1`, and `Scan-AppData.ps1`. Use `Get-Help` or inspect their parameter blocks for scope options.

Scans skip links and cloud placeholders instead of following junctions or downloading content. Warnings mean a result is partial. Sizes are logical file lengths—not allocated blocks—and can differ from Windows' used-space figure. Report output is not authorization to delete anything.

## USB storage commands

First inspect the intended disk's stable identity:

```bash
powershell -NoProfile -Command 'Get-Disk | Format-List Number,FriendlyName,UniqueId,SerialNumber,BusType,IsBoot,IsSystem,IsOffline'
```

Preview a safe eject, replacing the placeholder with the exact intended identity:

```bash
powershell -NoProfile -File ./scripts/storage/Eject-UsbDisk.ps1 -UniqueId "COPY-EXACT-USB-UNIQUE-ID" -WhatIf
```

To perform an approved request, omit `-WhatIf` and review the confirmation. Only a validated disk PnP node is targeted. A veto is an error; it does not authorize force-dismount, hub removal, service changes, or offlining. Some USB drivers veto disk-node eject; use Windows' Safely Remove UI or shut down before unplugging rather than forcing it.

Recovery commands are `Set-UsbDiskOnline.ps1` and `Set-UsbDriveLetter.ps1`. They require `-ExpectedDiskUniqueId`; letter assignment also requires `-PartitionNumber`. An occupied letter is refused, not stolen. Review [safety requirements](docs/SAFETY.md) before use.

## Maintenance

Every compaction command requires an explicit `-VhdPath`. No Docker or WSL image is guessed from the machine profile. Stop the relevant owner yourself; commands never kill applications to obtain access.

```bash
powershell -NoProfile -File ./scripts/maintenance/Invoke-VhdCompaction.ps1 -VhdPath "C:\path\reviewed-image.vhdx" -WhatIf
```

Supported commands:

| Command | Approved scope |
|---|---|
| `Invoke-VhdCompaction.ps1` | One explicitly selected VHD/VHDX |
| `Invoke-UbuntuMaintenance.ps1` | Selected image plus DISM component-store analysis/cleanup |
| `Invoke-SystemCleanup.ps1` | Hibernation, C: pagefile, and selected VHD; Windows PowerShell 5.1 only |
| `Set-PagefileAndCompact.ps1` | C: pagefile registry entry plus selected VHD |
| `Disable-Hibernation.ps1` | Hibernation only |

Maintenance commands require confirmation and may require elevation. `-WhatIf` must not create logs or mutate machine state. Default runtime logs use unique files under `.local/logs`. An explicit `-LogPath` must also name a **new file**: existing destinations are refused, never overwritten or appended to. A successful log acquisition keeps its stream open for the operation, including failure reporting. Successful independent steps are not rolled back if a later step fails; combined maintenance is **not transactional**. Pagefile changes require reboot.

The DiskPart text files under `docs/reference` are deliberately non-runnable templates. Use the guarded wrappers, not `diskpart /s` on those files.

## Diagnostics

`Scan-Lan.ps1` requires an explicit private subnet target and must only be used on authorized networks. It is not part of a normal disk scan.

`Find-OpenHandles.ps1` requires an explicit search and approval to accept the vendor EULA. Vendor executables are not bundled in Git or executed by CI. Existing local Sysinternals files, with their EULA, were preserved under `.local/vendor`.

## CI and limitations

[Windows validation](.github/workflows/ci.yml) runs the same validation command in Windows PowerShell 5.1 and PowerShell 7, with pinned dependencies and immutable action revisions. It uses read-only repository permissions and uploads results even after a failed test gate. There are no real maintenance or remote-control steps.

The workflow can run on GitHub after this repository is published; creating the workflow is not evidence of a hosted run. No remote is created or pushed automatically.

See [CONTRIBUTING.md](CONTRIBUTING.md), [architecture](docs/ARCHITECTURE.md), [migration](docs/MIGRATION.md), and [safety](docs/SAFETY.md).
