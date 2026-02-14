# cc-otel Roadmap

> OpenTelemetry collector config and Grafana dashboard for Claude Code metrics.

## Problem Statement

Claude Code exports rich OpenTelemetry telemetry (8 metrics + 5 event types), but there is no turnkey, open-source setup
to collect, store, and visualize this data. Users must figure out collector configuration, pipeline routing, and
dashboard design from scratch. This repo provides a ready-to-use solution: OTel Collector config, Grafana dashboard
JSON, and deployment examples.

## Success Criteria

| Criteria                                            | Measurement                                                            |
|-----------------------------------------------------|------------------------------------------------------------------------|
| All 8 CC metrics visible in Prometheus              | Query each metric name and confirm non-empty results                   |
| All 5 CC event types visible in Loki                | Query each event name and confirm log entries                          |
| Grafana dashboard loads with all 26 panels          | Import JSON, verify no panel errors with live data                     |
| Local setup works with a single `docker-compose up` | Fresh clone + `docker-compose up` + CC with env vars = data in Grafana |
| k3s manifests deploy cleanly via `kubectl apply`    | Collector pod running, receiving OTLP, forwarding to Prom/Loki         |

## Architecture

```
Mac (Claude Code)
  │
  │  OTLP/gRPC :4317
  ▼
OTel Collector
  ├──► Prometheus  (remote_write, metrics pipeline)
  └──► Loki        (loki exporter, logs/events pipeline)
          │
          ▼
       Grafana (dashboard)
```

## Data Contract (what Claude Code exports)

### Metrics (→ Prometheus)

| Metric                                | Type    | Unit    | Key Attributes                                         |
|---------------------------------------|---------|---------|--------------------------------------------------------|
| `claude_code.session.count`           | Counter | count   | standard                                               |
| `claude_code.lines_of_code.count`     | Counter | count   | `type` (added/removed)                                 |
| `claude_code.pull_request.count`      | Counter | count   | standard                                               |
| `claude_code.commit.count`            | Counter | count   | standard                                               |
| `claude_code.cost.usage`              | Counter | USD     | `model`                                                |
| `claude_code.token.usage`             | Counter | tokens  | `type` (input/output/cacheRead/cacheCreation), `model` |
| `claude_code.code_edit_tool.decision` | Counter | count   | `tool`, `decision`, `language`                         |
| `claude_code.active_time.total`       | Counter | seconds | standard                                               |

**Standard attributes**: `session.id`, `user.account_uuid`, `organization.id`, `terminal.type`

### Events (→ Loki)

| Event                       | Key Attributes                                                                           |
|-----------------------------|------------------------------------------------------------------------------------------|
| `claude_code.user_prompt`   | `prompt_length`, `prompt` (opt-in)                                                       |
| `claude_code.tool_result`   | `tool_name`, `success`, `duration_ms`, `decision`, `source`                              |
| `claude_code.api_request`   | `model`, `cost_usd`, `duration_ms`, `input_tokens`, `output_tokens`, `cache_read_tokens` |
| `claude_code.api_error`     | `model`, `error`, `status_code`, `duration_ms`, `attempt`                                |
| `claude_code.tool_decision` | `tool_name`, `decision`, `source`                                                        |

---

## Phases

### Phase 1 — OTel Collector Config + Docker Compose Infrastructure

**Goal**: A single `docker-compose up` that starts the full observability stack locally (OTel Collector, Prometheus,
Loki, Grafana) and accepts Claude Code telemetry.

**Deliverables**:

- [ ] `otel-collector-config.yaml` — OTLP receiver (gRPC :4317), Prometheus remote write exporter, Loki exporter, two
  pipelines (metrics + logs)
- [ ] `docker-compose.yml` — OTel Collector, Prometheus, Loki, Grafana (all preconfigured)
- [ ] `prometheus.yml` — minimal config enabling remote write receiver
- [ ] `loki-config.yaml` — minimal local Loki config
- [ ] Grafana provisioning (datasources for Prometheus + Loki, auto-provisioned)
- [ ] `.env.example` — Claude Code env vars to copy into `~/.zshrc`
- [ ] Smoke test: `docker-compose up`, set CC env vars, run a short CC session, confirm metrics in Prometheus and events
  in Loki via their respective UIs

**Acceptance criteria**:

