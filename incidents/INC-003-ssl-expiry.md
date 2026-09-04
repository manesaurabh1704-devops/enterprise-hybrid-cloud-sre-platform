# INC-003: SSL Certificate Expiry Warning

## Summary

The daily `ssl-audit.ps1` Scheduled Task flags a certificate bound to
the IIS HTTPS site approaching expiry.

## Simulating it

Bind a certificate with a short validity window (or, for a pure demo,
temporarily lower `-WarningDays`/`-CriticalDays` against a real cert
that's naturally further out than the default thresholds):

```powershell
.\ssl-audit.ps1 -SiteName "PlatformAPI" -WarningDays 400 -CriticalDays 365
```

## Detection

```json
{"level":"WARN","message":"Certificate: CN=app.company.com | Expires: 2026-10-01 | Remaining: 26 days | Status: WARNING"}
```

Event Viewer entry (source `PlatformAPIMonitor`, Event ID 9002,
type Warning or Error depending on threshold).

## Impact

None yet at WARNING — this is a proactive catch. If ignored past
expiry: browsers/clients reject the HTTPS connection outright (not a
500 error — a TLS handshake failure, which won't show up in
`W3CIISLog` at all since the request never completes at the
application layer). This is why certificate expiry needs its own
out-of-band monitoring rather than relying on HTTP-level metrics.

## Investigation

```powershell
Get-ChildItem Cert:\LocalMachine\My | Select-Object Subject, NotAfter, Thumbprint
Get-WebBinding -Name "PlatformAPI" -Protocol https | Select-Object -ExpandProperty certificateHash
```

Confirm which binding uses the expiring thumbprint, and who owns
renewal (internal CA team, or a public CA like DigiCert/Let's Encrypt).

## Root cause

Certificates are not on an automated renewal path — this is expected
for CA-issued certs on IIS-bound VMs (no ACME auto-renewal like a
Let's Encrypt setup would have).

## Fix

```powershell
# After the new cert is imported into Cert:\LocalMachine\My:
$binding = Get-WebBinding -Name "PlatformAPI" -Protocol "https"
$binding.AddSslCertificate("<NEW_THUMBPRINT>", "my")
```

Or re-run `iis-deployment.ps1` with the new `-CertThumbprint`.

## Verification

```powershell
.\ssl-audit.ps1 -SiteName "PlatformAPI"
# Status should now read OK with RemainingDays reflecting the new cert
```

## Prevention

- `ssl-audit.ps1` running daily is the prevention mechanism — the goal
  is to never let a cert reach CRITICAL (7 days) without a renewal
  already in progress.
- Longer term: move to a CA that supports ACME (Let's Encrypt via
  win-acme) so renewal is automatic and this incident class stops
  being a manual on-call concern entirely.
