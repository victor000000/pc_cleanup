$ErrorActionPreference = 'Stop'
try {
    $taskName = 'Disable Microsoft Defender at startup'
    $task = Get-ScheduledTask -TaskName $taskName
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    $status = Get-MpComputerStatus
    [pscustomobject]@{
        Success = ($info.LastTaskResult -eq 0 -and -not $status.RealTimeProtectionEnabled)
        TaskName = $task.TaskName
        State = [string]$task.State
        Enabled = $task.Settings.Enabled
        Account = $task.Principal.UserId
        StartupDelay = $task.Triggers[0].Delay
        TriggerType = $task.Triggers[0].CimClass.CimClassName
        LastRunTime = $info.LastRunTime.ToString('o')
        LastTaskResult = $info.LastTaskResult
        RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'defender-startup-verification.json') -Encoding UTF8
} catch {
    @{ Success = $false; Error = $_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'defender-startup-verification.json') -Encoding UTF8
    exit 1
}
