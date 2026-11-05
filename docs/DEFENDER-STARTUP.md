# Local Defender startup configuration

[README](../README.md) · [Commands](COMMANDS.md) · [Troubleshooting](TROUBLESHOOTING.md)

This guide describes the two root scripts created for this PC's requested Defender configuration. They are local working-tree additions and may be absent from a clean clone. Disabling these protections increases exposure to malware. Reports, maintenance, development setup, and tests do not invoke these scripts or install this task.

## Behavior

[configure-defender-startup.ps1](../configure-defender-startup.ps1) registers **Disable Microsoft Defender at startup**, then starts it immediately. Run setup only when that machine change is intended, from an elevated Windows PowerShell session. The script does not elevate itself, expose `-WhatIf`, request its own confirmation, or provide a managed update/rollback path for an existing task. Inspect an existing task before considering another setup run.

| Setting | Configured value |
|---|---|
| Task path/name | `\` / `Disable Microsoft Defender at startup` |
| Account | `SYSTEM`, highest privileges |
| Trigger | Windows startup with a 30-second delay (`PT30S`) |
| Action | Windows PowerShell using an embedded Base64-encoded command |
| Defender preferences | `DisableRealtimeMonitoring`, `DisableBehaviorMonitoring`, `DisableIOAVProtection` set to `$true` |
| Failure check | Throw if real-time protection still reports enabled after applying preferences |
| Retry policy | Up to three restarts at one-minute intervals on failure |
| Other task settings | Start when available; allow battery operation; five-minute execution limit |

The action is stored inside the task and does not read a script from the checkout. Moving or deleting this project does not uninstall the task. It reapplies preferences after startup; it does not guarantee protection stays off continuously. It does not uninstall Defender, stop its service, change the firewall, or disable tamper protection. Microsoft describes the ordinary real-time protection toggle as temporary in its [Windows Security guidance](https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-security-center-antivirus).

Setup writes `defender-startup-result.json` beside the script. `Success: true` records task registration and the request to start it, **not** completed execution or a tested reboot. Setup is not transactional: a later failure can leave the registered task in place.

## Verify without changing protection settings

Use an elevated Windows PowerShell window, from the project root. These commands inspect the task and Defender status; the verification script writes a local JSON file:

```powershell
.\verify-defender-startup.ps1
Get-Content -LiteralPath .\defender-startup-verification.json -Raw
Get-ScheduledTask -TaskName 'Disable Microsoft Defender at startup' |
    Select-Object TaskName, State, @{Name = 'Enabled'; Expression = { $_.Settings.Enabled }}
Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected
```

[verify-defender-startup.ps1](../verify-defender-startup.ps1) records the account, enabled flag, trigger type/delay, last run time/result, and real-time state. Check all of these together:

- `Enabled` is true, `Account` is `SYSTEM`, `TriggerType` is `MSFT_TaskBootTrigger`, and `StartupDelay` is `PT30S`.
- `LastTaskResult` is zero and `LastRunTime` corresponds to the execution being checked.
- `RealTimeProtectionEnabled` is false after that run.

The script's JSON `Success` checks only a zero last-task result and current real-time state. It does not validate task enablement, every preference, or execution after the latest reboot. A `Success: false` JSON result can still accompany process exit code zero; read the file. Old JSON is a snapshot, not live status.

After a separately approved reboot, allow the startup delay and execution time, then repeat verification. Compare the task time with the current boot time:

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object LastBootUpTime
Get-ScheduledTaskInfo -TaskName 'Disable Microsoft Defender at startup' |
    Select-Object LastRunTime, LastTaskResult
```

The earlier setup test showed successful execution without rebooting. It did not establish behavior across a full reboot or future Windows updates.

## Troubleshoot

| Symptom | Check |
|---|---|
| Task invisible or access denied | Use an elevated Windows PowerShell session. An ordinary session may not enumerate this SYSTEM task. |
| Setup fails when the task already exists | Inspect the existing task rather than assuming setup is an idempotent update. |
| JSON says success but the task did not run this boot | Compare last-run and boot times, then inspect `Enabled` and the startup trigger. |
| Protection remains on or changes later | Inspect task result, current preferences, tamper-protection status, and applicable management policy. Task registration does not prove settings were accepted. |
| No new JSON output | Check elevation, script errors, and whether the checkout is writable; do not rely on an older result file. |

The root JSON files contain local execution details and currently are not ignored by `.gitignore`. Keep them out of published changes. The code gate can parse/lint the root scripts, but no dedicated test exercises this actual task or a real reboot.

## Remove the task and restore its three preferences

Run the following **only when intentionally undoing this configuration**, in elevated Windows PowerShell. Remove the task before restoring preferences so a later boot cannot reapply them:

```powershell
Stop-ScheduledTask -TaskName 'Disable Microsoft Defender at startup' -ErrorAction Stop
Unregister-ScheduledTask -TaskName 'Disable Microsoft Defender at startup' -Confirm -ErrorAction Stop
if (Get-ScheduledTask -TaskName 'Disable Microsoft Defender at startup' -ErrorAction SilentlyContinue) {
    throw 'The startup task still exists. Stop and inspect it before restoring preferences.'
}
Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false
Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected
```

Stop if task removal fails or is declined. If the task is already absent, inspect current settings before deciding which preferences to restore. Restoring these preferences does not undo unrelated firewall or registry policy changes, and another policy or security provider may still control the observed state. Check Windows Security and the applicable policy if protection remains disabled.

References: Microsoft documents [task removal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/unregister-scheduledtask) and [Defender preference controls](https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference).
