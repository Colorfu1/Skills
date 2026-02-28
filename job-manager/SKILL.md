---
name: job-manager
description: Manage already-submitted Volc ML Platform jobs (`volc ml_task`) including listing tasks, checking status/details, viewing logs, inspecting instances, exporting config/code, monitoring resource usage, and canceling tasks. Use when Codex needs to operate on existing jobs after submission, troubleshoot running/failed jobs, or generate/execute Volc job management commands safely.
---

# Job Manager

## Overview

Use this skill for post-submit job operations on Volc ML Platform custom training tasks.

Focus on safe lifecycle management of existing tasks: inspect, monitor, troubleshoot, export, and cancel only with explicit confirmation.

## Workflow

### 1. Identify the Target Job(s)

Collect or discover the target task before running commands:

- `task_id` (preferred)
- task name (if task ID is unknown)
- instance ID (for logs/top, for example `worker_0`)
- whether the user wants interactive output or machine-readable `json`

If the task ID is unknown, prefer the local submission ledger first (CSV/JSONL written by the submit script), then query each stored `task_id` with `volc ml_task get --id ...`.
Use `volc ml_task list` for discovery of jobs not in the local ledger (including auto-retried jobs with a new task ID).

Workspace preference:

- Default to local-ledger-driven status queries for "my jobs":
  - Submit with `scripts/volc_submit_and_archive.sh` (stores `task_id` locally)
  - Ledger files live under `submitted_jobs_yamls/` (prefer CSV: `submission_ledger.csv`; JSONL is also recorded)
  - Query status/details by reading stored task IDs and calling `volc ml_task get --id <task_id> --output json`
  - Preferred pretty command: `./scripts/volc_jobs_status_pretty.sh`
- For job-name-based lookup (including retry chains), prefer built-in list filtering:
  - `volc ml_task list --output json -n <job_name> -s Queue,Staging,Running,Killing,Success,Failed,Killed,Initialized --format 'JobId,JobName,Description,Status,Start,Creator,ResourceQueueId,TaskRoleSpecs'`
  - Reason: `-n/--name` is much faster and more reliable than broad paging + client-side filtering.
- Important: `volc ml_task list` defaults to `-s Queue,Staging,Running,Killing`, which excludes terminal states (`Success`, `Failed`, `Killed`). When searching by job name or retries, explicitly include terminal statuses.
- For "all job status" in this workspace, use a merged view:
  - Source A: local ledger task IDs (`get --id`)
  - Source B: account `list` query with expanded `-s` (to include retry jobs not in local cache)
  - Merge/dedupe by `JobId`, and group by `JobName` so retries are visible.
- Fallback list query (account-wide, noisy in shared AK/SK):
  - `volc ml_task list --output json --limit 200 --offset 0 -s Queue,Staging,Running,Killing,Success,Failed,Killed,Initialized --format 'JobId,JobName,Description,Status,Start,Creator,ResourceQueueId,TaskRoleSpecs'`
  - Page offsets `200, 400, 600, 800` only if needed.
  - Reason: this Volc CLI defaults to `--limit 10` when `--output json` is used; this API can also prepend non-JSON text before the JSON payload.

### 2. Choose the Operation

Classify the request and choose the smallest command that answers it:

- Status / details: `get`
- Logs: `logs`
- Running/all tasks overview: `list`
- Resource usage: `top`
- Export config/code: `export`
- Instance details/list: `instance list`
- Stop task: `cancel`

Prefer read-only commands first when debugging.

### 3. Show the Exact Command

Before execution, show the exact `volc ml_task ...` command.

Examples:

- `volc ml_task get --id <task_id> --output json`
- `./scripts/volc_jobs_status_pretty.sh --all`
- `volc ml_task list --output json -n <job_name> -s Queue,Staging,Running,Killing,Success,Failed,Killed,Initialized --format 'JobId,JobName,Description,Status,Start,Creator,ResourceQueueId,TaskRoleSpecs'`
- `volc ml_task list --output json --limit 200 --offset 0 -s Queue,Staging,Running,Killing,Success,Failed,Killed,Initialized --format 'JobId,JobName,Description,Status,Start,Creator,ResourceQueueId,TaskRoleSpecs'`
- `volc ml_task logs -t <task_id> -i worker_0 -l 200`
- `volc ml_task cancel --id <task_id>`

