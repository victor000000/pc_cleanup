# Troubleshooting

[README](../README.md) · [Commands](COMMANDS.md) · [Safety](SAFETY.md) · [Development](../CONTRIBUTING.md)

## Reports

| Symptom | Meaning and next step |
|---|---|
| `Directory scan incomplete` warning | A path was inaccessible, disappeared, or had excluded attributes. Treat the result as partial; inspect the named path rather than suppressing warnings. |
| Zero or unexpectedly small totals | Skipped entries can contribute no bytes; logical lengths also differ from allocated/compressed/sparse storage. A zero total does not prove a directory is empty. |
| Scan takes longer than expected | `-Top` caps output while traversal continues. From the checkout root, try `.\scripts\reports\Scan-TopLevel.ps1 -RootPath (Get-Item -LiteralPath .\docs).FullName`, then substitute the directory you intend to inspect. |
| A legacy report shows an unexpected root after `Set-Location` | Pass an absolute `-RootPath`, `-ProfilePath` or `-AppPath`. The structured report accepts a relative filesystem path. |
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

### Verify a drive letter

After `Set-UsbDriveLetter.ps1` returns, read back the partition before using the letter. Substitute the same USB UniqueId and partition number you approved. This check obtains the current disk number from a fresh identity match.

```powershell
$expectedId = 'COPY-EXACT-USB-UNIQUE-ID'
$partitionNumber = 1
$selectedDisks = @(Get-Disk -ErrorAction Stop | Where-Object { $_.UniqueId -eq $expectedId })
if ($selectedDisks.Count -ne 1) { throw 'Recheck the USB UniqueId in disk inventory.' }
Get-Partition -DiskNumber $selectedDisks[0].Number -PartitionNumber $partitionNumber -ErrorAction Stop |
    Select-Object DiskNumber, PartitionNumber, DriveLetter
```

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

### After a partial maintenance run

1. Read the first failure and the preceding completed step in the local log. The VHD wrappers write to `.local/logs` by default. Standalone `Disable-Hibernation.ps1` logs only with `-LogPath`. A failure during preflight can occur before log creation.
2. If attachment cleanup reported an error, inspect the exact image from the original operation. If it is attached, identify its current owner before deciding how to release it.

   ```powershell
   $imagePath = 'C:\path\reviewed-image.vhdx'
   Get-DiskImage -ImagePath $imagePath -ErrorAction Stop |
       Select-Object ImagePath, Attached, DevicePath
   ```

3. For `Invoke-SystemCleanup.ps1`, hibernation can already be disabled when a pagefile or VHD step fails. The WMI and registry pagefile helpers attempt to restore their own settings after failed writes or readback. Check the configured state, especially if rollback itself produced a warning.

   ```powershell
   Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object AutomaticManagedPagefile
   Get-CimInstance -ClassName Win32_PageFileSetting | Select-Object Name, InitialSize, MaximumSize
   Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles |
       Select-Object -ExpandProperty PagingFiles
   ```

4. For `Invoke-UbuntuMaintenance.ps1`, a DISM error can follow successful VHD compaction. Review the remaining step and its prerequisites before retrying. Keep raw logs, file paths, and disk identities local when sharing a diagnosis.

## Development validation

| Symptom | Meaning and next step |
|---|---|
| Pinned dependency missing | From the checkout root, run `.\tools\Install-DevDependencies.ps1` with HTTPS access to PowerShell Gallery and a writable `.tools` directory. Then rerun the failing engine. |
| Package stamp/hash/version mismatch or incomplete dependency directory | Inspect the lock, downloaded bytes, and named `.tools` directory. Remove only a verified disposable dependency installation before reinstalling; do not loosen the pin. |
| Wildcard/backtick path rejected | Move the checkout to a path without `[]*?` or backtick characters. This validation limitation does not prohibit brackets in ordinary report inputs. |
| Lint gate fails | Inspect the current `lint.json`; fix the enabled-rule finding. `-SkipLint` is local diagnosis and does not satisfy CI. |
| Empty, skipped, unrun, or failed test/container result | Inspect `tests.xml` and discovery errors. These conditions deliberately fail the gate even when some tests pass. |
| Coverage missing or below the configured minimum | Inspect the current `coverage.xml`, source discovery, and missing safety cases. Keep the threshold in `tools/Quality.psd1`. |
| Only old artifacts exist | Check the latest process exit code and the engine's output directory. On Actions, open the failing job's log if setup ended before it could upload test results. [CI artifacts](../CONTRIBUTING.md#repository-hygiene-and-ci) |

For startup-task permissions, stale verification JSON, or protection settings that change after boot, see the [Defender startup guide](DEFENDER-STARTUP.md).

For native exit-code fixture failures from WSL, use the release checkout's `Test.ps1` in a fresh Windows engine. Its process-local `PATHEXT` adjustment lets PowerShell recognize `.exe` files during validation. Keep the failing engine's error and exit code for diagnosis. [Test runner](../Test.ps1) · [Native fixtures](../tests/NativeBoundary.Tests.ps1)

## Structured review and WSL space

| Symptom | Meaning and next step |
|---|---|
| JSON parses but `ScanStatus` is `Partial` | Successful serialization does not establish complete enumeration. Inspect warning count and sample; `-WarningLimit 0` hides samples only. |
| `CandidatesTruncated` is true while status is `Complete` | More files matched than `Top`; this is selection truncation, independent of enumeration warnings. |
| Missing/file root returns empty candidates | Inspect status and warnings. An invalid root can return a Partial report rather than terminating. Non-filesystem providers and invalid parameter ranges throw. |
| JSON output unexpectedly contains private paths | Paths and warning text are part of the contract. Redact them before sharing; scanning does not upload anything. |
| Removing guest files did not free Windows space | Guest filesystem use, VHD file length, and Windows allocated space are different measures. This toolkit does not discover the owner, remove guest data, trim the guest, or guarantee compaction savings. |

For a review-only request, inventory metadata and stop at the candidate list. A build/cache directory name alone does not prove it is inactive, reproducible, backed up, or no longer needed. Provider snapshots, staging, databases, and recovery checkpoints require application-specific retention and writer review outside this toolkit.
