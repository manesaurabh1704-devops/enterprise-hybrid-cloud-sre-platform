# Incident Response Process

## Severity levels

| Severity | Definition | Example from this repo |
|---|---|---|
| SEV-1 | Full outage, all users affected | All pods CrashLoopBackOff, zero capacity |
| SEV-2 | Partial outage or major degradation | INC-004 (5xx spike on one endpoint) |
| SEV-3 | Degraded performance, no hard failure | INC-005 (high P95 latency) |
| SEV-4 | Proactive warning, no current impact | INC-003 (SSL cert expiring) |

## Response flow

```
Detect (alert/monitoring/report)
        |
Acknowledge (stop the alert noise, confirm someone's on it)
        |
Assess impact & severity
        |
Investigate (see relevant runbook: aks-troubleshooting.md /
             iis-troubleshooting.md / azure-troubleshooting.md)
        |
Mitigate (restore service — rollback, restart, scale — before
          full root-cause is required)
        |
Root cause
        |
Fix (permanent)
        |
Verify
        |
Document (incidents/INC-XXX-*.md, using the existing template)
        |
Prevention follow-up
```

## During an active incident

1. **Mitigate before you fully understand.** A rollback or restart that
   restores service is almost always the right first move, even before
   root cause is confirmed — see `deployment-rollback.md`'s
   rollback-vs-fix-forward table.
2. **One communication channel.** Avoid parallel investigation threads
   losing track of what's already been tried.
3. **Timestamps matter.** Note when each action was taken — this is
   what makes the post-incident writeup (and the KQL correlation
   queries) actually usable afterward.

## Writing up an incident

Use the existing files in `../incidents/` as the template: Summary,
Simulating it (or "How it happened" for a real incident), Detection,
Impact, Investigation, Root cause, Fix, Verification, Prevention. Every
incident gets a Prevention section even if the honest answer is "the
existing safeguard already handles this" — that's still worth stating
explicitly.

## On-call handoff checklist

- Any open/unresolved alerts?
- Any recent deployments in the last 24h (higher-risk window)?
- Any known degraded-but-not-paging conditions (e.g. a cert in WARNING
  state, not yet CRITICAL)?
- Link to any in-progress incident docs.
