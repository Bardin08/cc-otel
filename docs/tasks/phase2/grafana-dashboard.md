# P2-T1: Grafana Dashboard (26 Panels)

**Phase**: 2 — Grafana Dashboard
**Size**: XL (large but systematic — each panel follows a pattern)
**Dependencies**: P1-T2 (docker-compose-stack must be functional for testing)

## Goal

Create a production-quality Grafana dashboard JSON with 26 panels that visualizes all Claude Code telemetry. The
dashboard must be importable into any Grafana instance that has Prometheus and Loki datasources, and it must auto-load
in the docker-compose stack.

## Scope

**In scope**:

- `grafana/dashboards/claude-code.json` — complete 26-panel dashboard
- Template variables for datasource selection (`$ds_prometheus`, `$ds_loki`)
- 7 logical row sections grouping related panels
- All panels from the roadmap panel inventory
- Grafana-side cost derivations using known model pricing constants

**Non-goals**:

- No alerting rules embedded in the dashboard
- No Grafana plugins beyond built-in panel types (stat, gauge, timeseries, piechart, barchart, bargauge, table)
- No multi-dashboard setup — everything in a single dashboard

## Deliverables

- [ ] `grafana/dashboards/claude-code.json`
- [ ] Update `grafana/provisioning/dashboards/dashboards.yaml` if needed (should already exist from P1-T2)

## Dashboard Structure

### Template Variables

| Variable | Type | Query | Purpose |
|---|---|---|---|
| `ds_prometheus` | datasource | type: `prometheus` | Select Prometheus datasource |
| `ds_loki` | datasource | type: `loki` | Select Loki datasource |

### Row Layout (7 sections)

**Row 1: Cost Overview** (panels 1-5)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 1 | Real-Time Cost Burn Rate | timeseries | `rate(claude_code_cost_usage_total[$__rate_interval])` |
| 2 | Total Cost Today | stat | `increase(claude_code_cost_usage_total[${__range}])` with time range = today |
| 3 | Cached Write Cost (24h) | stat | `increase(claude_code_token_usage_total{type="cacheCreation"}[24h])` × pricing constant |
| 4 | Regular Input Cost (24h) | stat | `increase(claude_code_token_usage_total{type="input"}[24h])` × pricing constant |
| 5 | Code Edit Acceptance Rate % | stat | `sum(increase(claude_code_code_edit_tool_decision_total{decision="accept"}[24h])) / sum(increase(claude_code_code_edit_tool_decision_total[24h])) * 100` |

**Row 2: Cost Analytics** (panels 6-10)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 6 | Cost Forecast | stat | Daily projection via `increase(cost[24h])`, monthly = daily × 30 |
| 7 | Average Cost / Session | stat | `increase(cost_total[24h]) / increase(session_count_total[24h])` |
| 8 | Cost per 1K Tokens | stat | `increase(cost_total[24h]) / (increase(token_usage_total[24h]) / 1000)` |
| 9 | Active Time (24h) | stat | `increase(claude_code_active_time_total_total[24h])` displayed as minutes |
| 10 | Token Distribution by Model (24h) | piechart | `increase(claude_code_token_usage_total[24h])` grouped by `model` |

**Row 3: Session & Code Metrics** (panels 11-13)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 11 | Active Sessions (24h) | stat | `increase(claude_code_session_count_total[24h])` |
| 12 | Average Session Metrics | bargauge | Avg cost, tokens, duration per session (composite) |
| 13 | Lines of Code Modified | bargauge | `increase(claude_code_lines_of_code_count_total{type="added"}[24h])` + same for removed |

**Row 4: Token Analytics** (panels 14-16)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 14 | Cache Hit Rate % | gauge | `sum(increase(token{type="cacheRead"}[24h])) / (sum(increase(token{type="input"}[24h])) + sum(increase(token{type="cacheRead"}[24h]))) * 100` |
| 15 | Total Tokens Today | stat | `increase(claude_code_token_usage_total[24h])` with 7d comparison |
| 16 | Model Token Efficiency (tokens/$) | bargauge | `increase(token[24h]) / increase(cost[24h])` by model |

**Row 5: Tool & Activity** (panels 17-19)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 17 | Tool Usage Breakdown (bar) | barchart | Loki: `count_over_time({event_name="claude_code.tool_result"} \| json \| [24h]) by (tool_name)` |
| 18 | Peak Cost Hours | timeseries | `sum(rate(claude_code_cost_usage_total[1h]))` bucketed by hour |
| 19 | Weekly Total Token Usage | stat | `increase(claude_code_token_usage_total[7d])` with week-over-week comparison |

