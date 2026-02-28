# Volc ML Task Job Management Reference

This reference covers post-submit lifecycle operations for existing Volc ML tasks.

## Quick Start

### List active tasks (interactive)

```bash
volc ml_task list
```

### List tasks (machine-readable)

```bash
volc ml_task list --output json
```

### List only `owner-tag` jobs (recommended in this workspace)

With `jq`:

```bash
volc ml_task list --output json --format JobId,JobName,Description,Status,Start,Creator | jq '.[] | select(.Description=="owner-tag")'
```

Without `jq` (Python one-liner):

```bash
volc ml_task list --output json --format JobId,JobName,Description,Status,Start,Creator | python3 -c 'import json,sys; data=json.load(sys.stdin); print(json.dumps([x for x in data if x.get("Description")=="owner-tag"], ensure_ascii=False, indent=2))'
```

### Get task details

```bash
volc ml_task get --id <task_id> --output json
```

### Get logs for an instance

```bash
volc ml_task logs -t <task_id> -i worker_0 -l 200
```

### Follow logs

```bash
volc ml_task logs -t <task_id> -i worker_0 -f
```

### Cancel a task (destructive)

```bash
volc ml_task cancel --id <task_id>
```

### Export config/code

```bash
volc ml_task export -t <task_id> --config
volc ml_task export -t <task_id> --code
```

## Common Flags

### `list`

- `--status`, `-s`: filter by status
- `--name`, `-n`: filter by task name or ID
- `--output json`: non-interactive output
- `--format`: select fields

### `get`

- `--id`, `-i`: task ID (required)
- `--output json`
- `--format`

### `logs`

- `--task`, `-t`: task ID (required)
- `--instance`, `-i`: instance ID (required)
- `--lines`, `-l`: line count
- `--content`, `-c`: keyword/Lucene filter
- `--reverse`, `-r`: oldest-first
- `-f`: follow
- `--list`: list available log files
- `--log-file`: choose a log file (default `stdout&stderr`)

## Common Status Values

- `Initialized`
- `Queue`
- `Staging`
- `Running`
- `Killing`
- `Success`
- `Failed`
- `Killed`
- `Exception`

## Troubleshooting

### Interactive UI appears when parsing `list`

Problem:
- `volc ml_task list` opens TUI output

Fix:
- Use `volc ml_task list --output json`

### Network / proxy / firewall issues

Symptoms:
- `请检查网络是否连通，或请求是否被防火墙拦截`
- `proxyconnect tcp: dial tcp 127.0.0.1:7890 ...`
- DNS lookup failures to Volc API endpoints

Checks:
- Verify local network and firewall
- Verify proxy env vars: `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`
- If running in a sandbox, rerun on the host/outside-sandbox terminal

### Wrong `--output` casing

Problem:
- `--output Json` may fail depending on CLI behavior/version

Fix:
- Use lowercase `--output json`

## Usage Guidance for Codex

- Show the exact command before execution.
- Ask for explicit confirmation before `cancel`.
- Return concise summaries first, then key raw lines.
- Use host execution if sandbox network cannot reach Volc API.
- In this workspace, default "show my jobs" queries to `Description == "owner-tag"` filtering.
