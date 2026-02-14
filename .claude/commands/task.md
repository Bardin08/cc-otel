---
allowed-tools: Bash, Read, Edit, Write, Task, EnterPlanMode, AskUserQuestion
description: Implement a task for this project
user-invocable: true
---

# Task Implementation Workflow

The user provides a task reference (e.g., `P1-T1`) or a description. Execute this workflow:

## Phase 1: Read the Spec

1. Find the task file. Task files live in `docs/tasks/`.
   Task IDs follow the pattern `P<phase>-T<task>` (e.g., `P1-T1`, `P2-T3`).
   The file name includes the task ID. Use Glob to find it (`docs/tasks/*P1-T1*` etc.).
2. Read the task file completely. Extract objectives, scope, requirements,
   acceptance criteria, and dependencies.
3. If dependencies are listed, verify they exist in the codebase.
4. Read `docs/roadmap.md` and `docs/execution-graph.md` for broader context
   if this is the first task in the conversation.
5. Run `git log --oneline -10` for recent context.

Do NOT use a subagent for this. It's a few file reads at most.

## Phase 2: Investigate Affected Area

Spawn an Explore subagent (model: haiku) with:
- The task scope summary from Phase 1
- Which areas are affected (OTel config, Docker Compose, Grafana, k8s, docs)
- Instructions to find:
  - Existing patterns in the affected area (find similar completed config)
  - Existing validation tooling or scripts
  - File paths and directory structure relevant to the task

Keep only the subagent's summary.

## Phase 3: Plan

Enter plan mode (EnterPlanMode). Write a plan that includes:
- Exact files to create or modify, with paths
- What changes in each file, referencing which existing pattern to follow
- Validation steps per artifact type:
  - OTel Collector config → `otelcol-contrib validate --config=<file>`
  - Docker Compose → `docker compose config`
  - Grafana dashboard JSON → valid JSON, correct datasource UIDs
  - k8s manifests → `kubectl apply --dry-run=client -f <file>`
  - Markdown docs → no broken internal links

Map each plan item to the acceptance criteria from the task file.
Wait for user approval before proceeding.

## Phase 4: Implement

After plan approval:

**For small/medium tasks**: Implement directly in this conversation.
Follow AGENTS.md playbook for implementation order:
1. Create/modify config files per the plan
2. Validate each artifact with the appropriate tool
3. Update docs if required by the task spec

**For large tasks**: Spawn an implementation subagent (model: opus) with:
  - The approved plan (exact files and changes)
  - Pattern examples found in Phase 2
  - Acceptance criteria as completion checklist
  - Instruction: validate all config artifacts before returning

## Phase 5: Verify & Commit

After implementation:
1. Run validation commands for each modified artifact type
2. If failures, fix and retry (up to 3 attempts)
3. Run `git diff --stat` to show change summary
4. Walk through acceptance criteria from the task file
5. Ask the user: commit? If yes, use conventional commit format
   (`feat: ...`, `fix: ...`, `docs: ...`, etc.) referencing the task ID.
   Never add AI co-author lines.
