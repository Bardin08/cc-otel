# cc-otel

Turnkey OpenTelemetry observability stack for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) telemetry. One `docker compose up` gives you metrics in Prometheus, events in Loki, and a 26-panel Grafana dashboard — no configuration required.

![Dashboard Screenshot](docs/assets/dashboard-screenshot.png)
<!-- TODO: replace with actual screenshot after verifying the dashboard -->

## What's Included

- **OTel Collector config** — OTLP receiver (gRPC + HTTP), Prometheus remote write exporter, Loki OTLP exporter
- **Docker Compose stack** — OTel Collector, Prometheus, Loki, Grafana (all preconfigured)
- **Grafana dashboard** — 26 panels covering cost, tokens, sessions, code edits, tool usage, and more
- **Documentation** — metrics reference, env var guide, troubleshooting

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/<your-org>/cc-otel.git
cd cc-otel
```

### 2. Start the stack

```bash
docker compose up -d
```

This starts four containers: OTel Collector (`:4317`), Prometheus (`:9090`), Loki (`:3100`), and Grafana (`:3000`).

### 3. Configure Claude Code

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

Reload your shell:

```bash
source ~/.zshrc
```

See [`.env.example`](.env.example) for all available options.

### 4. Run Claude Code

```bash
claude
```

Use it normally. Metrics export every 60 seconds, events every 5 seconds.

### 5. Open Grafana

Open [http://localhost:3000](http://localhost:3000). The **Claude Code** dashboard is auto-provisioned and ready — no login required.

## Architecture

```
Mac (Claude Code)
  │
  │  OTLP/gRPC :4317
  ▼
OTel Collector
  ├──► Prometheus  :9090  (remote_write, metrics pipeline)
  └──► Loki        :3100  (OTLP/HTTP, logs/events pipeline)
          │
          ▼
       Grafana     :3000  (dashboard)
```

The OTel Collector receives OTLP data from Claude Code and routes it to two backends:
- **Metrics** → Prometheus via remote write
- **Events/logs** → Loki via OTLP/HTTP

Grafana queries both backends and visualizes the data in a pre-built dashboard.

## Metrics & Events

Claude Code exports **8 metrics** and **5 event types**:

### Metrics (→ Prometheus)

| Metric | Type | Description |
|--------|------|-------------|
| `claude_code.session.count` | Counter | Sessions started |
| `claude_code.lines_of_code.count` | Counter | Lines added/removed |
| `claude_code.pull_request.count` | Counter | PRs created |
| `claude_code.commit.count` | Counter | Commits created |
| `claude_code.cost.usage` | Counter | Cost in USD |
| `claude_code.token.usage` | Counter | Tokens used (by type and model) |
| `claude_code.code_edit_tool.decision` | Counter | Edit accept/reject decisions |
| `claude_code.active_time.total` | Counter | Active usage time in seconds |

### Events (→ Loki)

| Event | Description |
|-------|-------------|
| `claude_code.user_prompt` | User submitted a prompt |
| `claude_code.tool_result` | Tool completed execution |
| `claude_code.api_request` | API request to Claude |
| `claude_code.api_error` | API request failed |
| `claude_code.tool_decision` | Tool permission decision made |

Full details: [docs/metrics-reference.md](docs/metrics-reference.md)

## Configuration

See [docs/env-vars.md](docs/env-vars.md) for all environment variables including:

- Export intervals
- Privacy controls (prompt logging, tool details)
- Metrics cardinality control
- Authentication (headers, mTLS)
- Custom resource attributes (team/department tagging)

## Kubernetes Deployment

See [docs/k8s-deployment.md](docs/k8s-deployment.md) for deploying the OTel Collector to an existing k3s/k8s cluster.

<!-- TODO: link will be added in Phase 4 (P4-T1) -->

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues:

- No metrics after a session
- Connection refused errors
- Missing labels in Loki
- Grafana "No data" panels
- Port conflicts

## Ports

| Service        | Port  | Purpose                 |
|----------------|-------|-------------------------|
| OTel Collector | 4317  | OTLP/gRPC receiver      |
| OTel Collector | 4318  | OTLP/HTTP receiver      |
| OTel Collector | 13133 | Health check            |
| Prometheus     | 9090  | Prometheus UI & API     |
| Loki           | 3100  | Loki API                |
| Grafana        | 3000  | Grafana UI              |

## License

[MIT](LICENSE)
