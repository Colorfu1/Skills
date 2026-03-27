---
name: feishu-experiment-doc
description: Create or update concise Feishu experiment docs (especially for Volc ml_task runs) using strict minimal templates. Use when the user wants to record experiments in Feishu/wiki and avoid verbose docs; supports minimal create and incremental status/result updates.
---

# Feishu Experiment Doc

## Goal

Create and update experiment records in Feishu with a minimal default format.

This skill is intentionally opinionated: concise first, details only on request.

## When To Use

Use this skill when the user asks to:

- create a Feishu/wiki page to record experiments
- append status or results to an existing experiment doc
- keep a clean experiment log for training jobs (for example Volc `ml_task`)
- recreate the same doc under a different wiki node (current tools do not support move)

## Default Policy (Strict)

By default, write only the minimum useful information.

- Max 5 sections
- Max 3 bullets per section
- Prefer one jobs table over long prose
- Prefer short tables over repeated path/link lists
- Include exact snapshot time when writing job status

Do **not** include these unless the user explicitly asks:

- canceled-job history
- full submission history
- archived YAML paths / ledger paths
- long workflow narration
- log dumps / raw JSON
- WIP placeholder templates
- background analysis unrelated to the current experiment record

If unsure, ask a short question before adding extra detail.

## Modes

Choose one mode before writing.

- `create-minimal` (default): create a new doc with purpose + config/git + active jobs + next actions
- `append-status`: append a short status snapshot (timestamp + jobs table delta)
- `append-result`: append metrics/checkpoint/conclusion only
- `finalize-summary`: write a compact final outcome section (what worked, what failed, next decision)

Optional expansions (only when requested):

- `include_history`
- `include_submit_paths`
- `include_logs`
- `full_mode`

## Required Inputs

Collect only what is needed for the chosen mode.

For `create-minimal`:

- destination `wiki_node` (or explicit `folder_token` / `wiki_space`)
- document title
- experiment purpose (1-3 bullets)
- active job facts (task_id, queue, status, start time)
- key config/git facts (commit, branch, config path) if relevant

For updates:

- target `doc_id`
- mode
- new facts to append (status, metrics, checkpoint, conclusion)

## Workflow

1. Confirm destination and mode.
2. Gather exact facts (task IDs, statuses, timestamps, commit hash, config path).
3. Draft minimal Markdown using the templates below.
4. Create/update the Feishu doc using the Feishu MCP tools.
5. Return the doc URL and a one-line summary of what was written.

Prefer Feishu operations:

- New doc: `mcp__feishu-mcp__create-doc`
- Update doc: `mcp__feishu-mcp__update-doc`
- Read existing doc before patching: `mcp__feishu-mcp__fetch-doc`

## Minimal Templates

### `create-minimal`

```markdown
## Purpose
- <1-3 bullets>

## Config
| Item | Value |
| --- | --- |
| Repo | `mmdet3d` |
| Branch | `feature/...` |
| Commit | `abc12345` |
| Config | `projects/...py` |

## Jobs (Snapshot: 2026-02-26 15:11:43 +0800)
| task_id | queue | status | start |
| --- | --- | --- | --- |
| `t-...` | Normal | Queue | `2026-...` |

## Next
- <1-3 bullets>
```

### `append-status`

Append only a compact snapshot.

```markdown
## Status Update (2026-02-26 18:30:00 +0800)
| task_id | queue | status | note |
| --- | --- | --- | --- |
| `t-...` | Normal | Running | `worker_0 started` |
```

### `append-result`

```markdown
## Result Update
| Metric | Value | Note |
| --- | --- | --- |
| mAP | 0.123 | val set |
| Checkpoint | `epoch_24.pth` | selected |

Conclusion:
- <1-2 bullets>
```

## Feishu-Specific Notes

- If the user provides a reference Feishu page, mirror the high-level structure only; do not copy verbose sections by default.
- If the user asks to "move" a doc to another wiki node, create a new doc under the target node and optionally add a short comment/link on the old doc.
- Use callouts sparingly (only for one-line reminders/risks).

## Anti-Patterns

Avoid these unless requested:

- writing long narrative postmortems for a simple experiment record
- duplicating local file paths, archived snapshots, and ledger files in multiple sections
- dumping CLI output into the doc
- adding placeholder sections that the user did not ask for
