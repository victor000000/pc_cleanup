# Troubleshooting

[README](../README.md) · [Commands](COMMANDS.md) · [Safety](SAFETY.md) · [Development](../CONTRIBUTING.md)

## Reports

| Symptom | Meaning and next step |
|---|---|
| `Directory scan incomplete` warning | A path was inaccessible, disappeared, or had excluded attributes. Treat the result as partial; inspect the named path rather than suppressing warnings. |
| Zero or unexpectedly small totals | Skipped entries can contribute no bytes; logical lengths also differ from allocated/compressed/sparse storage. A zero total does not prove a directory is empty. |
| Scan takes longer than expected | `-Top` limits selected/displayed rows, not traversal. Use `Scan-TopLevel -RootPath <focused-directory>` to narrow the scan; combined reports revisit overlapping trees. |
| Changing `Get-DiskUsage -RootPath` still scans the user profile | Its root and profile targets are independent. Supply both parameters or use a focused report. |
| Cannot discover current root/profile | Supply the appropriate `-RootPath` or `-ProfilePath` explicitly; do not infer a different user's location. |

Reports do not identify files as safe to delete. Review ownership, backups, and application use before any separate cleanup.

## USB storage

| Symptom | Meaning and next step |
|---|---|
| Missing or ambiguous identity | Run fresh `Get-Disk` inventory and copy the intended UniqueId/serial. Never substitute the current drive letter as the identity. |
| Disk number changed during confirmation | The mapping changed; the command cancelled. Reinspect the hardware and select the intended disk again. |
| Drive letter occupied | Inspect `Get-Volume` and `Get-Partition`. Choose an unused letter; do not remove another mount to force assignment. |
| Disk offline during letter assignment | Review and run the separate online command for the same stable identity, then inspect partitions again. |
| Eject veto or unsafe PnP mapping | Close the owner's files normally and use Windows Safely Remove Hardware. If safe eject remains unavailable, shut down before unplugging. Do not force-dismount or target an enclosing hub. |
| Access denied | Inspect inventory first. If the operation is still intended, run the reviewed storage command from an elevated Windows session. |

## Maintenance

| Symptom | Meaning and next step |
|---|---|
| Image already attached or cannot be opened exclusively | Stop the owning WSL/Docker/VM application yourself and confirm the exact image is released. The wrapper will not detach another owner's image. |
| Required Storage API unavailable | Use a Windows environment that provides the required cmdlets and parameters. There is no DiskPart attachment fallback. |
| WMI engine rejected | Run `Invoke-SystemCleanup.ps1` in Windows PowerShell 5.1; PowerShell 7 is unsupported for its real WMI path. |
| Log already exists or path rejected | Select a new absolute local file or use the unique default. Do not reuse an operational input, existing log, or linked path. |
| DiskPart exits successfully but compaction is reported as failure | The wrapper also requires a recognized success acknowledgement. Inspect the complete output; progress or exit code zero alone is insufficient. |
| A combined command fails after an earlier step | Inspect the log and current hibernation/pagefile/image state. Earlier independent changes remain; do not blindly rerun the whole command. |
| Cleanup warning after compaction | Inspect the exact image's attachment state and temporary-file diagnostic. `finally` attempts cleanup but cannot guarantee it after OS/process failure. |

Find default runtime logs under `.local/logs`. A preview or early preflight failure may have no log. Preserve the original error and native output when reporting a failure; remove private paths and device identities before sharing.

## Development validation

| Symptom | Meaning and next step |
|---|---|
| Pinned dependency missing | Run `tools/Install-DevDependencies.ps1` explicitly. The test runner will not download it. |
| Package stamp/hash/version mismatch or incomplete dependency directory | Inspect the lock, downloaded bytes, and named `.tools` directory. Remove only a verified disposable dependency installation before reinstalling; do not loosen the pin. |
| Wildcard/backtick path rejected | Move the checkout to a path without `[]*?` or backtick characters. This validation limitation does not prohibit brackets in ordinary report inputs. |
| Lint gate fails | Inspect the current `lint.json`; fix the enabled-rule finding. `-SkipLint` is local diagnosis and does not satisfy CI. |
| Empty, skipped, unrun, or failed test/container result | Inspect `tests.xml` and discovery errors. These conditions deliberately fail the gate even when some tests pass. |
| Coverage missing or below the configured minimum | Inspect the current `coverage.xml`, source discovery, and missing safety cases. Keep the threshold in `tools/Quality.psd1`. |
| Only old artifacts exist | Check timestamps, output directory, and the latest process exit code. Early failures may not write all files. |

For startup-task permissions, stale verification JSON, or protection settings that change after boot, see the [Defender startup guide](DEFENDER-STARTUP.md).

## Observed validation result — 2026-10-21

**Superseded diagnosis (2026-11-07):** the later runner fix at `2e963c2` temporarily adds `.EXE` to an inherited `PATHEXT` that can contain only `.CPL` when launched from WSL. It restores the process value afterward. The 0.0.3 clean-clone suites subsequently passed 466/466 in both engines; see the [documentation audit](DOCUMENTATION-AUDIT-2026-11-07.md#release-status-correction). The dated observations below are retained as history.

The documentation review ran the complete `Test.ps1 -Coverage` gate against unchanged code in both Windows engines. Both runs failed three tests in [NativeBoundary.Tests.ps1](../tests/NativeBoundary.Tests.ps1): accepting zero status, propagating status 7, and capturing stdout with a fresh success status. The native wrapper observed a null exit status in these cases. The tests substitute harmless `cmd.exe` fixtures; no real DISM operation was run.

| Engine | Passed / failed | Lint findings | Command coverage |
|---|---|---|---|
| Windows PowerShell 5.1.26100.9711 | 438 / 3 | 0 | 92.62% |
| PowerShell 7.6.7 | 438 / 3 | 0 | 92.27% |

This is an observed failure, not a diagnosed root cause. Review [Invoke-MaintenanceNativeCommand](../src/VhdMaintenance.ps1) and the native-process fixture before relying on real maintenance behavior. Passing lint and coverage do not override a failing test gate. Local logs and per-engine XML results are under `artifacts/docs-review`; they are ignored and absent from a clean clone. Separate documentation checks resolved local links and parsed all 16 PowerShell examples in both engines; no operational examples were executed.

## Structured review and WSL space

| Symptom | Meaning and next step |
|---|---|
| JSON parses but `ScanStatus` is `Partial` | Successful serialization does not establish complete enumeration. Inspect warning count and sample; `-WarningLimit 0` hides samples only. |
| `CandidatesTruncated` is true while status is `Complete` | More files matched than `Top`; this is selection truncation, independent of enumeration warnings. |
| Missing/file root returns empty candidates | Inspect status and warnings. An invalid root can return a Partial report rather than terminating. Non-filesystem providers and invalid parameter ranges throw. |
| JSON output unexpectedly contains private paths | Paths and warning text are part of the contract. Redact them before sharing; scanning does not upload anything. |
| Removing guest files did not free Windows space | Guest filesystem use, VHD file length, and Windows allocated space are different measures. This toolkit does not discover the owner, remove guest data, trim the guest, or guarantee compaction savings. |

For a review-only request, inventory metadata and stop at the candidate list. A build/cache directory name alone does not prove it is inactive, reproducible, backed up, or no longer needed. Provider snapshots, staging, databases, and recovery checkpoints require application-specific retention and writer review outside this toolkit.
