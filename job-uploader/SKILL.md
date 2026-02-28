---
name: job-uploader
description: Prepare, validate, and submit job configuration files (especially YAML/JSON manifests) to a remote training/compute platform using CLI or HTTP APIs. Use when Codex needs to help upload or submit a job, fix upload errors, verify required fields/paths, or generate commands/scripts for job submission workflows.
---

# Job Uploader

## Overview

Use this skill to turn a job spec into a reliable submission workflow: inspect the config, run preflight checks, generate the upload/submit command, and troubleshoot common failures.

Prefer a cautious workflow: validate locally first, avoid mutating the user's config unless asked, and show the exact command before running it.

## Workflow

### 1. Gather Submission Context

Collect the minimum required details before proposing commands:

- Job config file path (`.yaml`, `.yml`, `.json`)
- Target platform (CLI name or API endpoint)
- Authentication method (env vars, token file, profile)
- Project/namespace/queue identifiers
- Required artifact paths (code package, dataset, checkpoints, storage mounts)

If the platform is unclear, inspect the repo and config first, then ask a short clarifying question only if needed.

### 2. Run Preflight Checks

Check the job config before upload/submission:

- Confirm the file exists and parses
- Confirm referenced local paths exist
- Confirm required fields are present for the target platform
- Check obvious typos in storage IDs, mount paths, image names, queue names, and regions
- Verify `TensorBoard`/artifact paths look writable and consistent with the job output path when present
- For Volc `ml_task` YAMLs, inspect `Entrypoint` and confirm it starts the intended codebase (for example `cd /mmdet3d` and scripts under `./tools` or `./projects`)

When editing is needed, patch the smallest possible section and explain the change.

### 3. Build the Submission Command

Prefer explicit, copyable commands. Show placeholders only when the exact value is unknown.

Common patterns:

- CLI submit: `platform-cli job submit -f job.yaml`
- CLI upload + submit: `platform-cli upload artifact ...` then `platform-cli job submit ...`
- API submit: `curl`/HTTP request with auth header and config payload

Volc ML Platform pattern (custom training):

- Remind prerequisites first:
  - `volc` CLI installed (or install: `sh -c "$(curl -fsSL https://ml-platform-public-examples-cn-beijing.tos-cn-beijing.volces.com/cli-binary/install.sh)" && export PATH=$HOME/.volc/bin:$PATH`)
  - AK/SK + region configured via `volc configure`
- Submit task config: `volc ml_task submit -c <user-task.yaml>`
- If creating a fresh run from an existing YAML, prefer overriding the task name on CLI: `volc ml_task submit -c <user-task.yaml> -n <new-task-name>`

When credentials are required, reference environment variables (for example, `API_TOKEN`) instead of embedding secrets.

### 4. Execute Safely (If Requested)

Before running commands that submit or modify remote state:

- Confirm the user wants execution, not just command generation
- For Volc submissions, show the exact `volc ml_task submit ...` command and ask for confirmation before the real submit
- Call out side effects (job creation, uploads, costs)
- Prefer dry-run/validate modes when the platform supports them
- If running inside a restricted sandbox that cannot reach the platform API, use an approved host/outside-sandbox terminal execution path when available

If execution fails, capture the exact error and continue with targeted troubleshooting.

### 5. Troubleshoot Submission Failures

Classify failures quickly:

- Auth/permission errors
- Invalid config schema/required fields missing
- Resource not found (queue/image/storage/dataset)
- Path or mount issues
- API/CLI version mismatch
- Network or timeout errors
- CLI not installed or PATH not set (`volc: command not found`)
- Sandbox/network restrictions (for example DNS/proxy blocked in sandbox while the user's local terminal works)

Propose the smallest fix, then retry only the necessary step.

## Output Style

Provide results in this order when helping with a submission:

1. Preflight findings (what is valid vs. what needs fixing)
2. Exact command(s) to run
3. Optional patch to the config file (if needed)
4. Next verification step (for example, how to check job status/logs)

For Volc submissions, include:

- A reminder to verify `volc configure` (AK/SK/region) before retrying auth failures
- The CLI submit output (task ID/status) and any immediate log/error text returned by `volc ml_task submit`
- By default, return submit result only after submit (for example `task_id`). Fetch status/logs only when the user explicitly asks.

## Examples

Typical requests that should trigger this skill:

- "Help me upload and submit this training job YAML"
- "Check why my job config fails to submit"
- "Generate the CLI command to submit this job file"
- "Fix the storage path in this job manifest and resubmit"
- "Use `volc ml_task submit -c ...` to submit this YAML and check the status"

## Volc ML Task Notes

When the user is submitting a Volc custom training task from a YAML:

1. Check environment readiness first (`volc` installed and `volc configure` completed).
2. Validate the YAML's `Entrypoint` carefully, especially `cd` target and script paths (for example, training scripts under `/mmdet3d`).
3. Show the exact submit command and ask for confirmation before executing.
4. Submit with `volc ml_task submit -c <yaml>` (or `-n <new-task-name>` if requested).
5. If sandbox networking blocks the API, run the submit on the host/outside-sandbox terminal after approval.
6. Return the submit result (success/error). Do not auto-fetch status/logs unless the user asks.
