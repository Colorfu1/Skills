---
name: todo
description: Manage a persistent future-job reminder list in a repo file (default `data/job_queue.yaml`) by adding, listing, updating, and deleting job records. Use when Codex needs to record jobs the user wants to do later, show TODOs, update status/notes, or clean up reminder entries. Do not use this skill to execute jobs; hand execution off to other skills such as `l3-data-script-runner`.
---

# Todo

## Overview

Use this skill to maintain a reminder/tracker file for future work, especially:

- `data/job_queue.yaml`

This skill manages records only. It does not decide which execution skill to use and should not store execution-tool capability metadata in the reminder file unless the user explicitly asks for that.

## Scope (and Non-Goals)

Do:

- Add reminder jobs
- Show filtered job lists (`todo`, `running`, high priority, etc.)
- Update status / notes / targets / hypotheses
- Delete reminder entries

Do not:

- Launch scripts, SSH, `git pull`, or `nohup` jobs (use `l3-data-script-runner` or another execution workflow when the user asks to run something)
- Mix "what skill/tool can run this" into the reminder list unless the user explicitly wants a separate field

## Default File

- `data/job_queue.yaml` (workspace-relative)

If the file is missing, create it with minimal structure:

- `version`
- `metadata`
- `checklist_templates` (optional but recommended)
- `jobs:`

## Common Operations

### 1. Show Jobs

Use the bundled helper:

```bash
~/.codex/skills/todo/scripts/job_queue_list.sh --file data/job_queue.yaml --status todo
```

Common filters:

- `--status todo`
- `--priority high`
- `--type analysis`
- `--id-substr compare-ft`
- `--format tsv`

If the helper is unavailable, use a small `awk` read-only parser or inspect with `rg`/`sed`.

### 2. Add a Job

When adding a reminder:

0. Only add a job when the user explicitly asks to create/add/record a TODO
0. Do not auto-create TODOs from inferred next steps or suggestions; ask first if tracking is desired
1. Pick a stable `id` (lowercase, hyphenated)
2. Preserve the user's wording for goals and notes
3. Add only fields that are known now; leave unknowns as `null` or omit optional fields

Minimum recommended fields for each job:

- `id`
- `name`
- `path`
- `type`
- `category`
- `purpose`
- `status`
- `priority`

For analysis/training jobs, include:

- `targets`
- `pre_knowledge` / `baseline_observations` / `questions_to_answer` when provided

### 3. Update a Job

Common updates:

- `status` (`todo` -> `running` -> `done`)
- `notes`
- `targets`
- `next_check`
- `log_path`
- `output_paths`

Use `apply_patch` for precise edits. Avoid reformatting unrelated entries.

### 4. Delete Job(s)

Delete by exact `id` only.

Workflow:

1. Find the entry with `rg -n '^  - id: <job-id>$' data/job_queue.yaml`
2. Show the matching ID(s) to the user if ambiguous
3. Remove the whole YAML block with `apply_patch`
4. Re-read the remaining TODO list to confirm

### 5. Summarize TODOs

Default output order:

1. `priority` (high -> medium -> low)
2. `id`

Show a compact table with:

- `ID`
- `Priority`
- `Type`
- `Name`
- `Path`

## Editing Rules

- Keep `data/job_queue.yaml` as a reminder list, not an execution-capability map
- Preserve YAML indentation and quoting style used in the file
- Do not reorder large sections unless the user asks
- Preserve `checklist_templates` entries unless explicitly changing them
- Preserve user-provided hypotheses/observations verbatim when possible

## References

- Helper script: `scripts/job_queue_list.sh`
- Typical data file: `data/job_queue.yaml`
- Execution handoff (when asked to run jobs): `l3-data-script-runner`
