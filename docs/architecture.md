# Architecture & Roadmap

## Target role alignment

This project is built against the requirements of a **Software Engineer,
Cloud Site Reliability (SRE)** role: Azure + AKS, Windows Server + IIS,
CD pipelines, monitoring/log analysis (App/IIS/AKS/Azure), GitHub
collaboration, and rotational on-call/incident response.

## System architecture

```
                        Platform API (Flask)
                                |
                +---------------+----------------+
                |                                 |
        AKS (Linux workload)              Windows Server + IIS
                |                                 |
        Deployment / Service                  Website / App Pool
        ConfigMap / Secret                    SSL bindings
        Liveness & Readiness probes           Event Viewer / logs
                |                                 |
                +----------------+----------------+
                                 |
                          Azure Monitor
                                 |
                          Log Analytics
                                 |
                               KQL
                                 |
                     Incident Response / Runbooks
```

## CI/CD flow

```
Developer -> Git Push/PR -> GitHub Actions
                                |
                    +-----------+-----------+
                    |                       |
                Validate                Security Scan
                    |                       |
                    +-----------+-----------+
                                |
                             Deploy to AKS
                                |
                          Health Check
                          /          \
                      PASS          FAIL
                        |              |
                    Success       Rollback
```

## Build roadmap (phased)

- [x] **Phase 1 — Foundation**: repo structure, README, this doc, app code (Flask Platform API)
- [ ] **Phase 2 — Azure + AKS**: Resource Group, AKS cluster, namespace, Deployment, Service, resource limits, liveness/readiness, RollingUpdate, HPA, PDB, NetworkPolicy
- [ ] **Phase 3 — GitHub CD**: OIDC to Azure, GitHub Environment, CD workflow, manifest validation, rollout verification, automatic rollback
- [ ] **Phase 4 — Windows + IIS**: Website, App Pool, bindings, HTTPS/SSL, Event Viewer, App Pool health automation, SSL expiry automation, IIS deploy/rollback scripts
- [ ] **Phase 5 — Monitoring**: Azure Monitor, Log Analytics, KQL for 5xx rate, P95/P99 latency, pod restarts, availability
- [ ] **Phase 6 — Incident Response**: CrashLoopBackOff, readiness failure, IIS App Pool stopped, SSL expiry, HTTP 5xx spike, high latency, failed deployment + rollback — each documented as detection → impact → root cause → fix → prevention
- [ ] **Phase 7 — Security** (right-sized, not gold-plated): Azure RBAC, Kubernetes RBAC/secrets, GitHub branch protection — enough to speak to in an interview, not a full security product
- [ ] **Phase 8 — Interview prep**: architecture, troubleshooting, and behavioral answers grounded in what's actually in this repo

## Design decisions worth remembering

- **The app is a vehicle, not the product.** It exists only to generate
  realistic logs, latency, and failures for the infra/SRE layer to react
  to. Deliberately no DB, auth, frontend, or microservices.
- **AWS gets a documentation-level treatment**, not a parallel
  implementation — the target role is Azure-first, so depth went into
  Azure/AKS/Windows instead of spreading thin across three clouds.
- **Security is scoped to what the JD asks for** (compliance with best
  practices), not a maximal implementation — avoids diluting time away
  from the Azure/AKS/Windows/IIS core the role actually tests.
