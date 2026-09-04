# Enterprise Hybrid Cloud Infrastructure & Site Reliability Platform

A production-style hybrid cloud SRE platform built to demonstrate real
operational capability across **Azure, AKS, Windows Server/IIS, CI/CD,
observability, and incident response** — not just infrastructure code,
but the troubleshooting and reliability engineering that goes with it.

This repo is built for the **Software Engineer, Cloud Site Reliability
(SRE)** role profile: Azure + AKS + Windows/IIS + monitoring + on-call
incident response.

## Why this project exists

Most portfolio projects show a working deployment. This one is built to
show what happens **when things break** — because that's what an SRE
role actually tests for. Every major component pairs infrastructure
code with a deliberately triggered failure scenario, a diagnostic
process, a fix, and a prevention note.

## What's in here

| Area | What it demonstrates |
|---|---|
| `app/` | Minimal Flask "Platform API" — the workload used to exercise everything else (liveness/readiness probes, failure & latency simulation, structured logging) |
| `k8s-aks/` | AKS manifests: Deployment, Service, ConfigMap, HPA, PDB, NetworkPolicy |
| `windows-iis/` | Windows Server + IIS automation: health monitoring, SSL audit, deployment/rollback scripts |
| `azure-monitor/` | KQL queries for error rate, P95/P99 latency, availability |
| `.github/workflows/` | CD pipeline: validate → security scan → deploy to AKS → health check → auto-rollback on failure |
| `infrastructure/` | Azure architecture docs + an AWS-equivalent architecture mapping |
| `incidents/` | Real incident write-ups: detection → impact → root cause → fix → prevention |
| `runbooks/` | Troubleshooting runbooks for AKS, IIS, Azure, deployments |
| `docs/` | Architecture, security, monitoring, and interview-prep notes |

## Architecture at a glance

```
                 Developer
                     |
                Git Push / PR
                     |
                GitHub Actions ---- security scan
                     |
                  Deploy to AKS
                     |
              Health Check (readiness)
                 /          \
             PASS          FAIL
               |              |
            Success       Auto-Rollback

        Platform API (Flask)
               |
        ---------------------
        |                   |
   AKS (Linux)      Windows Server + IIS
        |                   |
   Container logs      IIS/Event logs
        \___________________/
                 |
          Azure Monitor / Log Analytics
                 |
                KQL
                 |
          Incident Response / On-call
```

## Status

Actively being built phase by phase (see `docs/architecture.md` for the
full roadmap). Each phase is committed only once it's actually working —
not just written.

## Local development

```bash
cd app
pip install -r requirements.txt
python app.py
# in another terminal
curl localhost:8080/health
curl localhost:8080/ready
curl "localhost:8080/api/failure?force=true"
```

Run tests:

```bash
cd app
pytest tests/ -v
```
