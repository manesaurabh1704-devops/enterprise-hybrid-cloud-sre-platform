## What changed

<!-- Brief description of the change -->

## Type of change

- [ ] Application code (`app/`)
- [ ] Kubernetes manifests (`k8s-aks/`)
- [ ] Windows/IIS scripts (`windows-iis/`)
- [ ] CI/CD workflow
- [ ] Documentation / runbook

## Checklist

- [ ] Tests pass locally (`pytest app/tests/`)
- [ ] Kubernetes manifests validated (`kubeconform -strict k8s-aks/*.yaml`)
- [ ] No secrets committed (check `git diff` for values, not just filenames)
- [ ] Linked incident/runbook updated if this fixes a documented issue

## How was this tested?

<!-- e.g. ran locally, applied to a dev namespace, simulated the failure it fixes -->
