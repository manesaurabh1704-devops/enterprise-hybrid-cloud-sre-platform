# Azure Architecture

## Resource layout

```
Subscription
   |
   +-- Resource Group: rg-platform-sre-prod
         |
         +-- AKS Cluster: aks-platform-sre
         |      +-- Node Pool: system (2 nodes, no workloads scheduled)
         |      +-- Node Pool: user (3-8 nodes, autoscaling, runs platform-api)
         |
         +-- Azure Container Registry: acrplatformsre
         |
         +-- Log Analytics Workspace: law-platform-sre
         |
         +-- Azure Monitor (Container Insights enabled on AKS)
         |
         +-- Key Vault: kv-platform-sre  (secrets -> CSI driver -> AKS)
         |
         +-- Windows VM / VM Scale Set: vm-iis-platform (IIS workload)
```

## Why these choices

- **Separate system/user node pools** — system pool runs only
  cluster-critical pods (CoreDNS, metrics-server); the app never
  contends with cluster components for resources, and system nodes
  don't need to scale with traffic.
- **AKS with cluster autoscaler on the user pool** — traffic-driven
  scaling at the node level, paired with the HPA at the pod level.
- **ACR instead of Docker Hub** — private registry, integrates with AKS
  via managed identity (no image-pull secrets to rotate).
- **Log Analytics + Container Insights** — a single workspace collects
  AKS container logs, IIS logs (via Azure Monitor Agent on the Windows
  VM), and application logs, so KQL can correlate across all three.
- **Key Vault + CSI Secret Store driver** — secrets never live as plain
  Kubernetes Secrets checked into anything; they're mounted at runtime
  from Key Vault.

## Identity & access

- **AKS -> ACR**: managed identity, `AcrPull` role only.
- **GitHub Actions -> Azure**: OIDC federated credential (no long-lived
  service principal secrets stored in GitHub).
- **Least privilege**: the CI/CD identity has `Contributor` scoped to
  the single resource group, not the subscription.

## AKS resource sizing (starting point)

| Resource | Requests | Limits |
|---|---|---|
| platform-api container | 100m CPU / 128Mi | 250m CPU / 256Mi |
| Node pool (user) | Standard_D2s_v5 (2 vCPU/8GB), 3-8 nodes | — |

Sizing is intentionally conservative for a demo workload — the point is
to show correct *practice* (requests/limits always set, HPA tied to
them), not to size for real production load.

## Networking

- AKS uses Azure CNI (pod IPs routable on the VNet) so NetworkPolicy and
  future integration with on-prem/Windows VM networking stay simple.
- Windows IIS VM sits in the same VNet, different subnet, with an NSG
  restricting inbound to 443/3389 (RDP scoped to a bastion/jump subnet
  only, never public).

## AWS-equivalent mapping

See [`../aws/architecture.md`](../aws/architecture.md) for how each of
these maps to AWS — the target role is Azure-first, so the hands-on
build stays on Azure/AKS while this shows the same architectural
thinking transfers.
