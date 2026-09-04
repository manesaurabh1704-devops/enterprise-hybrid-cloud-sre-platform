# Deployment Rollback Runbook

## AKS — automatic (via CD pipeline)

The `cd-pipeline.yml` `deploy` job already does this automatically when
`kubectl rollout status` times out. See `../incidents/INC-006-failed-deployment.md`.

## AKS — manual rollback

```bash
kubectl rollout history deployment/platform-api -n platform-api
kubectl rollout undo deployment/platform-api -n platform-api
# or to a specific revision:
kubectl rollout undo deployment/platform-api -n platform-api --to-revision=<N>
kubectl rollout status deployment/platform-api -n platform-api
```

## AKS — emergency: scale to zero then back

Only if a rollback itself is failing (e.g. previous ReplicaSet was
already garbage-collected past `revisionHistoryLimit: 5`):
```bash
kubectl set image deployment/platform-api \
  platform-api=<ACR>.azurecr.io/platform-api:<known-good-tag> \
  -n platform-api
kubectl rollout status deployment/platform-api -n platform-api
```

## IIS — manual rollback

`iis-deployment.ps1` always deploys from a `-SourcePath` folder, so
rollback is redeploying from the previous release's artifact folder:
```powershell
.\iis-deployment.ps1 -SiteName "PlatformAPI" -AppPoolName "PlatformAPIPool" `
    -SourcePath "C:\Deploy\platform-api\v1.1.0" `
    -PhysicalPath "C:\inetpub\wwwroot\platform-api"
```
This is why `windows-iis/README.md` recommends keeping the last 2-3
release folders on disk — without them, "rollback" means re-running the
full deployment pipeline for the previous version instead of a fast
file-copy.

## Deciding whether to roll back vs. fix forward

| Roll back if | Fix forward if |
|---|---|
| The previous version was known-good and stable | The bug is trivial and well-understood (e.g. a typo'd env var) |
| Root cause isn't yet clear | Rolling back would lose data/schema changes that can't easily reverse |
| Users are actively impacted right now | Impact is limited/contained and a fix is faster than a full redeploy cycle |

Default to rollback first, root-cause after — restoring service takes
priority over understanding the bug immediately.
