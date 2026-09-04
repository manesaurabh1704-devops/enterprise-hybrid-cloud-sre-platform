# Monitoring

## Log flow

```
Flask app (structured JSON to stdout)
        |
   Container stdout
        |
   AKS (Container Insights agent)
        |
        +----------------------> ContainerLogV2 (application + system logs)
        +----------------------> KubePodInventory (pod status, restarts)
        +----------------------> KubeEvents (scheduling/probe/crash events)
        +----------------------> InsightsMetrics (CPU/memory)

IIS (W3C extended log format)
        |
   Azure Monitor Agent + Data Collection Rule
        |
        +----------------------> W3CIISLog

All of the above land in one Log Analytics Workspace, so KQL can join
across AKS and IIS in a single query where needed.
```

## What's covered

- `incident-queries.kql` — detection queries mapped to the simulated
  incidents in `../incidents/`
- `availability.kql` — pod-level, app-level, and IIS-level uptime
- `performance.kql` — P50/P95/P99 latency, slowest endpoints, resource
  correlation

See `troubleshooting-guide.md` for which query to reach for given a
symptom.

## Alerting (not yet wired up)

These KQL queries are written to be directly usable as Azure Monitor
**scheduled query alert rules** (each has a clear threshold condition),
but wiring them into actual alert rules + action groups (email/Teams/
PagerDuty) is a planned next step, not yet implemented in this repo.
