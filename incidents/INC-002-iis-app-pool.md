# INC-002: IIS App Pool Stopped

## Summary

The `PlatformAPIPool` App Pool stopped (crashed past IIS's rapid-fail
protection threshold, or was manually/accidentally stopped), taking the
website offline.

## Simulating it

```powershell
Stop-WebAppPool -Name "PlatformAPIPool"
```

## Detection

`iis-health-monitor.ps1`, running as a Scheduled Task every 2 minutes,
detects this on its next run:

```json
{"level":"ERROR","message":"App Pool 'PlatformAPIPool' is NOT running (state: Stopped). Beginning remediation."}
```

An Error-level Event Viewer entry is also written (source
`PlatformAPIMonitor`, Event ID 9001) — visible in `Get-EventLog` or
forwarded to Azure Monitor if the Windows VM has the Azure Monitor
Agent configured for Application log collection.

## Impact

Website returns connection-refused / 503 for all requests until the
pool is restarted. This is a hard outage on the Windows/IIS side (no
redundancy assumed for this single-VM demo — a real production setup
would have this VM behind a load balancer with a second instance).

## Investigation

```powershell
Get-WebAppPoolState -Name "PlatformAPIPool"
Get-EventLog -LogName Application -Source "PlatformAPIMonitor" -Newest 10
Get-EventLog -LogName System -Newest 20 | Where-Object { $_.Source -like "*WAS*" }
```

Check *why* it stopped — most commonly IIS's rapid-fail protection
(5 crashes in 5 minutes, per the `iis-deployment.ps1` config) kicked in
and auto-stopped the pool to prevent a crash loop from consuming
resources.

## Root cause

For this drill: manually stopped. In production, typically an
unhandled application exception crossing the rapid-fail threshold, or
a bad deployment.

## Fix

`iis-health-monitor.ps1` handles this automatically — no manual action
needed if the Scheduled Task is running. Manual fix if needed:

```powershell
Start-WebAppPool -Name "PlatformAPIPool"
Invoke-WebRequest -Uri "http://localhost/health" -UseBasicParsing
```

## Verification

```powershell
Get-WebAppPoolState -Name "PlatformAPIPool"   # should read "Started"
(Invoke-WebRequest -Uri "http://localhost/health" -UseBasicParsing).StatusCode   # should be 200
```

## Prevention

- The health monitor script already auto-remediates within ~2 minutes
  of the next scheduled run — the real prevention lever is reducing
  detection time (run every 1 minute instead of 2 for a tighter SLA)
  and alerting on the Event Viewer entry immediately via Azure Monitor
  Agent forwarding, rather than waiting to notice in a dashboard.
- If rapid-fail protection is triggering repeatedly, that's a signal
  the underlying app bug needs fixing — auto-restart treats the
  symptom, not the cause. Track restart frequency over time; a rising
  trend is itself an incident.
