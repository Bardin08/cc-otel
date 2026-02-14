# Environment Variables Guide

How to configure Claude Code to export OpenTelemetry data.

Source: [Claude Code — Monitoring Usage](https://docs.anthropic.com/en/docs/claude-code/monitoring)

---

## Required Variables

These four variables are the minimum needed to send telemetry to a collector:

| Variable                         | Description                    | Value for this stack        |
|----------------------------------|--------------------------------|-----------------------------|
| `CLAUDE_CODE_ENABLE_TELEMETRY`   | Enable telemetry collection    | `1`                         |
| `OTEL_METRICS_EXPORTER`          | Metrics exporter type          | `otlp`                      |
| `OTEL_LOGS_EXPORTER`             | Logs/events exporter type      | `otlp`                      |
| `OTEL_EXPORTER_OTLP_ENDPOINT`   | Collector endpoint             | `http://localhost:4317`     |

You also need to set the protocol (gRPC is recommended for this stack):

| Variable                         | Description                    | Value for this stack        |
|----------------------------------|--------------------------------|-----------------------------|
| `OTEL_EXPORTER_OTLP_PROTOCOL`   | OTLP transport protocol        | `grpc`                      |

---

## Optional Variables

### Export Intervals

| Variable                       | Description                               | Default    |
|--------------------------------|-------------------------------------------|------------|
| `OTEL_METRIC_EXPORT_INTERVAL`  | Metrics export interval (ms)              | `60000`    |
| `OTEL_LOGS_EXPORT_INTERVAL`    | Logs export interval (ms)                 | `5000`     |

Lower intervals are useful for debugging. For production, the defaults are fine.

### Privacy & Content Logging

| Variable                 | Description                                          | Default    |
|--------------------------|------------------------------------------------------|------------|
| `OTEL_LOG_USER_PROMPTS`  | Log full prompt content (otherwise only length)      | disabled   |
| `OTEL_LOG_TOOL_DETAILS`  | Log MCP server/tool names and skill names in events  | disabled   |

Set either to `1` to enable.

### Metrics Cardinality Control

Control which attributes are included in metrics to manage storage and query performance:

| Variable                              | Description                              | Default  |
|---------------------------------------|------------------------------------------|----------|
| `OTEL_METRICS_INCLUDE_SESSION_ID`     | Include `session.id` in metrics          | `true`   |
| `OTEL_METRICS_INCLUDE_VERSION`        | Include `app.version` in metrics         | `false`  |
| `OTEL_METRICS_INCLUDE_ACCOUNT_UUID`   | Include `user.account_uuid` in metrics   | `true`   |

Set to `false` to disable an attribute. Lower cardinality = better query performance + less storage.

### Authentication

| Variable                                          | Description                          |
|---------------------------------------------------|--------------------------------------|
| `OTEL_EXPORTER_OTLP_HEADERS`                     | Static auth headers for OTLP         |
| `OTEL_EXPORTER_OTLP_METRICS_CLIENT_KEY`           | Client key for mTLS                  |
| `OTEL_EXPORTER_OTLP_METRICS_CLIENT_CERTIFICATE`   | Client certificate for mTLS          |

### Signal-Specific Endpoint Overrides

Send metrics and logs to different backends:

| Variable                                | Description                              |
|-----------------------------------------|------------------------------------------|
| `OTEL_EXPORTER_OTLP_METRICS_PROTOCOL`  | Protocol for metrics (overrides general) |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT`  | Endpoint for metrics (overrides general) |
| `OTEL_EXPORTER_OTLP_LOGS_PROTOCOL`     | Protocol for logs (overrides general)    |
| `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`     | Endpoint for logs (overrides general)    |

### Custom Resource Attributes

Add team/department identification:

```bash
export OTEL_RESOURCE_ATTRIBUTES="department=engineering,team.id=platform,cost_center=eng-123"
```

> **Format rules** (W3C Baggage spec): No spaces in values. Comma-separated `key=value` pairs. Percent-encode special characters.

### Dynamic Headers

For environments requiring token refresh, configure a helper script in `.claude/settings.json`:

```json
{
  "otelHeadersHelper": "/bin/generate_opentelemetry_headers.sh"
}
```

| Variable                                    | Description                    | Default       |
|---------------------------------------------|--------------------------------|---------------|
| `CLAUDE_CODE_OTEL_HEADERS_HELPER_DEBOUNCE_MS` | Header refresh interval (ms) | `1740000` (29 min) |

---

## Copy-Paste Blocks

### Local Docker Compose (this repo)

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Claude Code OTel — local docker-compose stack
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

Then reload your shell (`source ~/.zshrc`) and start Claude Code.

### Remote Collector (e.g. Tailscale)

```bash
# Claude Code OTel — remote collector
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://<tailscale-ip>:4317
```

Replace `<tailscale-ip>` with your collector host's Tailscale IP.

### Console Debugging

Useful for verifying telemetry is being emitted without running a full stack:

```bash
# Claude Code OTel — console debug output
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=console
export OTEL_LOGS_EXPORTER=console
export OTEL_METRIC_EXPORT_INTERVAL=1000
```

Metrics and events will be printed to the Claude Code terminal output.
