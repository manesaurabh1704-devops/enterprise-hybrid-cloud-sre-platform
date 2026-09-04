# IIS Troubleshooting Runbook

## Website returns 503 Service Unavailable

Almost always an App Pool problem, not a website problem.
```powershell
Get-WebAppPoolState -Name "PlatformAPIPool"
```
If not `Started`, see `../incidents/INC-002-iis-app-pool.md`.

## App Pool keeps stopping repeatedly

Check rapid-fail protection history:
```powershell
Get-EventLog -LogName System -Newest 50 | Where-Object { $_.Source -eq "WAS" }
```
If you see repeated "Application pool ... is being automatically
disabled due to a series of failures", the app is crashing faster than
it can be manually restarted — look at the application's own error
output/Event Viewer entries for the actual exception, not just the
IIS-level symptom.

## Website returns 404 for everything

```powershell
Get-Website -Name "PlatformAPI" | Select-Object PhysicalPath, State
Test-Path (Get-Website -Name "PlatformAPI").PhysicalPath
```
Confirm the physical path exists and actually contains the deployed
content — a failed/partial `iis-deployment.ps1` run is the usual cause.

## HTTPS binding not working / wrong certificate served

```powershell
Get-WebBinding -Name "PlatformAPI"
netsh http show sslcert
```
Compare the bound thumbprint against `Get-ChildItem Cert:\LocalMachine\My`.
A mismatch here (binding points to a thumbprint not in the store, or an
expired one) causes TLS handshake failures that won't appear in
`W3CIISLog` at all.

## SSL certificate expired or expiring

See `../incidents/INC-003-ssl-expiry.md`. Quick check:
```powershell
.\ssl-audit.ps1 -SiteName "PlatformAPI"
```

## Deployment/rollback

See `deployment-rollback.md`.

## Where to look for logs

- IIS access logs: `%SystemDrive%\inetpub\logs\LogFiles\W3SVC1\`
- Application Event Log: `Get-EventLog -LogName Application -Source "PlatformAPIMonitor"`
- Failed Request Tracing (if enabled): `%SystemDrive%\inetpub\logs\FailedReqLogFiles\`
