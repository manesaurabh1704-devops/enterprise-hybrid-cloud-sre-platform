# Azure Troubleshooting Runbook

## AKS cluster unreachable / kubectl commands time out

```bash
az aks get-credentials --resource-group rg-platform-sre-prod --name aks-platform-sre --overwrite-existing
az aks show --resource-group rg-platform-sre-prod --name aks-platform-sre --query "powerState"
```
If `powerState` isn't `Running`, the cluster itself may be stopped
(cost-saving stop/start) or in a failed provisioning state — check
`az aks show ... --query "provisioningState"`.

## GitHub Actions OIDC login failing

```
Error: AADSTS70021: No matching federated identity record found
```
Usually means the federated credential's `subject` doesn't match the
actual branch/environment the workflow ran from. Check:
```bash
az ad app federated-credential list --id <APP_ID>
```
Compare the `subject` field against `repo:<org>/<repo>:ref:refs/heads/main`
(or the environment-scoped subject if using GitHub Environments).

## ACR push/pull failures

```bash
az acr repository list --name acrplatformsre
az role assignment list --assignee <AKS_KUBELET_IDENTITY_ID> --scope <ACR_RESOURCE_ID>
```
AKS pulls images using the kubelet managed identity, not the cluster's
control-plane identity — confirm the `AcrPull` role is assigned to the
right one.

## Log Analytics / KQL returning no data

- Confirm Container Insights is actually enabled:
  ```bash
  az aks show --resource-group rg-platform-sre-prod --name aks-platform-sre \
    --query "addonProfiles.omsagent"
  ```
- Confirm the query's time range covers when the event happened — KQL
  defaults to the workspace's selected time range in the portal, not
  "all time."
- For `W3CIISLog` specifically: confirm the Data Collection Rule is
  associated with the Windows VM (`az monitor data-collection-rule
  association list`).

## General Azure Monitor / Resource Group audit

```bash
az resource list --resource-group rg-platform-sre-prod --output table
az monitor activity-log list --resource-group rg-platform-sre-prod --offset 1h
```
`activity-log` shows *who changed what* at the Azure control-plane
level — useful for "did someone change a setting" questions that
application/container logs can't answer.
