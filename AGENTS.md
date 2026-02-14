# AGENTS.MD — Canonical AI Agent Instructions

Shared guidance for all AI coding agents working in this repository.
Human contributors should also treat this as a contribution guide until a dedicated CONTRIBUTING.md is created.

---

## Purpose

This file is the **single source of truth** for how AI agents (and humans) should work in `cc-otel`.
All vendor-specific wrappers (CLAUDE.MD, copilot-instructions, etc.) must defer to this file.

## Project Context

`cc-otel` provides a turnkey observability stack for Claude Code telemetry:
OTel Collector config, Docker Compose stack, Grafana dashboard, documentation, and k8s manifests.
This is a **configuration-only** repo — no application code. Deliverables are YAML, JSON, and Markdown.

Phases and task specs live in `docs/`. Read `docs/roadmap.md` for high-level context and
`docs/execution-graph.md` for task ordering before starting work.

---

## Core Values

1. **KISS** — Keep it simple. No over-engineering. No abstractions for single-use cases.
2. **YAGNI** — Don't build for hypothetical futures. Solve the current task.
3. **Simplicity & maintainability** — Prefer the obvious approach. Minimal diffs. Easy to review.

## Safety & Non-Goals

- **No secrets exfiltration.** Never print, log, or commit tokens, keys, or credentials.
- **No destructive actions** unless explicitly requested (e.g., `git push --force`, `rm -rf`).
- **No "clever" refactors.** Prefer straightforward, readable changes over elegant but opaque ones.
- **No drive-by cleanup.** Keep changes scoped to the task. Don't fix unrelated style issues.

---

## Working Rules

### Ask vs. Assume

- When something is unclear, **ask** before proceeding.
- If asking is not possible (automation context), make the **smallest reasonable assumption** and document it explicitly
  in the PR description.

### PR-Only Workflow

- **No direct commits to `master`.** All changes go through pull requests.
- PRs must have a clear title, summary of changes, and list of files modified.
- Keep PRs focused — one task per PR when possible.

### Branch Naming

```
<type>/<TASK-ID>-<description>
```

| Part          | Rule                                        | Example       |
|---------------|---------------------------------------------|---------------|
| `type`        | `feat`, `fix`, `docs`, `chore`, `refactor`  | `feat`        |
| `TASK-ID`     | Always **UPPERCASE**                        | `P1-T1`       |
| `description` | Always **lowercase**, kebab-case, ≤ 4 words | `otel-config` |

Full example: `feat/P1-T1-otel-config`

### Scoped Changes

- Only touch files relevant to the current task.
- Don't add docstrings, comments, or type annotations to code you didn't change.
- Don't introduce new dependencies unless the task spec requires it.

### Commit Attribution

- **Never add `Co-Authored-By` or similar AI attribution lines to commits.** All commits are authored by the human who requested them. AI agents do not receive co-author credit.

---

## Output Contract for AI Changes

When describing changes, always include:

1. **File paths** — exact paths for every file created or modified.
2. **What changed and why** — concise summary, not a line-by-line diff narration.
3. **Assumptions** — list any assumptions made when requirements were ambiguous.

### Validation

This repo's deliverables are config files. Validate changes with the tools available per task spec:

| Artifact               | Validation                                           |
|------------------------|------------------------------------------------------|
| OTel Collector config  | `otelcol-contrib validate --config=<file>`           |
| Docker Compose         | `docker compose config` (syntax check)               |
| Prometheus config      | `promtool check config <file>` (if available)        |
| Grafana dashboard JSON | Valid JSON; panels reference correct datasource UIDs |
| k8s manifests          | `kubectl apply --dry-run=client -f <file>`           |
| Markdown docs          | No broken internal links; consistent formatting      |

### Observability Conventions

This repo **defines** observability config — it doesn't emit its own telemetry.
When writing collector configs, Prometheus rules, or Grafana queries, follow the data contract
in `docs/roadmap.md` (metrics table and events table).

Metric naming: OTel dot notation → Prometheus underscore + `_total` suffix for counters.
Example: `claude_code.cost.usage` → `claude_code_cost_usage_total`

---

## Playbooks

### Feature Implementation

1. **Discover** — Read the relevant task spec in `docs/tasks/`. Understand acceptance criteria.
2. **Plan** — Identify files to create/modify. Note dependencies on other tasks.
3. **Implement** — Write the config/code. Follow the spec closely.
4. **Validate** — Run the validation steps from the task's acceptance criteria.
5. **PR** — Open a PR with a clear description. Reference the task ID (e.g., "Implements P1-T1").

### Bug Triage

1. **Reproduce** — Confirm the issue with `docker compose up` or relevant tooling.
2. **Isolate** — Identify which config file or component is responsible.
3. **Fix** — Minimal change to resolve the issue.
4. **Verify** — Run acceptance criteria for the affected task.
5. **PR** — Reference the original issue if one exists.

### Code Review Support

- Respond to review comments in-line; don't open new threads.
- If a comment requests a change, make it or explain why not — don't ignore.
- Keep follow-up commits atomic. Don't squash mid-review unless asked.
