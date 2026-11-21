# Local Defender startup configuration

[README](../README.md) · [Commands](COMMANDS.md) · [Troubleshooting](TROUBLESHOOTING.md)

The two scripts in the repository root describe an optional, machine-specific Defender configuration. A source checkout includes the scripts. Inspect Task Scheduler and Windows Security to determine the machine's actual state. Generated JSON contains local diagnostics. Disabling these protections increases exposure to malware.

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

Run these checks from the project root in an elevated Windows PowerShell session. The verification script writes a local JSON file. The other commands read the task and current protection status.

```powershell
.\verify-defender-startup.ps1
Get-Content -LiteralPath .\defender-startup-verification.json -Raw
Get-ScheduledTask -TaskPath '\' -TaskName 'Disable Microsoft Defender at startup' |
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
Get-ScheduledTaskInfo -TaskPath '\' -TaskName 'Disable Microsoft Defender at startup' |
    Select-Object LastRunTime, LastTaskResult
```

## Troubleshoot

| Symptom | Check |
|---|---|
| Task invisible or access denied | Use an elevated Windows PowerShell session. An ordinary session may not enumerate this SYSTEM task. |
| Setup fails when the task already exists | Inspect the existing task rather than assuming setup is an idempotent update. |
| JSON says success but the task did not run this boot | Compare last-run and boot times, then inspect `Enabled` and the startup trigger. |
| Protection remains on or changes later | Inspect task result, current preferences, tamper-protection status, and applicable management policy. Task registration does not prove settings were accepted. |
| No new JSON output | Check elevation, script errors, and whether the checkout is writable; do not rely on an older result file. |

The root JSON files contain local execution details and are explicitly ignored by `.gitignore`. Keep them out of published changes. The code gate can parse/lint the root scripts, but no dedicated test exercises this actual task or a real reboot.

## Remove the task and restore its three preferences

Use elevated Windows PowerShell when you intend to remove this task and enable the three protections. Setup does not save their previous values. Check the intended settings with the machine's administrator if another policy manages Defender. This block selects the task by its root folder and exact name, then verifies removal before changing preferences.

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $taskName = 'Disable Microsoft Defender at startup'
    $matchesTask = { $_.TaskPath -eq '\' -and $_.TaskName -eq $taskName }
    $task = Get-ScheduledTask | Where-Object $matchesTask
    if ($task) {
        if ($task.State -eq 'Running') { Stop-ScheduledTask -TaskPath '\' -TaskName $taskName }
        Unregister-ScheduledTask -TaskPath '\' -TaskName $taskName -Confirm
    }
    if (Get-ScheduledTask | Where-Object $matchesTask) {
        throw 'The startup task still exists. Inspect it before continuing.'
    }
    Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false
    Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, IsTamperProtected
}
```

If removal is declined or a scheduler query fails, the block stops before the preference update. Check Windows Security and the applicable management policy if protection remains disabled after restoration.

References: Microsoft documents [task removal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/unregister-scheduledtask) and [Defender preference controls](https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference).
