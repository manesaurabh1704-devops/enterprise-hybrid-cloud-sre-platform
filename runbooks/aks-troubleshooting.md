# AKS Troubleshooting Runbook

## Pod stuck in Pending

```bash
kubectl describe pod <pod-name> -n platform-api
```
Look for Events: `FailedScheduling` — usually insufficient node
resources (check `kubectl top nodes`) or a NodeSelector/affinity rule
that no node satisfies.

## Pod in CrashLoopBackOff

See `../incidents/INC-001-crashloopbackoff.md` for the full walkthrough.
Quick version:
```bash
kubectl logs <pod-name> -n platform-api --previous
kubectl describe pod <pod-name> -n platform-api
```

## Pod Running but not Ready (0/1)

```bash
kubectl describe pod <pod-name> -n platform-api
# Check Events for "Readiness probe failed"
kubectl exec <pod-name> -n platform-api -- curl -sv localhost:8080/ready
```

## ImagePullBackOff

```bash
kubectl describe pod <pod-name> -n platform-api
# Check Events for the exact registry/image/tag and auth error
```
Common causes: ACR managed identity role assignment missing/wrong,
image tag doesn't exist, ACR name typo in `deployment.yaml`.

## Service not routing traffic

```bash
kubectl get endpoints platform-api -n platform-api
# If empty, no pods are currently Ready — that's the real problem,
# not the Service itself.
kubectl get pods -n platform-api -l app=platform-api
```

## Rollout stuck / not progressing

```bash
kubectl rollout status deployment/platform-api -n platform-api
kubectl rollout history deployment/platform-api -n platform-api
kubectl get replicasets -n platform-api
```
See `deployment-rollback.md` for manual rollback steps.

## General log/event commands

```bash
kubectl logs -n platform-api -l app=platform-api --tail=100 -f
kubectl get events -n platform-api --sort-by='.lastTimestamp'
kubectl top pod -n platform-api
kubectl get hpa -n platform-api
```
