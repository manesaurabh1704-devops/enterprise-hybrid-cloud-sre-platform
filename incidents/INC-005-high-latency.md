# INC-005: High P95 Latency

## Summary

P95 response time on the platform exceeds the SLO threshold (500ms),
even though the service is otherwise "up" (no 5xx, pods Running/Ready).

## Simulating it

```bash
# Generate load against the latency-simulation endpoint
for i in $(seq 1 30); do curl -s "http://<service-ip>/api/slow?delay=2" > /dev/null & done
wait
```

## Detection

`azure-monitor/performance.kql` query #3 — alert-style query that flags
`P95 > 500ms` over a 5-minute bin.

```
P50 = 120ms
P95 = 850ms
P99 = 2.4s
```

## Impact

No errors, no failed health checks — this is the class of incident
that pure uptime monitoring completely misses. Users experience a slow
but "working" product. This is the difference between asking "is the
application up?" and "is the application performing within its
reliability target?" — the latter is the actual SRE question.

## Investigation

```bash
# Per-route breakdown — is it one endpoint or system-wide?
```
Run `performance.kql` query #4 (slowest endpoints by P95).

```bash
# Is it resource-starved or logic-bound?
```
Run `performance.kql` query #5 (CPU/memory correlation via
`InsightsMetrics`). If CPU/memory is near the `resources.limits` set in
`deployment.yaml` (250m CPU / 256Mi memory), the pod is likely
throttled — check with:

```bash
kubectl top pod -n platform-api
```

## Root cause

For this drill: `/api/slow` intentionally sleeping. In production,
common causes are: a slow downstream dependency, CPU throttling from
under-provisioned `resources.limits`, or lock contention under
concurrent load (relevant here since the demo app is single-threaded
in dev mode — the Dockerfile's gunicorn config with `--workers 2`
mitigates but doesn't eliminate this for a real workload).

## Fix

Immediate mitigation options, in order of speed:
1. **Scale out** — HPA should already be reacting if CPU-bound
   (`hpa.yaml` targets 70% CPU); confirm with `kubectl get hpa -n platform-api`.
2. **Scale up limits** — if consistently CPU-throttled at low replica
   count, raise `resources.limits.cpu` in `deployment.yaml`.
3. **Root-cause the dependency** — if a downstream call is the actual
   slow path, fixing that beats scaling the caller.

## Verification

Re-run `performance.kql` query #1/#3 after mitigation — P95 should
return under the 500ms SLO threshold within one or two 5-minute bins.

## Prevention

- HPA is already tuned to CPU/memory utilization, so transient load
  spikes should self-heal without manual scaling.
- The gap this incident exposes: there's currently no alert RULE wired
  up for the P95 query (see `docs/monitoring.md` — alerting is a
  documented next step, not yet implemented). Detection today is
  reactive (someone runs the query), not proactive (an alert fires).