**Row 6: Anomaly & Patterns** (panels 20-22)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 20 | Cost Anomaly Detection | timeseries | `rate(cost[5m]) / avg_over_time(rate(cost[5m])[24h:5m]) * 100` — deviation from rolling avg |
| 21 | Prompts Per Hour | timeseries | Loki: `count_over_time({event_name="claude_code.user_prompt"} [1h])` |
| 22 | Tool Decision Sources (24h) | piechart | Loki: `count_over_time({event_name="claude_code.tool_decision"} \| json \| [24h]) by (source)` |

**Row 7: Velocity & Distribution** (panels 23-26)

| # | Panel | Type | Query Logic |
|---|---|---|---|
| 23 | Code Modification Velocity (lines/min) | timeseries | `rate(claude_code_lines_of_code_count_total[5m]) * 60` by type |
| 24 | Token Usage Rate (24h) | timeseries + table | `rate(claude_code_token_usage_total[$__rate_interval])` with stats table |
| 25 | Prompt Length Distribution | barchart | Loki: histogram bucket `prompt_length` from `user_prompt` events |
| 26 | Tool Usage Breakdown (pie) | piechart | Loki: same data as #17 but as pie chart |

## Implementation Notes

### Metric Name Translation

OTel Collector + Prometheus remote write translates metric names. Dots become underscores, and counters get a `_total`
suffix:

| OTel metric name | Prometheus metric name |
|---|---|
| `claude_code.cost.usage` | `claude_code_cost_usage_total` |
| `claude_code.token.usage` | `claude_code_token_usage_total` |
| `claude_code.session.count` | `claude_code_session_count_total` |
| `claude_code.lines_of_code.count` | `claude_code_lines_of_code_count_total` |
| `claude_code.pull_request.count` | `claude_code_pull_request_count_total` |
| `claude_code.commit.count` | `claude_code_commit_count_total` |
| `claude_code.code_edit_tool.decision` | `claude_code_code_edit_tool_decision_total` |
| `claude_code.active_time.total` | `claude_code_active_time_total_total` |

### Cost Derivation Constants

For panels that derive dollar costs from token counts, use Grafana variables or hardcoded constants for current Claude
pricing. Document that these need updating when pricing changes.

### Loki Query Patterns

Events arrive as OTLP logs. The Loki exporter maps them with labels. Typical query pattern:

```logql
{exporter="OTLP"} | json | event_name = "claude_code.api_request"
```

The exact label set depends on how the Loki exporter in the OTel Collector maps resource attributes and log record
attributes to Loki labels vs structured metadata. This must be verified against the running stack from Phase 1 before
finalizing Loki panel queries.

### Dashboard JSON Generation

Build the dashboard by hand or use Grafana's UI to create panels and then export. Either approach is fine — the
deliverable is the final JSON file. If building by hand, use a Grafana dashboard JSON schema reference.

## Acceptance Criteria

- [ ] `grafana/dashboards/claude-code.json` is valid JSON and imports into Grafana without errors
- [ ] All 26 panels are present and organized into 7 rows
- [ ] Datasource template variables (`$ds_prometheus`, `$ds_loki`) are defined and used by all panels
- [ ] After a CC session against the docker-compose stack, no panel shows "No data" (all 26 render)
- [ ] Time range selector affects all panels consistently
- [ ] Dashboard auto-loads in the docker-compose stack via Grafana provisioning
- [ ] Panels use appropriate visualizations (stat for single numbers, timeseries for time data, piechart for
  distributions, etc.)
- [ ] 7-day average / comparison values show on relevant stat panels
- [ ] Cost derivation panels document the pricing assumptions used

## Verification Steps

1. `docker-compose up -d` (Phase 1 stack)
2. Open Grafana at `http://localhost:3000`
3. Navigate to the "Claude Code" dashboard — should be auto-provisioned
4. Verify both datasource template variables appear in the top bar
5. Set CC env vars, run a CC session (e.g., `claude -p "explain hello world"`)
6. Wait 60-90 seconds for metric export
7. Refresh dashboard — verify all 26 panels show data
8. Change time range to "Last 1 hour" — verify panels update
9. Export dashboard JSON from Grafana UI, diff against the file in repo — should be identical (or near-identical if
   Grafana adds runtime metadata)

## Parallelization Notes

- **Depends on**: P1-T2 (needs running stack to test queries and verify label mappings)
- **Blocks**: P3-T1 (documentation needs dashboard screenshots)
- **Partial parallel start**: Prometheus-based panels (#1-16, #18-20, #23-24) can be drafted based on known metric name
  translations. Loki panels (#17, #21-22, #25-26) require verifying the actual label schema from the running stack.
- **Can mock**: Draft the JSON structure, row layout, and Prometheus panels while P1-T2 is being finalized. Only Loki
  query syntax needs live verification.
