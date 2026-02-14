# P1-T1: OTel Collector Configuration

**Phase**: 1 — OTel Collector Config + Docker Compose Infrastructure
**Size**: M
**Dependencies**: None (foundational task)

## Goal

Create the OpenTelemetry Collector configuration file that receives OTLP telemetry from Claude Code and routes it to
Prometheus (metrics) and Loki (logs/events) via two separate pipelines.

This is the core artifact of the entire repository. Every other task builds on top of this config.

## Scope

**In scope**:

- OTLP gRPC receiver on port 4317
- OTLP HTTP receiver on port 4318 (for flexibility)
- Batch processor for both pipelines
- Prometheus remote write exporter (metrics pipeline)
- Loki exporter (logs pipeline)
- Health check extension (port 13133)
- Two pipelines: `metrics` and `logs`

**Non-goals**:

- No authentication/TLS (local dev only; k3s auth handled in Phase 4)
- No custom processors or transformations on the data
- No filtering — pass through all 8 metrics and all 5 event types as-is

## Deliverables

- [ ] `otel-collector-config.yaml` at repository root

## Contract (interfaces other tasks depend on)

Other tasks depend on these fixed values:

| Interface | Value | Consumed by |
|---|---|---|
| OTLP gRPC port | `:4317` | Claude Code env vars, docker-compose, k8s Service |
| OTLP HTTP port | `:4318` | Alternative CC config |
| Health check port | `:13133` | docker-compose healthcheck, k8s readinessProbe |
| Prometheus remote write target | `http://prometheus:9090/api/v1/write` | docker-compose service name |
| Loki push target | `http://loki:3100/loki/api/v1/push` | docker-compose service name |

## Implementation Notes

Use the `otel/opentelemetry-collector-contrib` image (not the core image) because the Loki exporter is in contrib.

Minimal config structure:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024

exporters:
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
    resource_to_telemetry_conversion:
      enabled: true

  loki:
    endpoint: http://loki:3100/loki/api/v1/push

extensions:
  health_check:
    endpoint: 0.0.0.0:13133

service:
  extensions: [health_check]
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [loki]
```

Key decisions:

- `resource_to_telemetry_conversion: enabled: true` on the Prometheus exporter — this promotes OTel resource attributes
  (`session.id`, `model`, etc.) to Prometheus labels so they're queryable.
- Batch processor with 5s timeout balances latency vs efficiency for local dev.
- Loki exporter uses the contrib distribution's native `loki` exporter, which maps OTLP log records to Loki's push
  format and uses OTel resource/log attributes as Loki labels.

## Acceptance Criteria

- [ ] File passes `otelcol-contrib validate --config=otel-collector-config.yaml` (config validation)
- [ ] Config defines exactly two pipelines: `metrics` and `logs`
- [ ] OTLP receiver listens on both gRPC (:4317) and HTTP (:4318)
- [ ] Health check extension is configured on :13133
- [ ] Prometheus remote write exporter targets `http://prometheus:9090/api/v1/write`
- [ ] Loki exporter targets `http://loki:3100/loki/api/v1/push`
- [ ] `resource_to_telemetry_conversion` is enabled on the Prometheus exporter

## Verification Steps

1. Pull the collector image: `docker pull otel/opentelemetry-collector-contrib:latest`
2. Validate config:
   ```bash
   docker run --rm -v $(pwd)/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml \
     otel/opentelemetry-collector-contrib:latest validate --config=/etc/otelcol-contrib/config.yaml
   ```
3. Confirm exit code 0 and no validation errors in output.

## Parallelization Notes

- **Can start immediately** — no dependencies.
- **Blocks**: P1-T2 (docker-compose-stack) depends on this file existing and the contract above being final.
- **Can run in parallel with**: Nothing else in Phase 1, but the contract table above is stable enough that P1-T2
  could be stubbed against it.
