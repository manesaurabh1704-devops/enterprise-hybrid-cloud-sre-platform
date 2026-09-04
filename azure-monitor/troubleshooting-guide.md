# Monitoring Troubleshooting Guide

Quick map from symptom -> which query to run -> what it tells you.

| Symptom | Query to run | What it confirms |
|---|---|---|
| Users report errors / alerts firing | `incident-queries.kql` #1, #2 | Whether it's a real 5xx spike and how bad (rate, not just count) |
| Pod keeps restarting | `incident-queries.kql` #3 | Confirms restart count and current phase across all pods |
| Need root cause for a crashing pod | `incident-queries.kql` #4 | Kubernetes Events (OOMKilled, ImagePullBackOff, probe failures, etc.) |
| Deployment seems stuck / rolled back unexpectedly | `incident-queries.kql` #5, #6 | Whether readiness probes were failing and whether a rollback pattern is visible in ReplicaSet pod counts |
| "Is the app actually up?" | `availability.kql` #1, #2, #3 | Pod-level, app-level, and IIS-level availability — these can disagree, and that disagreement is itself diagnostic (e.g. pod Running but health check failing = app-level issue, not infra) |
| Users say "it's slow" | `performance.kql` #1, #2 | P50/P95/P99 from IIS and from the app directly |
| Need to find which endpoint is slow | `performance.kql` #4 | Per-route latency breakdown |
| Latency is high — is it CPU/memory starved or logic-bound? | `performance.kql` #5 | Correlates latency window against pod CPU/memory usage |

## General diagnostic order

1. **Availability first** — is it actually down, or just slow/erroring for
   some requests? (`availability.kql`)
2. **Error rate** — if erroring, how much and since when? (`incident-queries.kql` #1-2)
3. **Root cause** — Kubernetes Events for infra-level causes, or app logs
   for logic-level causes (`incident-queries.kql` #4)
4. **Correlate with deploys** — did this start right after a deployment?
   Check `KubePodInventory` ReplicaSet transitions around that time.
5. **Latency, if relevant** — only after ruling out hard failures, since a
   5xx-heavy period will distort latency percentiles anyway.

## Known limitations of this monitoring setup

- `duration_ms` in app logs is wall-clock time inside Flask's
  before/after request hooks — it does not include network time to
  reach the pod, so it will read lower than what an external synthetic
  monitor (e.g. Azure Application Insights availability test) would show.
- IIS `W3CIISLog` queries assume the Data Collection Rule is actually
  routing IIS logs into Log Analytics — this depends on the Azure
  Monitor Agent being correctly configured on the Windows VM (see
  `infrastructure/azure/architecture.md`).