Use lowercase `json` for `--output json`.
Note: in this CLI, using `--format` without `--output json` may still open the interactive TUI for `list`.
Note: this CLI may print a non-JSON prefix before the JSON array; robust automation should strip leading lines before `[` when parsing.

### 4. Confirm Risky Actions

Require explicit confirmation before any command that changes remote state:

- `volc ml_task cancel --id <task_id>`

For read-only commands (`list`, `get`, `logs`, `top`, `export --config`), confirmation is optional unless the user requests it.

### 5. Execute and Return Results

Return concise results:

- For `list/get`: key status fields (`task_id`, name, status, start time, queue)
- For job-name lookups, list all matching task IDs (including retries) sorted by `Start` newest-first
- For "all job status", return a merged table (ledger + list-only retries), deduped by `JobId`
- For `logs`: the requested lines (or summarized errors if long)
- For `cancel`: success/failure message and task ID
- For `export`: what was exported and where
- For list/get in this workspace, include worker count (`Workers`) when `TaskRoleSpecs` is available by summing `RoleReplicas` for `RoleName == "worker"` (fallback: sum all replicas)

If running in a restricted sandbox and Volc API calls fail, use approved host/outside-sandbox terminal execution when available.

## Volc Command Map (Post-Submit)

Common `volc ml_task` commands for this skill:

- `list` - list tasks (interactive by default; use `--output json` for parsing)
  - Supports `-n/--name` filter by task name or task id
  - Supports `-s/--status` filter; default excludes terminal states
- `get` - task details
- `logs` - instance logs
- `top` - container load / resource usage
- `cancel` - stop a task
- `export` - export task config and/or code
- `instance list` - list task instances

Use `volc ml_task --help` and subcommand `--help` to confirm flags for the installed CLI version.

## Output Style

When responding to a job-management request, prefer this order:

1. Target task(s) identified
2. Command executed (or planned)
3. Result summary
4. Raw key output lines (if helpful)
5. Next command suggestion (optional, for example `logs` after a failed `get`)

Workspace formatting preference:

- Always list query results explicitly (do not only summarize)
- Use a pretty table by default (even for a single matched row)
- Default list title for local workflow: `Jobs Status (Local Ledger CSV -> volc ml_task get)`
- Default columns for list output: `JobId | JobName | Status | Workers | ResourceQueueId | Creator | Start/Error`
- For merged "all jobs" views, include `Source` (`ledger`, `list-only`, `both`) and group same `JobName` retries together when helpful
- Keep raw JSON optional (include only when helpful or requested)
- Avoid raw TSV/JSON-only output when presenting results to the user unless they explicitly ask for machine-readable output.

## Safety Rules

- Do not cancel a task unless the user explicitly asks to cancel and confirms the command.
- Do not guess task IDs when multiple matches exist; show candidates and ask which one.
- Prefer `--output json` for automation/parsing.
- Prefer `-n <job_name>` for job-name/retry discovery instead of broad paging + client-side `jq` filtering.
- When using `list` for completed/failed jobs, always expand `-s` to include terminal states (`Success,Failed,Killed` at minimum).
- If `volc ml_task list` opens an interactive UI unexpectedly, rerun with `--output json`.
- If `volc ml_task list` output is not directly parseable JSON, strip any leading non-JSON lines before the first `[` and then parse.
- For "all jobs status" in this workspace, do not rely only on the local ledger; merge with `list` results so auto-retry jobs not in local cache are included.

## References

- Read `references/volc-ml-task-job-ops.md` for common command patterns and troubleshooting.
- Read workspace `ml_task.md` for the broader `ml_task` reference (submit + management commands).
