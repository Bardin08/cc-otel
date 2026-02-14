# P3-T1: Repository Documentation

**Phase**: 3 — Documentation + Repository Polish
**Size**: L
**Dependencies**: P2-T1 (needs working dashboard for screenshots)

## Goal

Make the repository ready for public consumption. A developer with no prior context should be able to go from `git
clone` to a working dashboard by following the README.

## Scope

**In scope**:

- `README.md` — project overview, quick start, architecture diagram, dashboard screenshot, feature list
- `docs/metrics-reference.md` — complete reference of all 8 metrics and 5 events with attributes
- `docs/env-vars.md` — Claude Code OTel env var setup guide with all options
- `docs/troubleshooting.md` — top issues and their resolutions
- `.env.example` — refine with full comments and all optional vars
- `LICENSE` — MIT

**Non-goals**:

- No contributing guide or code of conduct (premature for a small config repo)
- No GitHub Actions / CI setup
- No changelog (only one version so far)

## Deliverables

- [ ] `README.md`
- [ ] `docs/metrics-reference.md`
- [ ] `docs/env-vars.md`
- [ ] `docs/troubleshooting.md`
- [ ] `.env.example` (updated)
- [ ] `LICENSE`

## Content Specifications

### README.md

Structure:

1. **Title + badge area** — repo name, one-line description
2. **Dashboard screenshot** — the 26-panel dashboard (captured from Phase 2)
3. **What's included** — bullet list: collector config, dashboard JSON, docker-compose, k8s examples
4. **Quick Start** — numbered steps:
   - Clone the repo
   - `docker-compose up -d`
   - Add env vars to shell
   - Run Claude Code
   - Open Grafana at localhost:3000
5. **Architecture** — ASCII or Mermaid diagram (reuse from roadmap)
6. **Metrics & Events** — summary table with link to `docs/metrics-reference.md`
7. **Configuration** — link to `docs/env-vars.md`
8. **Kubernetes Deployment** — link to `docs/k8s-deployment.md` (Phase 4; add link placeholder)
9. **Troubleshooting** — link to `docs/troubleshooting.md`
10. **License** — MIT

### docs/metrics-reference.md

Mirror the data contract from the roadmap but with full detail:

- For each of the 8 metrics: name, OTel type, unit, Prometheus translated name, all attributes with descriptions and
  possible values
- For each of the 5 events: event name, all attributes with descriptions and types
- Standard attributes section
- Resource attributes section (`service.name`, `os.type`, etc.)

Source: Claude Code official docs at `https://code.claude.com/docs/en/monitoring-usage`

### docs/env-vars.md

Two sections:

1. **Required variables** — the 4 essential vars for OTLP setup
2. **Optional variables** — all tuning knobs: export intervals, cardinality control, prompt logging, resource
   attributes, dynamic headers

Include a copy-paste block for each common setup scenario:
- Local docker-compose
- Remote collector (Tailscale)
- Console debugging

### docs/troubleshooting.md

Cover these known issues:

| # | Problem | Cause | Solution |
|---|---|---|---|
| 1 | No metrics in Prometheus after CC session | Forgot to set env vars / export interval too long | Verify env vars, reduce `OTEL_METRIC_EXPORT_INTERVAL` |
| 2 | Collector logs "connection refused" to Prometheus | Prometheus not ready or remote write not enabled | Check `--web.enable-remote-write-receiver` flag |
| 3 | Collector logs "connection refused" to Loki | Loki not ready | Check `docker-compose ps`, Loki health endpoint |
| 4 | Events in Loki have no useful labels | Loki exporter config issue | Verify collector config Loki exporter settings |
| 5 | Grafana shows "No data" on all panels | Datasources misconfigured or no data ingested yet | Check datasource config, run a CC session, wait for export |

## Acceptance Criteria

- [ ] `README.md` quick start steps are copy-pasteable and result in a working setup
- [ ] `docs/metrics-reference.md` covers all 8 metrics and 5 events with every attribute
- [ ] `docs/env-vars.md` lists every relevant environment variable with description and example
- [ ] `docs/troubleshooting.md` covers at least 5 common issues
- [ ] `.env.example` has comments explaining each variable
- [ ] `LICENSE` is present and contains MIT license text
- [ ] All internal links between docs are valid
- [ ] README includes at least one dashboard screenshot

## Verification Steps

1. Read through README as a new user — are the quick start steps unambiguous?
2. Cross-reference `docs/metrics-reference.md` against Claude Code official docs — all metrics and events present?
3. Verify all links in README resolve to existing files
4. Spot-check `.env.example` — do all variable names match official Claude Code docs?
5. Confirm `LICENSE` file contains standard MIT license text

## Parallelization Notes

- **Depends on**: P2-T1 (need dashboard screenshot and confirmed panel queries)
- **Blocks**: P4-T1 (repo should be documented before adding k8s complexity)
- **Partial parallel start**: `docs/metrics-reference.md`, `docs/env-vars.md`, and `LICENSE` can be written in parallel
  with Phase 2 — they don't depend on the dashboard. Only the README (screenshot) and troubleshooting (verified against
  running stack) need Phase 2 complete.
- **Can mock**: README screenshot placeholder can be added and replaced later.