- `docker-compose up` succeeds with zero config changes on a fresh clone
- OTel Collector healthcheck passes
- After a CC session: `claude_code.token.usage` queryable in Prometheus, `claude_code.api_request` events visible in
  Loki
- All containers healthy, no error logs in collector

**Dependencies**: None

---

### Phase 2 — Grafana Dashboard (26 Panels)

**Goal**: A production-quality Grafana dashboard JSON that visualizes all Claude Code telemetry, importable into any
Grafana instance with Prometheus + Loki datasources.

**Deliverables**:

- [ ] `grafana/dashboards/claude-code.json` — full 26-panel dashboard
- [ ] Grafana provisioning config to auto-load the dashboard on `docker-compose up`

**Panel inventory** (grouped by section):

| #  | Panel                                  | Data Source | Derivation                                                |
|----|----------------------------------------|-------------|-----------------------------------------------------------|
| 1  | Real-Time Cost Burn Rate               | Prometheus  | `rate(claude_code.cost.usage)`                            |
| 2  | Total Cost Today                       | Prometheus  | `increase(claude_code.cost.usage[today])`                 |
| 3  | Cached Write Cost (24h)                | Prometheus  | token count × cacheCreation pricing                       |
| 4  | Regular Input Cost (24h)               | Prometheus  | input token count × input pricing                         |
| 5  | Code Edit Acceptance Rate %            | Prometheus  | accept / (accept + reject) from `code_edit_tool.decision` |
| 6  | Cost Forecast                          | Prometheus  | linear extrapolation of daily cost                        |
| 7  | Average Cost / Session                 | Prometheus  | total cost / session count                                |
| 8  | Cost per 1K Tokens                     | Prometheus  | cost / (tokens / 1000)                                    |
| 9  | Active Time (24h)                      | Prometheus  | `active_time.total` split by CLI vs user time             |
| 10 | Token Distribution by Model (24h)      | Prometheus  | `token.usage` grouped by `model`                          |
| 11 | Active Sessions (24h)                  | Prometheus  | distinct `session.id` count from `session.count`          |
| 12 | Average Session Metrics                | Prometheus  | avg cost, tokens, duration per session                    |
| 13 | Lines of Code Modified                 | Prometheus  | `lines_of_code.count` by `type`                           |
| 14 | Cache Hit Rate %                       | Prometheus  | cacheRead / (input + cacheRead) tokens                    |
| 15 | Total Tokens Today                     | Prometheus  | `increase(token.usage[today])`                            |
| 16 | Model Token Efficiency (tokens/$)      | Prometheus  | tokens / cost grouped by model                            |
| 17 | Tool Usage Breakdown                   | Loki        | count of `tool_result` events by `tool_name`              |
| 18 | Peak Cost Hours                        | Prometheus  | cost rate bucketed by hour                                |
| 19 | Weekly Total Token Usage               | Prometheus  | `increase(token.usage[7d])`                               |
| 20 | Cost Anomaly Detection                 | Prometheus  | deviation from rolling average (Grafana math)             |
| 21 | Prompts Per Hour                       | Loki        | count of `user_prompt` events per hour                    |
| 22 | Tool Decision Sources (24h)            | Loki        | `tool_decision` events grouped by `source`                |
| 23 | Code Modification Velocity (lines/min) | Prometheus  | `rate(lines_of_code.count)`                               |
| 24 | Token Usage Rate (24h)                 | Prometheus  | `rate(token.usage)`                                       |
| 25 | Prompt Length Distribution             | Loki        | histogram of `prompt_length` from `user_prompt` events    |
| 26 | Tool Usage Breakdown (pie)             | Loki        | `tool_result` events by `tool_name`                       |

**Acceptance criteria**:

- Dashboard JSON imports into Grafana without errors
- All 26 panels render with sample data (no "No data" on any panel after a CC session)
- Dashboard uses template variables for datasource selection (Prometheus / Loki)
- Time range selector works across all panels
- Dashboard auto-loads when using `docker-compose up`

**Dependencies**: Phase 1 (needs working local stack to test panels)

---

### Phase 3 — Documentation + Repository Polish

**Goal**: The repo is ready for public use. A developer can go from zero to a working dashboard by following the README.

**Deliverables**:

