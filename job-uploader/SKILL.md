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
- For repo-based jobs, remote sync target details (SSH host/user/port and remote repo path)

If the platform is unclear, inspect the repo and config first, then ask a short clarifying question only if needed.

### 2. Run Preflight Checks

Check the job config before upload/submission:

- Confirm the file exists and parses
- Confirm referenced local paths exist
- Confirm required fields are present for the target platform
- Check obvious typos in storage IDs, mount paths, image names, queue names, and regions
- Verify `TensorBoard`/artifact paths look writable and consistent with the job output path when present
- For Volc `ml_task` YAMLs, if user asks for `free-device`, verify `Preemptible: true` is set
- For Volc `ml_task` YAMLs, inspect `Entrypoint` and confirm it starts the intended codebase (for example `cd /mmdet3d` and scripts under `./tools` or `./projects`)
- For Volc `ml_task` YAMLs, do **not** keep `git pull` in `Entrypoint`; network to Git remote can fail inside task containers
- Enforce code sync order for repo-based runs: local commit/push first, then SSH to remote device and run `git pull --ff-only` before submit

When editing is needed, patch the smallest possible section and explain the change.

### 3. Build the Submission Command

Prefer explicit, copyable commands. Show placeholders only when the exact value is unknown.

Common patterns:

- CLI submit: `platform-cli job submit -f job.yaml`
- CLI upload + submit: `platform-cli upload artifact ...` then `platform-cli job submit ...`
- API submit: `curl`/HTTP request with auth header and config payload

Volc ML Platform pattern (custom training):

- Remind prerequisites first:
  - `volc` CLI installed (or install from the official Volc CLI guide for your environment)
  - AK/SK + region configured via `volc configure`
- For repo-sync workflows, run this sequence before submit:
  - `git push origin <branch>`
  - `ssh <user>@<host> -p <port> 'cd <remote_repo_path> && git pull --ff-only'`
  - Then `volc ml_task submit -c <user-task.yaml>`
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
- In-task Git network failures (for example `ssh: connect to host ... timed out` from `git pull`)
- CLI not installed or PATH not set (`volc: command not found`)
- Sandbox/network restrictions (for example DNS/proxy blocked in sandbox while the user's local terminal works)

Propose the smallest fix, then retry only the necessary step.

### 6. Register Experiment Placeholder

After a successful `volc ml_task submit`, if the job is a training experiment rather than an eval-only task:

1. Extract `work_dir` from `Entrypoint` (`--work-dir <path>`)
2. Extract the config `.py` path from `Entrypoint`
3. Extract `volc_task_id` from submit output
4. Call `/experiment-recorder placeholder <work_dir> --config <config_path> --task-id <volc_task_id>`
5. This creates a minimal `status: "submitted"` registry entry so later metric collection and lineage updates have a stable experiment record

Skip placeholder creation when:

- `Entrypoint` does not contain `--work-dir`
- The task is an evaluation job (`TaskName` starts with `eval-`, or `Entrypoint` uses `dist_test` / `test.py` instead of `dist_train` / `train.py`)

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
3. Remove/avoid `git pull` from `Entrypoint`; tasks should not depend on Git network access at runtime.
4. Sync code before submit: push local branch, SSH to remote device, and `git pull --ff-only` in the remote repo.
5. Show the exact submit command and ask for confirmation before executing.
6. Submit with `volc ml_task submit -c <yaml>` (or `-n <new-task-name>` if requested).
7. If sandbox networking blocks the API, run the submit on the host/outside-sandbox terminal after approval.
8. Return the submit result (success/error). Do not auto-fetch status/logs unless the user asks.
9. For `free-device` requests, set `Preemptible: true` (or submit with `--preemptible`). `RetryOptions.PolicySets` with `InstanceReclaimed` alone is not sufficient to make a task preemptible.

## Template Override Rules (owner-tag)

When the user asks to use template `/home/mi/codes/workspace/t-20260224114159-g8rmg.yaml`, treat it as a fixed template and only edit the requested fields below unless the user explicitly asks for more changes.

Allowed edits:

1. `Entrypoint` workdir folder token in path segments such as:
   - `mkdir .../pth_dir/<job_workdir>/`
   - `ln -s .../pth_dir/<job_workdir>/tf_logs`
   - `--work-dir .../pth_dir/<job_workdir>/`
2. `Entrypoint` training config path, e.g. `projects/flatformer/configs/<config>.py`
3. `Entrypoint` pretrained checkpoint path in `--load-from <ckpt_path>`
4. `ResourceQueueID`
5. `TaskRoleSpecs[].RoleReplicas`

`PolicySets` rule:

- Only when user explicitly asks for `"free-device"`:
  - add `"InstanceReclaimed"` into `RetryOptions.PolicySets`
  - set top-level `Preemptible: true` (or use CLI `--preemptible`)
- If user does not ask for `"free-device"`:
  - do not add `"InstanceReclaimed"`
  - do not force `Preemptible: true`
