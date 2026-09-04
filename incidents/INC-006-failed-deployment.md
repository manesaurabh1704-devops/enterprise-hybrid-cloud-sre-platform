# INC-006: Failed Deployment — Automatic Rollback

## Summary

A new version is deployed with `READY_OVERRIDE=false` (simulating a
broken release that never becomes ready), and the CD pipeline detects
the failed rollout and automatically rolls back to the last known-good
version — with zero manual intervention.

## Simulating it

```bash
# Push a "broken" config change that will make new pods never pass readiness
kubectl patch configmap platform-api-config -n platform-api \
  --type merge -p '{"data":{"READY_OVERRIDE":"false"}}'
kubectl rollout restart deployment/platform-api -n platform-api
```

Or, more realistically, trigger `cd-pipeline.yml` on a commit that sets
this in `k8s-aks/configmap.yaml` — this is the actual failure path the
pipeline is designed to catch.

## Detection

The `deploy` job's **Wait for rollout to stabilize** step:

```bash
kubectl rollout status deployment/platform-api -n platform-api --timeout=180s
```

This blocks until every new pod is Ready, or times out. A timeout here
is what the pipeline treats as "deployment failed" — not the `kubectl
apply` exit code, which would report success even though the app never
became healthy.

## Impact

New pods sit at `0/1 Ready` (readiness probe on `/ready` failing) but
old pods from the previous ReplicaSet continue serving traffic
throughout, since Kubernetes' RollingUpdate strategy never removes old
pods until new ones are Ready. **User-facing impact should be zero** —
this is the entire point of readiness-gated rollouts.

## Investigation

```bash
kubectl get pods -n platform-api
# New ReplicaSet pods stuck at 0/1 Ready

kubectl describe pod <new-pod-name> -n platform-api
# Events: "Readiness probe failed: HTTP probe failed with statuscode: 503"
```

## Root cause

`READY_OVERRIDE=false` in the ConfigMap change that shipped with this
release (drill). In production, this simulates any change that breaks
the readiness path — a bad dependency URL, a missing secret, a broken
startup migration.

## Fix — automatic

The `deploy` job's **Rollback on failed rollout** step runs
automatically:

```bash
kubectl rollout undo deployment/platform-api -n platform-api
kubectl rollout status deployment/platform-api -n platform-api --timeout=120s
```

This restores the previous ReplicaSet (the last version that was
successfully Ready), and the workflow run fails loudly (`exit 1`) so
the team knows a rollback happened rather than silently "fixing" it.

## Verification

```bash
kubectl rollout history deployment/platform-api -n platform-api
kubectl get pods -n platform-api
# Should show pods from the PREVIOUS ReplicaSet, all Ready

curl -sf http://<service-ip>/ready
```

## Prevention

- This entire incident class is *already* prevented from becoming a
  user-facing outage by the readiness-gated RollingUpdate — the
  incident is really "a bad config almost shipped," not "the site went
  down."
- The interview-relevant point: **deployment acceptance is not treated
  as application health.** The pipeline waits for rollout stabilization
  and initiates rollback if the rollout doesn't become healthy within
  the timeout — that's the SRE design decision this incident
  demonstrates, not just the YAML.