- [ ] `README.md` — project overview, quick start, architecture diagram, screenshots
- [ ] `docs/metrics-reference.md` — complete reference of all CC metrics and events (from official docs)
- [ ] `docs/env-vars.md` — Claude Code env var setup guide
- [ ] `docs/troubleshooting.md` — common issues (no data, connection refused, etc.)
- [ ] `.env.example` refined with comments
- [ ] `LICENSE` (MIT)

**Acceptance criteria**:

- A new user can follow the README and have data flowing within 10 minutes
- All metric names and attributes documented
- Troubleshooting covers the top 5 setup issues

**Dependencies**: Phase 2 (needs screenshots of working dashboard)

---

### Phase 4 — k3s / Kubernetes Deployment

**Goal**: Provide Kubernetes manifests and Helm examples for deploying the OTel Collector into an existing k3s/k8s
cluster that already runs Prometheus, Loki, and Grafana.

**Deliverables**:

- [ ] `k8s/base/` — plain Kubernetes manifests (Deployment, Service, ConfigMap for collector)
- [ ] `k8s/helm/` — Helm values example for the official `opentelemetry-collector` chart
- [ ] `docs/k8s-deployment.md` — deployment guide covering: prerequisites, Tailscale/networking setup, connecting to
  existing Prometheus + Loki
- [ ] ArgoCD Application manifest example (GitOps)

**Acceptance criteria**:

- `kubectl apply -k k8s/base/` deploys collector successfully
- Collector receives OTLP from outside the cluster (via Tailscale or NodePort)
- Metrics appear in cluster's existing Prometheus, events in Loki
- Grafana dashboard JSON from Phase 2 works unchanged against the k8s-hosted backends

**Dependencies**: Phase 3 (repo should be documented before adding deployment complexity)

---

## Tasks Index

> Detailed specs for each task. See [execution-graph.md](execution-graph.md) for dependency tree and parallelization
> map.

### Phase 1 — OTel Collector Config + Docker Compose Infrastructure

| ID | Task | Size | Spec |
|---|---|---|---|
| P1-T1 | OTel Collector Config | M | [tasks/phase1/otel-collector-config.md](tasks/phase1/otel-collector-config.md) |
| P1-T2 | Docker Compose Stack | L | [tasks/phase1/docker-compose-stack.md](tasks/phase1/docker-compose-stack.md) |

### Phase 2 — Grafana Dashboard

| ID | Task | Size | Spec |
|---|---|---|---|
| P2-T1 | Grafana Dashboard (26 panels) | XL | [tasks/phase2/grafana-dashboard.md](tasks/phase2/grafana-dashboard.md) |

### Phase 3 — Documentation + Repository Polish

| ID | Task | Size | Spec |
|---|---|---|---|
| P3-T1 | Repository Documentation | L | [tasks/phase3/repo-documentation.md](tasks/phase3/repo-documentation.md) |

### Phase 4 — k3s / Kubernetes Deployment

| ID | Task | Size | Spec |
|---|---|---|---|
| P4-T1 | Kubernetes / k3s Deployment | L | [tasks/phase4/k8s-deployment.md](tasks/phase4/k8s-deployment.md) |

---

## Non-Goals (explicit scope exclusions)

- **Shipping Prometheus/Loki/Grafana** — users bring their own; docker-compose includes them only for local development
  convenience
- **Custom Claude Code instrumentation** — we only consume what CC exports natively
- **Multi-user auth/RBAC in Grafana** — out of scope for this repo
- **Alerting rules** — may add as a future phase, not in v1
- **CI/CD pipeline for the repo itself** — premature for the current scope
- **Terraform / Pulumi IaC** — Kubernetes manifests + Helm are sufficient

## Open Questions

| # | Question                                                                                    | Owner       | Blocking?                                                     |
|---|---------------------------------------------------------------------------------------------|-------------|---------------------------------------------------------------|
| 1 | Should the docker-compose stack use Grafana Alloy instead of the standalone OTel Collector? | Engineering | No — start with standard OTel Collector, evaluate Alloy later |
| 2 | Do we need a data generator / simulator for demo purposes (no real CC session)?             | Engineering | No — nice-to-have for Phase 3                                 |
| 3 | Which Loki version/config to target (monolithic vs microservices)?                          | Engineering | Yes — decide in Phase 1 (monolithic for local, document both) |
