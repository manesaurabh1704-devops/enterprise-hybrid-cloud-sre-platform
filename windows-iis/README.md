# Windows Server + IIS Operations

Scripts here automate the IIS-side operational responsibilities from
the JD: website/app pool management, SSL binding, deployment/rollback,
and health monitoring.

## Scripts

| Script | Purpose | Run as |
|---|---|---|
| `iis-deployment.ps1` | Creates/updates the App Pool + Website, deploys new content, binds HTTPS | Manual or called from a deployment pipeline |
| `iis-health-monitor.ps1` | Detects a stopped App Pool, auto-restarts, verifies via health check, logs to Event Viewer | Scheduled Task, every 1-2 min |
| `ssl-audit.ps1` | Checks certificate expiry against WARNING/CRITICAL thresholds, logs to Event Viewer | Scheduled Task, daily |

## Prerequisites

- Windows Server with IIS + `WebAdministration` PowerShell module
  (installed with the Web-Server role).
- Run as Administrator (App Pool / cert store operations require it).
- **Not yet tested against a live Windows Server/IIS instance** — validate
  in a lab environment before relying on these for a real deployment or
  demo.

## Setting up the Scheduled Tasks

```powershell
# Health monitor - every 2 minutes
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -File C:\Scripts\iis-health-monitor.ps1 -AppPoolName PlatformAPIPool -SiteName PlatformAPI"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration ([TimeSpan]::MaxValue)
Register-ScheduledTask -TaskName "PlatformAPI-HealthMonitor" -Action $action -Trigger $trigger -RunLevel Highest

# SSL audit - daily at 6 AM
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -File C:\Scripts\ssl-audit.ps1 -SiteName PlatformAPI"
$trigger = New-ScheduledTaskTrigger -Daily -At 6am
Register-ScheduledTask -TaskName "PlatformAPI-SSLAudit" -Action $action -Trigger $trigger -RunLevel Highest
```

## Rollback

Because `iis-deployment.ps1` copies content into `PhysicalPath`, rollback
is: re-run the script with `-SourcePath` pointed at the previous
release's artifact folder (keep at least the last 2-3 releases on disk
for this reason).
