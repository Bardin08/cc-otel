# Metrics & Events Reference

Complete reference for all Claude Code OpenTelemetry metrics and events.

Source: [Claude Code — Monitoring Usage](https://docs.anthropic.com/en/docs/claude-code/monitoring)

---

## Resource Attributes

All telemetry is exported with these resource-level attributes:

| Attribute         | Description                                  | Example                          |
|-------------------|----------------------------------------------|----------------------------------|
| `service.name`    | Always `claude-code`                         | `claude-code`                    |
| `service.version` | Current Claude Code version                  | `1.0.16`                         |
| `os.type`         | Operating system type                        | `linux`, `darwin`, `windows`     |
| `os.version`      | Operating system version string              | `15.3.2`                         |
| `host.arch`       | Host architecture                            | `amd64`, `arm64`                 |
| `wsl.version`     | WSL version (only present on WSL)            | `2`                              |

Meter name: `com.anthropic.claude_code`

---

## Standard Attributes

All metrics and events include these attributes (when available):

| Attribute           | Description                                       | Controlled By                                       |
|---------------------|---------------------------------------------------|-----------------------------------------------------|
| `session.id`        | Unique session identifier                         | `OTEL_METRICS_INCLUDE_SESSION_ID` (default: `true`) |
| `app.version`       | Current Claude Code version                       | `OTEL_METRICS_INCLUDE_VERSION` (default: `false`)   |
| `organization.id`   | Organization UUID (when authenticated)            | Always included when available                      |
| `user.account_uuid` | Account UUID (when authenticated)                 | `OTEL_METRICS_INCLUDE_ACCOUNT_UUID` (default: `true`) |
| `terminal.type`     | Terminal type (e.g. `iTerm.app`, `vscode`, `cursor`, `tmux`) | Always included when detected          |

---

## Metrics (8 total)

All metrics are exported via the OTel metrics protocol. Prometheus receives them via its native OTLP endpoint, which converts OTel dot-notation names to underscores and appends unit and type suffixes (e.g., `_USD_total`, `_tokens_total`, `_seconds_total`).

### 1. `claude_code.session.count`

Count of CLI sessions started.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | count   |
| Prometheus | `claude_code_session_count_total` |

**Attributes**: [standard attributes](#standard-attributes)

---

### 2. `claude_code.lines_of_code.count`

Count of lines of code modified.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | count   |
| Prometheus | `claude_code_lines_of_code_count_total` |

**Attributes**: [standard attributes](#standard-attributes) plus:

| Attribute | Description                       | Values             |
|-----------|-----------------------------------|--------------------|
| `type`    | Whether lines were added/removed  | `added`, `removed` |

---

### 3. `claude_code.pull_request.count`

Number of pull requests created.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | count   |
| Prometheus | `claude_code_pull_request_count_total` |

**Attributes**: [standard attributes](#standard-attributes)

---

### 4. `claude_code.commit.count`

Number of git commits created.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | count   |
| Prometheus | `claude_code_commit_count_total` |

**Attributes**: [standard attributes](#standard-attributes)

---

### 5. `claude_code.cost.usage`

Cost of the Claude Code session in USD.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | USD     |
| Prometheus | `claude_code_cost_usage_USD_total` |

**Attributes**: [standard attributes](#standard-attributes) plus:

| Attribute | Description      | Example                         |
|-----------|------------------|---------------------------------|
| `model`   | Model identifier | `claude-sonnet-4-5-20250929` |

> **Note**: Cost metrics are approximations. For official billing data, refer to your API provider (Claude Console, AWS Bedrock, or Google Cloud Vertex).

---

### 6. `claude_code.token.usage`

Number of tokens used.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | tokens  |
| Prometheus | `claude_code_token_usage_tokens_total` |

**Attributes**: [standard attributes](#standard-attributes) plus:

| Attribute | Description      | Values                                           |
|-----------|------------------|--------------------------------------------------|
| `type`    | Token type       | `input`, `output`, `cacheRead`, `cacheCreation`  |
| `model`   | Model identifier | `claude-sonnet-4-5-20250929`                  |

---

### 7. `claude_code.code_edit_tool.decision`

Count of code editing tool permission decisions.

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | count   |
| Prometheus | `claude_code_code_edit_tool_decision_total` |

**Attributes**: [standard attributes](#standard-attributes) plus:

| Attribute  | Description                     | Values                                   |
|------------|---------------------------------|------------------------------------------|
| `tool`     | Tool name                       | `Edit`, `Write`, `NotebookEdit`          |
| `decision` | User decision                   | `accept`, `reject`                       |
| `language` | Language of the edited file     | `TypeScript`, `Python`, `JavaScript`, `Markdown`, `unknown` |

---

### 8. `claude_code.active_time.total`

Total active time in seconds. Tracks actual time spent actively using Claude Code (not idle time).

| Property   | Value   |
|------------|---------|
| Type       | Counter |
| Unit       | seconds |
| Prometheus | `claude_code_active_time_seconds_total` |

**Attributes**: [standard attributes](#standard-attributes)

---

## Events (5 total)

Events are exported via the OTel logs/events protocol. They require `OTEL_LOGS_EXPORTER` to be configured.

### 1. `claude_code.user_prompt`

Logged when a user submits a prompt.

| Attribute        | Description                                    | Notes                                        |
|------------------|------------------------------------------------|----------------------------------------------|
| `event.name`     | `user_prompt`                                  |                                              |
| `event.timestamp`| ISO 8601 timestamp                             |                                              |
| `event.sequence` | Monotonically increasing counter per session   |                                              |
| `prompt_length`  | Length of the prompt                            |                                              |
| `prompt`         | Prompt content                                 | Redacted by default; enable with `OTEL_LOG_USER_PROMPTS=1` |

---

### 2. `claude_code.tool_result`

Logged when a tool completes execution.

| Attribute         | Description                              | Values / Notes                                                    |
|-------------------|------------------------------------------|-------------------------------------------------------------------|
| `event.name`      | `tool_result`                            |                                                                   |
| `event.timestamp` | ISO 8601 timestamp                       |                                                                   |
| `event.sequence`  | Monotonically increasing counter         |                                                                   |
| `tool_name`       | Name of the tool                         |                                                                   |
| `success`         | Whether the tool succeeded               | `true`, `false`                                                   |
| `duration_ms`     | Execution time in milliseconds           |                                                                   |
| `error`           | Error message (if failed)                |                                                                   |
| `decision`        | Accept or reject                         | `accept`, `reject`                                                |
| `source`          | Decision source                          | `config`, `user_permanent`, `user_temporary`, `user_abort`, `user_reject` |
| `tool_parameters` | JSON with tool-specific parameters       | See below                                                         |

**`tool_parameters` details**:
- **Bash tool**: `bash_command`, `full_command`, `timeout`, `description`, `sandbox`
- **MCP tools** (when `OTEL_LOG_TOOL_DETAILS=1`): `mcp_server_name`, `mcp_tool_name`
- **Skill tool** (when `OTEL_LOG_TOOL_DETAILS=1`): `skill_name`

---

### 3. `claude_code.api_request`

Logged for each API request to Claude.

| Attribute              | Description                         |
|------------------------|-------------------------------------|
| `event.name`           | `api_request`                       |
| `event.timestamp`      | ISO 8601 timestamp                  |
| `event.sequence`       | Monotonically increasing counter    |
| `model`                | Model used                          |
| `cost_usd`             | Estimated cost in USD               |
| `duration_ms`          | Request duration in milliseconds    |
| `input_tokens`         | Number of input tokens              |
| `output_tokens`        | Number of output tokens             |
| `cache_read_tokens`    | Number of tokens read from cache    |
| `cache_creation_tokens`| Number of tokens for cache creation |

---

### 4. `claude_code.api_error`

Logged when an API request to Claude fails.

| Attribute         | Description                           |
|-------------------|---------------------------------------|
| `event.name`      | `api_error`                           |
| `event.timestamp` | ISO 8601 timestamp                    |
| `event.sequence`  | Monotonically increasing counter      |
| `model`           | Model used                            |
| `error`           | Error message                         |
| `status_code`     | HTTP status code (if applicable)      |
| `duration_ms`     | Request duration in milliseconds      |
| `attempt`         | Attempt number (for retried requests) |

---

### 5. `claude_code.tool_decision`

Logged when a tool permission decision is made.

| Attribute         | Description                                    | Values                                                                |
|-------------------|------------------------------------------------|-----------------------------------------------------------------------|
| `event.name`      | `tool_decision`                                |                                                                       |
| `event.timestamp` | ISO 8601 timestamp                             |                                                                       |
| `event.sequence`  | Monotonically increasing counter               |                                                                       |
| `tool_name`       | Name of the tool                               | `Read`, `Edit`, `Write`, `NotebookEdit`, etc.                         |
| `decision`        | Accept or reject                               | `accept`, `reject`                                                    |
| `source`          | Decision source                                | `config`, `user_permanent`, `user_temporary`, `user_abort`, `user_reject` |
