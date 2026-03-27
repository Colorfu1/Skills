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
- For "all job status" / "all my jobs" in this workspace, use a two-step merged view (this is usually sufficient):
  - Step 1 (local-recorded): query local ledger task IDs via `get --id` (preferred pretty command: `./scripts/volc_jobs_status_pretty.sh --all`)
  - Step 2 (same-name discovery): for each ledger job, query same-name jobs with `volc ml_task list --output json -n <job_name> -s Queue,Staging,Running,Success --format 'JobId,JobName,Status,Start,Creator,ResourceQueueId,TaskRoleSpecs'`
  - Step 2 keeps only active/successful same-name jobs; Failed/Killed rows are already represented by Step 1 ledger lookups
  - If ledger `job_name` is empty, derive the task name from the recorded YAML `TaskName` field (prefer `archived_yaml_path`, fallback `yaml_path`)
  - If CSV and JSONL ledgers diverge, merge both local ledgers and dedupe by `task_id` (prefer latest `submit_time`) before Step 1
  - Merge/dedupe by `JobId`, group by local task name / `JobName`, and show discovered same-name jobs with `*` suffix on status
  - `./scripts/volc_jobs_status_pretty.sh` runs Step 1 and Step 2 in parallel with `ThreadPoolExecutor(max_workers=8)` so total wall time is bounded by the slowest API calls, not the number of jobs
  - The script groups output by queue section (`normal`, `pipeline`, `other`) and only nests discovered same-name rows under ledger jobs with the same queue
  - The Step 2 implementation writes job names to a temp file before invoking Python; do not pipe names through stdin because hyphenated job names can break shell parsing
  - If `./scripts/volc_jobs_status_pretty.sh --all` hangs, keep the same two-step workflow but rerun Step 1 as a per-task `get --id` loop with per-call timeouts
  - Do not replace Step 1 with a broad `list --limit/offset` query; Step 1 is ledger `get --id`, Step 2 is same-name `list -n -s`.
- Fallback list query (account-wide; use only if local-ledger + same-name lookup is insufficient or the user asks account-wide, noisy in shared AK/SK):
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
- For "all job status", return a merged table (Step 1 local ledger `get` + Step 2 same-name `list -n -s`), deduped by `JobId`
- Use the helper script's conventions when presenting the merged view: title `Jobs Status (Local Ledger CSV -> volc ml_task get + same-name discovery)` and `*` suffix on statuses for active same-name jobs not present in the local ledger
- If the run is slow, explain the cause explicitly (remote Volc latency/stalls; Step 1 scales with local task ID count; Step 2 scales with unique local job name count)
- For `logs`: the requested lines (or summarized errors if long)
- For `cancel`: success/failure message and task ID
- For `export`: what was exported and where
- For list/get in this workspace, include worker count (`Workers`) when `TaskRoleSpecs` is available by summing `RoleReplicas` for `RoleName == "worker"` (fallback: sum all replicas)
- For every listed task row, include queue information derived from `ResourceQueueId` (`normal`, `pipeline`, or truncated raw queue ID for other queues).

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
- Always output pretty results (human-readable tables/sections) by default, including multi-step workflows; do not reply with raw TSV/JSON dumps unless explicitly requested
- Default list title for local workflow: `Jobs Status (Local Ledger CSV -> volc ml_task get + same-name discovery)`
- For "all my jobs" queries, prefer the helper script's merged pretty table instead of separate ledger/list sections
- Default columns for list output: `JobId | JobName | Status | W | Queue | Start`
- `Queue` should map `ResourceQueueId` to `normal`, `pipeline`, or truncated raw queue ID for other queues
- Jobs with `*` suffix on `Status` indicate active same-name discoveries not present in the local ledger (typically retries or manual resubmits)
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
- For "all jobs status" in this workspace, use the two-step workflow: (1) local ledger `get --id` for recorded task IDs, then (2) same-name `list -n <job_name> -s Queue,Staging,Running,Success` lookups for active/successful sibling jobs.
- Step 2 filters out Failed/Killed rows because those states are already captured by Step 1 ledger lookups.
- The helper script groups rows by queue section and only nests discovered same-name jobs under ledger jobs with the same queue.
- Do not treat same-name discoveries as local-ledger corruption by default; they are usually valid retries or reruns.
- If you reimplement Step 2 manually, pass job names via a temp file rather than a stdin pipe to avoid shell parsing issues with hyphenated names.
- Use broad account-wide `list --limit/offset` paging only as a fallback or when the user explicitly asks for account-wide discovery beyond local recorded names.

## References

- Read `references/volc-ml-task-job-ops.md` for common command patterns and troubleshooting.
- Read workspace `ml_task.md` for the broader `ml_task` reference (submit + management commands).
