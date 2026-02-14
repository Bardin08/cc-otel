# P1-T2: Docker Compose Stack

**Phase**: 1 — OTel Collector Config + Docker Compose Infrastructure
**Size**: L
**Dependencies**: P1-T1 (otel-collector-config)

## Goal

Create a complete `docker-compose up`-ready local observability stack: OTel Collector, Prometheus, Loki, and Grafana —
all preconfigured to work together with zero manual setup. A user clones the repo, runs `docker-compose up`, configures
4 env vars in their shell, and starts seeing Claude Code telemetry.

## Scope

**In scope**:

- `docker-compose.yml` with 4 services (collector, prometheus, loki, grafana)
- `prometheus.yml` — minimal Prometheus config with remote write receiver enabled
- `loki-config.yaml` — monolithic-mode Loki config for local development
- Grafana provisioning: datasource definitions for Prometheus and Loki
- Grafana provisioning: dashboard provider config (dashboard JSON added in Phase 2)
- `.env.example` — Claude Code environment variables
- Container healthchecks for all 4 services
- Named volumes for data persistence across restarts

**Non-goals**:

- No TLS/authentication between services (local dev only)
- No custom Grafana plugins
- No resource limits / production tuning
- Dashboard JSON itself (Phase 2)

## Deliverables

- [ ] `docker-compose.yml`
- [ ] `prometheus.yml`
- [ ] `loki-config.yaml`
- [ ] `grafana/provisioning/datasources/datasources.yaml`
- [ ] `grafana/provisioning/dashboards/dashboards.yaml` (provider config; dashboard dir mount)
- [ ] `grafana/dashboards/.gitkeep` (placeholder until Phase 2 adds the JSON)
- [ ] `.env.example`

## Implementation Notes

### docker-compose.yml

4 services with these key settings:

| Service | Image | Ports (host) | Key config |
|---|---|---|---|
| `otel-collector` | `otel/opentelemetry-collector-contrib:0.120.0` | `4317:4317`, `4318:4318`, `13133:13133` | Mounts `otel-collector-config.yaml` |
| `prometheus` | `prom/prometheus:v3.2.1` | `9090:9090` | Mounts `prometheus.yml`, `--web.enable-remote-write-receiver` flag |
| `loki` | `grafana/loki:3.4.2` | `3100:3100` | Mounts `loki-config.yaml` |
| `grafana` | `grafana/grafana:11.5.2` | `3000:3000` | Mounts provisioning dirs, `GF_AUTH_ANONYMOUS_ENABLED=true` |

Pin image tags to specific versions (not `latest`) for reproducibility.

Service dependency order: `prometheus` + `loki` start first → `otel-collector` depends on both → `grafana` depends on
`prometheus` + `loki`.

### prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Remote write receiver is enabled via CLI flag --web.enable-remote-write-receiver
# No scrape configs needed — all data arrives via remote write from the OTel Collector
```

### loki-config.yaml

Monolithic mode (single-process). Key points:

- Auth disabled (`auth_enabled: false`)
- Filesystem storage backend (local volume)
- TSDB as the index type (Loki 3.x default)
- Reject samples older than 168h (1 week) for local dev

### Grafana provisioning

**Datasources** (`grafana/provisioning/datasources/datasources.yaml`):

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
```

**Dashboard provider** (`grafana/provisioning/dashboards/dashboards.yaml`):

```yaml
apiVersion: 1
providers:
  - name: cc-otel
    type: file
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

### .env.example

```bash
# Add these to your ~/.zshrc or ~/.bashrc, then restart your shell.
# Then run Claude Code normally — telemetry will flow to the local collector.

export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# Optional: faster export for debugging (defaults: metrics=60s, logs=5s)
# export OTEL_METRIC_EXPORT_INTERVAL=10000
# export OTEL_LOGS_EXPORT_INTERVAL=5000

# Optional: include prompt content in events (disabled by default for privacy)
# export OTEL_LOG_USER_PROMPTS=1
```

## Acceptance Criteria

- [ ] `docker-compose up -d` succeeds with zero config changes on a fresh clone
- [ ] All 4 containers reach healthy status within 30 seconds
- [ ] Prometheus UI (`http://localhost:9090`) is accessible
- [ ] Loki readiness endpoint (`http://localhost:3100/ready`) returns 200
- [ ] Grafana UI (`http://localhost:3000`) loads with both datasources pre-configured
- [ ] OTel Collector health check (`http://localhost:13133`) returns 200
- [ ] After setting CC env vars and running a short CC session:
  - `claude_code_token_usage_total` is queryable in Prometheus
  - `{event_name="claude_code.api_request"}` returns results in Loki
- [ ] `docker-compose down && docker-compose up -d` preserves previous data (named volumes)
- [ ] No error-level log lines from the collector during normal operation

## Verification Steps

1. `docker-compose up -d`
2. Wait for health: `docker-compose ps` — all services should show "healthy"
3. Check collector: `curl -s http://localhost:13133 | jq .status` → `"Server available"`
4. Check Prometheus: `curl -s http://localhost:9090/-/healthy` → 200
5. Check Loki: `curl -s http://localhost:3100/ready` → `ready`
6. Check Grafana datasources: `curl -s http://localhost:3000/api/datasources | jq '.[].name'` → shows Prometheus, Loki
7. Set env vars from `.env.example`, run `claude --dangerously-skip-permissions -p "say hello"`, wait 60s for metric
   export
8. Query Prometheus: `curl -s 'http://localhost:9090/api/v1/query?query=claude_code_token_usage_total' | jq .data.result`
   → non-empty
9. Query Loki: `curl -s 'http://localhost:3100/loki/api/v1/query_range' --data-urlencode 'query={event_name=~".+"}' --data-urlencode 'start=...' | jq .data.result` → non-empty
10. `docker-compose down`

## Parallelization Notes

- **Depends on**: P1-T1 (needs `otel-collector-config.yaml` finalized, but the contract is defined so work can overlap)
- **Blocks**: P2-T1 (Grafana dashboard needs the stack running for testing)
- **Can run in parallel with**: P1-T1 if the contract table from P1-T1 is treated as stable
