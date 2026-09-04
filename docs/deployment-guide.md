# Deployment Guide

## One-time setup: GitHub Actions -> Azure OIDC (no stored secrets)

Instead of a service principal secret sitting in GitHub forever, we use
a federated credential so GitHub issues a short-lived OIDC token that
Azure trusts for this exact repo/branch.

```bash
# 1. Create an Azure AD App Registration
az ad app create --display-name "gh-platform-sre-cd"

# 2. Create a Service Principal for it
az ad sp create --id <APP_ID>

# 3. Assign least-privilege role, scoped to the resource group only
az role assignment create \
  --assignee <APP_ID> \
  --role Contributor \
  --scope /subscriptions/<SUB_ID>/resourceGroups/rg-platform-sre-prod

# 4. Add a federated credential trusting this repo's main branch
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "gh-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<ORG>/<REPO>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Then set these as **GitHub repo secrets** (values only, never expire):

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App registration's Application (client) ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

No client secret is ever generated or stored — that's the point of OIDC.

## Branch protection (GitHub repo settings)

- `main`: require PR review, require status checks (`validate`,
  `security-scan`) to pass, no direct pushes, no force-push.
- `develop`: require status checks only, direct pushes allowed for
  solo iteration speed.
- `GitHub Environment: production` — attached to the `deploy` job,
  can require manual approval before deploying to AKS.

## Rollback behavior

The `deploy` job in `cd-pipeline.yml` treats a deployment as failed if
`kubectl rollout status` doesn't report success within 180s (pods not
becoming Ready — see `readinessProbe` in `deployment.yaml`). On
failure it automatically runs `kubectl rollout undo`, which restores
the previous ReplicaSet. See `incidents/INC-006-failed-deployment.md`
for a walkthrough of this actually happening.

## Manual deploy (if needed)

```bash
az aks get-credentials --resource-group rg-platform-sre-prod --name aks-platform-sre
kubectl apply -f k8s-aks/
kubectl rollout status deployment/platform-api -n platform-api
```
