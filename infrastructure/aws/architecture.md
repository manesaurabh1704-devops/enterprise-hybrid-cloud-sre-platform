# AWS-Equivalent Architecture (documentation only, not implemented)

The target role is Azure-first (Azure + AKS + Windows/IIS), so the
hands-on build in this repo stays on Azure. This doc exists to show the
same design translates to AWS, since the JD also mentions "manage cloud
environments (AWS, Azure)".

| Azure | AWS equivalent |
|---|---|
| Resource Group | Account / VPC boundary |
| Virtual Network (VNet) | VPC |
| Subnet | Subnet |
| AKS | EKS |
| Azure Container Registry | ECR |
| Azure Monitor | CloudWatch |
| Log Analytics + KQL | CloudWatch Logs Insights |
| Azure Key Vault | AWS Secrets Manager / Parameter Store |
| Azure RBAC | IAM (roles + policies) |
| Managed Identity | IAM Roles for Service Accounts (IRSA) on EKS |
| Azure AD OIDC (GitHub Actions) | AWS IAM OIDC provider for GitHub Actions |
| Windows VM (IIS) | EC2 Windows instance |
| Network Security Group | Security Group |

## What would change operationally

- Node pools -> EKS managed node groups (same system/user pool split
  logic applies).
- HPA/PDB/NetworkPolicy manifests are Kubernetes-native and would run
  unchanged on EKS.
- CI/CD OIDC trust moves from Azure AD to an AWS IAM OIDC identity
  provider — the GitHub Actions workflow logic (validate -> scan ->
  deploy -> health check -> rollback) stays the same, only the
  authentication step and CLI (`az` -> `aws`/`eksctl`) change.
- IIS on EC2 Windows behaves identically to IIS on an Azure VM — the
  Windows Server/IIS layer isn't cloud-specific.
