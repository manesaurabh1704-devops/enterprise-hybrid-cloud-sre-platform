# INC-001: AKS CrashLoopBackOff

## Summary

Reproducing this by setting `CRASH_ON_STARTUP=true` in the ConfigMap
causes the container to exit(1) immediately on start, which Kubernetes
interprets as a crash and enters a backoff-restart loop.

## Simulating it

```bash
kubectl patch configmap platform-api-config -n platform-api \
  --type merge -p '{"data":{"CRASH_ON_STARTUP":"true"}}'
kubectl rollout restart deployment/platform-api -n platform-api
```

## Detection

```bash
kubectl get pods -n platform-api
# NAME                            READY   STATUS             RESTARTS
# platform-api-7d9f8c6b5d-x2k9p   0/1     CrashLoopBackOff   4 (2m ago)
```

Or via KQL: `azure-monitor/incident-queries.kql` query #3 (pods with
`ContainerRestartCount > 3`).

## Impact

- Pod never reaches Ready, so it's never added to the Service endpoints
  — no user traffic is affected as long as at least one healthy
  ReplicaSet's pods still exist. If this happened on **every** pod in a
  fresh rollout, the Deployment as a whole has zero capacity.
- `kubectl rollout status` would time out and the CD pipeline's
  auto-rollback (see INC-006) would trigger.

## Investigation

```bash
kubectl describe pod platform-api-7d9f8c6b5d-x2k9p -n platform-api
# Look at: Last State (Reason: Error, Exit Code), and the Events section

kubectl logs platform-api-7d9f8c6b5d-x2k9p -n platform-api --previous
# --previous is essential here — the CURRENT container has already
# crashed and restarted, so its own logs are empty/fresh. The crash
# reason is in the PREVIOUS container's log.
```

Expected log line:
```json
{"level":"ERROR","message":"CRASH_ON_STARTUP is set to true — simulating startup crash"}
```

Also check events for the pattern:
```bash
kubectl get events -n platform-api --field-selector involvedObject.name=platform-api-7d9f8c6b5d-x2k9p
```

Or via KQL: `azure-monitor/incident-queries.kql` query #4.

## Root cause

`CRASH_ON_STARTUP=true` was left set (in this drill, intentionally; in
reality this class of bug is usually a bad config value, a missing
required env var, or an unhandled exception in app startup code).

## Fix

```bash
kubectl patch configmap platform-api-config -n platform-api \
  --type merge -p '{"data":{"CRASH_ON_STARTUP":"false"}}'
kubectl rollout restart deployment/platform-api -n platform-api
kubectl rollout status deployment/platform-api -n platform-api
```

## Verification

```bash
kubectl get pods -n platform-api
# All pods should show STATUS=Running, READY=1/1

kubectl exec -n platform-api deploy/platform-api -- curl -sf localhost:8080/health
```

## Prevention

- ConfigMap changes should go through the same PR review as code
  changes — `infrastructure-validation.yml` already validates manifest
  syntax, but doesn't currently catch semantically dangerous values
  (a follow-up: add a policy check, e.g. OPA/Conftest, that flags
  `CRASH_ON_STARTUP: "true"` outside of a designated demo namespace).
- Any app that can crash on bad config should log the specific reason
  *before* exiting, which this app already does — that's what made
  `kubectl logs --previous` useful here.
