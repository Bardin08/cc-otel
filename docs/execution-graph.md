# Execution Graph

> Dependency tree and parallelization map for AI agent execution.

## Task Index

| ID    | Task                          | Phase | Size | Spec                                                                     |
|-------|-------------------------------|-------|------|--------------------------------------------------------------------------|
| P1-T1 | OTel Collector Config         | 1     | M    | [phase1/otel-collector-config.md](tasks/phase1/otel-collector-config.md) |
| P1-T2 | Docker Compose Stack          | 1     | L    | [phase1/docker-compose-stack.md](tasks/phase1/docker-compose-stack.md)   |
| P2-T1 | Grafana Dashboard (26 panels) | 2     | XL   | [phase2/grafana-dashboard.md](tasks/phase2/grafana-dashboard.md)         |
| P3-T1 | Repository Documentation      | 3     | L    | [phase3/repo-documentation.md](tasks/phase3/repo-documentation.md)       |
| P4-T1 | Kubernetes / k3s Deployment   | 4     | L    | [phase4/k8s-deployment.md](tasks/phase4/k8s-deployment.md)               |

## Dependency Graph

```
P1-T1  OTel Collector Config
  │
  ├──────────────────────┐
  │                      │
  ▼                      │
P1-T2  Docker Compose    │
  │                      │
  ▼                      │
P2-T1  Grafana Dashboard │
  │                      │
  ▼                      │
P3-T1  Documentation     │
  │                      │
  ├──────────────────────┘
  ▼
P4-T1  k8s Deployment
```

## Execution Order (critical path)

```
P1-T1 → P1-T2 → P2-T1 → P3-T1 → P4-T1
```

The critical path is strictly sequential — each task's primary output feeds the next. However, significant portions of
downstream tasks can start early via the parallelization opportunities below.

## Parallelization Opportunities

### During Phase 1

| Can start early | What exactly                                                                              | Blocked until                                         |
|-----------------|-------------------------------------------------------------------------------------------|-------------------------------------------------------|
| P1-T2 structure | `docker-compose.yml` skeleton, `prometheus.yml`, `loki-config.yaml`, Grafana provisioning | P1-T1 finalizes the contract table (ports, endpoints) |

P1-T1's contract (ports, endpoint URLs, health check path) is defined in the spec. If treated as stable, **P1-T1 and
P1-T2 can effectively run in parallel**.

### During Phase 2

| Can start early         | What exactly                                               | Blocked until                                          |
|-------------------------|------------------------------------------------------------|--------------------------------------------------------|
| P2-T1 Prometheus panels | Panels 1-16, 18-20, 23-24 (Prometheus-sourced)             | P1-T2 confirms the Prometheus metric name translations |
| P3-T1 partial docs      | `docs/metrics-reference.md`, `docs/env-vars.md`, `LICENSE` | Nothing — these are source-doc based                   |

Loki-sourced panels (#17, #21-22, #25-26) require verifying the actual label schema from the running stack.

### During Phase 3

| Can start early     | What exactly                                                                 | Blocked until                                 |
|---------------------|------------------------------------------------------------------------------|-----------------------------------------------|
| P4-T1 k8s manifests | `k8s/base/` manifests, `k8s/helm/values.yaml`, `k8s/argocd/application.yaml` | P1-T1 only (reuses the same collector config) |

The k8s manifests are wrappers around the collector config. Only `docs/k8s-deployment.md` and end-to-end verification
depend on the later phases.

## Stubbing / Mocking Strategy

| Task  | What can be stubbed                                                                                 | Contract it depends on                                    |
|-------|-----------------------------------------------------------------------------------------------------|-----------------------------------------------------------|
| P1-T2 | Collector config volume mount → use P1-T1's contract table for ports/endpoints                      | P1-T1 contract table                                      |
| P2-T1 | Dashboard JSON structure, row layout, Prometheus panels → draft with known metric name translations | OTel → Prometheus name mapping (documented in P2-T1 spec) |
| P2-T1 | Loki panels → stub with placeholder queries, finalize after verifying labels                        | Running stack from P1-T2                                  |
| P3-T1 | README screenshot → placeholder image, replace after Phase 2                                        | Working dashboard from P2-T1                              |
| P4-T1 | k8s manifests → `kubectl apply --dry-run=client` validation                                         | P1-T1 collector config                                    |

## Agent Execution Instructions

When executing this graph:

1. **Start with P1-T1** — it has zero dependencies and defines the contracts everything else uses.
2. **Proceed to P1-T2** immediately after P1-T1 (or in parallel if using the contract table).
3. **Run P2-T1** once the docker-compose stack is verified. Draft Prometheus panels first; Loki panels require a
   running stack to verify label mappings.
4. **Run P3-T1** once the dashboard is verified. Start `metrics-reference.md` and `env-vars.md` earlier if desired.
5. **Run P4-T1** last. The k8s manifests themselves can be drafted earlier (after P1-T1), but the deployment guide and
   verification require the full stack.

**Between each task**: verify the acceptance criteria before moving to the next. If a criterion fails, fix it before
proceeding — downstream tasks depend on the outputs being correct.
