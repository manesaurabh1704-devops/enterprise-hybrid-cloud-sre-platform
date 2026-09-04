# INC-004: HTTP 5xx Spike

## Summary

Error rate on `/api/failure` (or any route, if `FAILURE_MODE=true` is
set globally) spikes above the alerting threshold.

## Simulating it

```bash
kubectl patch configmap platform-api-config -n platform-api \
  --type merge -p '{"data":{"FAILURE_MODE":"true"}}'
kubectl rollout restart deployment/platform-api -n platform-api

# Generate traffic to make the spike visible in logs
for i in $(seq 1 50); do curl -s http://<service-ip>/api/failure > /dev/null; done
```

## Detection

`azure-monitor/incident-queries.kql` query #1/#2 — error count and
error rate % over 5-minute bins. In a wired-up alert rule, this would
fire a scheduled query alert once `ErrorCount > 5` in a window.

## Impact

Every request to the affected endpoint returns HTTP 500. Depending on
scope (one endpoint vs. `FAILURE_MODE` globally), this ranges from a
partial degradation to a full outage of API functionality (health/ready
endpoints are unaffected by `FAILURE_MODE` by design, so the pod stays
"healthy" from Kubernetes' point of view even while serving errors —
this is exactly why app-level error-rate monitoring matters separately
from pod liveness).

## Investigation

```bash
kubectl logs -n platform-api -l app=platform-api --tail=100 | grep '"level":"ERROR"'
```

Run `incident-queries.kql` #2 to see if the error rate is isolated to
one time window (a bad deploy, a config flip) or sustained (an upstream
dependency issue).

## Root cause

For this drill: `FAILURE_MODE` config flag. In production, this
pattern typically indicates a downstream dependency outage (the
message text "Backend dependency unavailable" is written to hint at
exactly this class of real-world cause) or a bad deployment.

## Fix

```bash
kubectl patch configmap platform-api-config -n platform-api \
  --type merge -p '{"data":{"FAILURE_MODE":"false"}}'
kubectl rollout restart deployment/platform-api -n platform-api
```

## Verification

Re-run `incident-queries.kql` #1 — `ErrorCount` should drop to baseline
within one 5-minute bin after the restart completes.

## Prevention

- Alert on error RATE, not raw count — query #2 divides by total
  request volume specifically so a traffic spike doesn't get
  misread as a reliability problem.
- `/health` and `/ready` intentionally don't reflect `FAILURE_MODE` —
  that's correct (a partial functional failure shouldn't cause
  Kubernetes to kill/reschedule healthy pods), but it means app-level
  error-rate alerting is not optional — pod health alone will miss this
  entire class of incident.
