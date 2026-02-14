# Troubleshooting

Common issues when setting up the cc-otel observability stack.

---

## 1. No metrics in Prometheus after a Claude Code session

**Symptoms**: Prometheus queries for `claude_code_*` return no results.

**Causes & solutions**:

- **Environment variables not set or not loaded**. Verify they are active in your shell:
  ```bash
  echo $CLAUDE_CODE_ENABLE_TELEMETRY   # should print 1
  echo $OTEL_EXPORTER_OTLP_ENDPOINT    # should print http://localhost:4317
  ```
  If empty, re-add them to your `~/.zshrc` / `~/.bashrc` and reload (`source ~/.zshrc`), then restart Claude Code.

- **Export interval too long**. The default metrics interval is 60 seconds. Run a Claude Code session long enough for at least one export cycle, or reduce the interval:
  ```bash
  export OTEL_METRIC_EXPORT_INTERVAL=10000  # 10 seconds
  ```

- **Claude Code session too short**. Metrics are exported on a timer. If the session ends before the first export, no data is sent. Ensure the session runs for at least the export interval duration.

---

## 2. Collector logs "connection refused" to Prometheus

**Symptoms**: OTel Collector logs show errors like `connection refused` when exporting to Prometheus.

**Causes & solutions**:

- **Prometheus not ready yet**. The `docker-compose.yml` uses `depends_on` with a health check, but startup timing can vary. Restart the stack:
  ```bash
  docker compose down && docker compose up -d
  ```

- **OTLP receiver not enabled**. Prometheus must be started with `--web.enable-otlp-receiver`. This is already configured in the `docker-compose.yml` command. If you are using your own Prometheus instance, ensure this flag is set. The collector sends metrics to `http://prometheus:9090/api/v1/otlp` via the `otlphttp` exporter.

---

## 3. Collector logs "connection refused" to Loki

**Symptoms**: OTel Collector logs show errors like `connection refused` when exporting to Loki.

**Causes & solutions**:

- **Loki not ready**. Check container status:
  ```bash
  docker compose ps
  ```
  Loki should be running. Check its health endpoint:
  ```bash
  curl -s http://localhost:3100/ready
  ```

- **Loki config mismatch**. Ensure `allow_structured_metadata: true` is set in `loki-config.yaml` — the OTel Collector sends structured metadata with log entries.

---

## 4. Events in Loki have no useful labels

**Symptoms**: Log entries appear in Loki but are missing expected labels/attributes.

**Causes & solutions**:

- **`OTEL_LOGS_EXPORTER` not set**. Events require the logs exporter to be configured:
  ```bash
  export OTEL_LOGS_EXPORTER=otlp
  ```

- **Loki not configured for OTLP ingestion**. The collector sends events via the OTLP/HTTP endpoint (`/otlp`). Ensure Loki's OTLP endpoint is accessible at `http://loki:3100/otlp`.

- **Structured metadata not enabled**. Loki 3.x requires `allow_structured_metadata: true` in the limits config. This is already set in the provided `loki-config.yaml`.

---

## 5. Grafana shows "No data" on all panels

**Symptoms**: Dashboard loads but every panel displays "No data".

**Causes & solutions**:

- **No telemetry ingested yet**. Run a Claude Code session with the env vars set, wait for at least one export interval (60s default), then refresh the dashboard.

- **Datasources misconfigured**. In Grafana (http://localhost:3000), go to **Connections → Data sources** and verify:
  - Prometheus URL: `http://prometheus:9090`
  - Loki URL: `http://loki:3100`

- **Time range too narrow**. Expand the dashboard time range (e.g. "Last 1 hour") to capture the window when data was ingested.

- **Dashboard variable mismatch**. If the dashboard uses template variables for datasource selection, ensure they match the provisioned datasource names (`Prometheus` and `Loki`).

---

## 6. Docker Compose fails to start

**Symptoms**: `docker compose up` exits with errors.

**Causes & solutions**:

- **Port conflicts**. The stack uses ports `4317`, `4318`, `9090`, `3100`, `3000`, and `13133`. Check for conflicts:
  ```bash
  lsof -i :4317 -i :9090 -i :3100 -i :3000
  ```
  Stop conflicting services or change the host port mappings in `docker-compose.yml`.

- **Docker not running**. Ensure Docker Desktop (or the Docker daemon) is running.

- **Stale volumes**. If a previous run left corrupted data, remove volumes:
  ```bash
  docker compose down -v && docker compose up -d
  ```

---

## 7. Only metrics OR events appear, not both

**Symptoms**: Prometheus has metrics but Loki has no events (or vice versa).

**Causes & solutions**:

- **Missing exporter variable**. Both must be set:
  ```bash
  export OTEL_METRICS_EXPORTER=otlp   # for metrics → Prometheus
  export OTEL_LOGS_EXPORTER=otlp      # for events → Loki
  ```

- **Protocol mismatch**. Ensure `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` is set (the collector config expects gRPC on port 4317). If using HTTP, the endpoint should be `http://localhost:4318`.

---

## General Debugging Tips

- **Check collector health**: `curl http://localhost:13133`
- **Check collector logs**: `docker compose logs otel-collector`
- **Check all container statuses**: `docker compose ps`
- **Verify metrics in Prometheus UI**: Open http://localhost:9090, query `{__name__=~"claude_code.*"}`
- **Verify events in Loki via Grafana**: Open http://localhost:3000, go to Explore → Loki, query `{service_name="claude-code"}`
- **Console debugging**: Set `OTEL_METRICS_EXPORTER=console` and `OTEL_LOGS_EXPORTER=console` to see raw telemetry output in the terminal
