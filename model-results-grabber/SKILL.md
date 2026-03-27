---
name: model-results-grabber
description: Retrieve and summarize model training/validation results from submitted jobs, especially Volc ML Platform (`volc ml_task`) runs and MMDet/MMDet3D-style training outputs. Use when Codex needs to fetch job status, read logs, locate metrics (loss, mAP/NDS, validation scores), collect checkpoint/eval artifacts, or produce a concise training result summary.
---

# Model Results Grabber

## Overview

Use this skill to grab training and validation results from running or finished jobs.

Prioritize read-only inspection first: query job status, fetch logs, identify the result source (stdout logs vs. work-dir files), then extract metrics into a concise summary.

## Workflow

### 1. Identify the Result Source

Collect:

- `task_id` (preferred)
- framework/project type (for example MMDet3D / custom PyTorch)
- target result type:
  - training progress (loss, lr, iter/epoch)
  - validation metrics (mAP, NDS, accuracy, etc.)
  - final checkpoint path / best checkpoint
- whether the job is still running or finished

If no `task_id` is given, use `job-manager` workflow to find the right job first (default workspace filter may be `Description == "owner-tag"`).

### 2. Check Job State First

Before grabbing metrics, query task status:

- `volc ml_task get --id <task_id> --output json`

Interpret state:

- `Queue` / `Staging`: no meaningful training metrics yet
- `Running`: fetch live logs
- `Success` / `Failed` / `Killed`: fetch final logs and artifact paths

### 3. Get Logs or Artifacts

Prefer the smallest source that contains the needed result:

- Live or recent stdout/stderr: `volc ml_task logs -t <task_id> -i worker_0 -l <N>`
- Follow live logs: `volc ml_task logs -t <task_id> -i worker_0 -f`
- If needed, export config/code for inspection: `volc ml_task export -t <task_id> --config`

For distributed jobs, `worker_0` usually has enough training/validation summaries. Only query other workers when debugging hangs or worker-specific failures.

For MMDet/MMDet3D training-stage provenance (for example "which pretrain model did this run use?"):

- Prefer the saved config copy in the remote model/work directory first (often `*.py`, sometimes `*.config`)
- Search for `load_from` and `resume_from`
- If no dumped config file exists, grep the earliest training logs for `load_from = ...`
- Report the full checkpoint path (for example `.../run_name/epoch_24.pth`), not only the filename
- Persist resolved provenance into the local snapshot `summary.json` under a top-level `provenance` object so later local reprints do not require SSH

### 4. Extract Metrics

Look for:

- Training metrics: `loss`, `lr`, `time`, `data_time`, `eta`, `iter`, `epoch`
- Validation/eval metrics: `mAP`, `NDS`, `AP`, `AUC`, `acc`, task-specific scores
- Checkpoint events: `Saving checkpoint`, `best`, `epoch_xx.pth`
- Final result summaries near the end of logs

For MMDet/MMDet3D-style logs, search for:

- validation blocks after epoch boundaries
- `bbox_mAP`, `mAP`, `NDS`, class-wise AP tables
- eval scripts invoked in `Entrypoint` (for example under `./projects/.../evaluation/...`)

When metrics appear multiple times, report:

1. latest value
2. best value (if clearly logged)
3. timestamp/epoch/iter where it occurred

For FS results from `seg_table.txt`, report per-class metrics by default:

- `Precision`
- `Recall`
- `F1`
- `mIoU` (compute from total columns as `TP / (TP + FP + FN)` when not explicitly provided)

### 5. Return a Clear Summary

Provide a compact result summary:

1. Task status (`Running`/`Success`/etc.)
2. Source used (`worker_0` logs, exported config, artifact path)
3. Training progress snapshot (latest loss/epoch/iter)
4. Validation metrics (latest and best)
5. Pretrain / initialization checkpoint (`load_from`, if available; report full path and indicate whether it is a different run)
6. Checkpoint/result paths (if visible in logs)
7. Next command (optional: more logs, follow logs, cancel, etc.)

Presentation defaults for this workspace/user preference:

- Use a pretty, readable format by default (tables and clear sections, not raw dumps)
- Include FS per-class `Precision`, `Recall`, `F1`, and `mIoU` in every result summary when `seg_table.txt` is available
- Always include a `Pretrain / Provenance` section in model result summaries (even when unresolved)
- Always include pretrain provenance (`load_from`) in model result summaries when it can be found from remote saved config/logs
- If provenance is not resolved this turn, print `verified=false` and a short reason instead of omitting the section

## Volc Commands (Result Retrieval)

Common commands:

- `volc ml_task get --id <task_id> --output json`
- `volc ml_task logs -t <task_id> -i worker_0 -l 200`
- `volc ml_task logs -t <task_id> -i worker_0 -f`
- `volc ml_task instance list -i <task_id> --output json`
- `volc ml_task export -t <task_id> --config`
- `python scripts/enrich_model_results_provenance.py <snapshot_dir_or_model> [--epoch <N>]` (persist `load_from` / `resume_from` into `summary.json`)

Use lowercase `json` for `--output json`.

Remote pretrain provenance lookup (workspace pattern, read-only):

```bash
# 1) Inspect saved config copy in remote model dir (prefer *.py, also check *.config)
ssh -p <port> <user>@<host> \
  'WD=/remote/store/<project>/pth_dir/<model_run>; \
   find "$WD" -maxdepth 2 -type f \( -name "*.py" -o -name "*.config" \) | sort'

# 2) Extract load_from / resume_from from saved config copy
ssh -p <port> <user>@<host> \
  'CFG=/remote/store/<project>/pth_dir/<model_run>/<config_name>.py; \
   grep -nE "^(load_from|resume_from)\s*=|load_from|resume_from" "$CFG"'

# 3) Fallback: grep earliest logs in the same dir
ssh -p <port> <user>@<host> \
  'WD=/remote/store/<project>/pth_dir/<model_run>; \
   grep -inE "load_from|resume_from|load-from|resume from" "$WD"/*.log | sed -n "1,80p"'
```

Persist provenance into the local snapshot after remote lookup (recommended):

```bash
python scripts/enrich_model_results_provenance.py data/model_eval_results/<model_name>/epoch_<N>
```

## MMDet/MMDet3D Notes

Typical result locations/patterns:

- stdout logs contain periodic training metrics and eval summaries
- work directory paths often appear in command args (`--work-dir ...`)
- checkpoints often named like `epoch_XX.pth`
- eval scripts may run after training in the same `Entrypoint`, so validation results can appear later in the same log stream

Training config provenance in this workspace:

- Remote training output dirs often contain a saved config copy named like `<config_name>.py`
- Do not assume a `*.config` file exists; check `*.py` too
- `load_from` usually means pretrained/warm-start checkpoint from a different run
- `resume_from` means resume the same run state (if non-`None`)

If the `Entrypoint` includes both train and eval commands, separate the summary into:

- Training phase results
- Validation/Test phase results

## Workspace Validation Set Mapping (Remember This)

For this workspace/project, use the following result sources by default:

### OD (3 validation sets, read from top-level `epoch_xx/*.html`)

- `val_od_89k` -> `det_det_val_od_89k.html`
- `val_seg_2w` -> `det_det_val_seg_2w.html`
- `val_seg` -> `det_det_val_seg.html`

Grab OD results from the corresponding `*.html` report files.

Preferred OD summary fields:

- `AP@IoU=0.5or0.1` (class-wise + overall)
- Precision table (`overall` column across score thresholds)
- Recall table (`overall` column across score thresholds)

### FS (1 validation set, read from text table)

- FS results -> `seg_table.txt`

Preferred FS summary fields:

- macro summary: average `mIoU`, average `F1`, number of classes
- per-class table: `Precision`, `Recall`, `F1`, `mIoU`

### Flow (1 validation set, read from text table)

- Flow results -> `flow_table.txt`

When `seg_table.txt` / `flow_table.txt` live under an `eval/` directory with many files, avoid broad directory scans. Search only for these exact filenames.

## Safety Rules

- Do not modify or cancel tasks when the user only asks for results.
- Prefer read-only commands (`get`, `logs`, `instance list`, `export --config`).
- If logs are huge, fetch a limited tail first (`-l 100` or `-l 200`) and widen only if needed.
- If sandbox networking blocks Volc API, use approved host/outside-sandbox execution when available.
- Attempt SSH-based remote inspection directly (for example `ssh -p <port> <user>@<host> ...`); if the SSH tunnel is unavailable/broken, report the SSH error and continue with non-SSH fallbacks when possible.
- Avoid broad scans of large `eval/` directories in this workspace; read only the exact known result files (`*.html`, `seg_table.txt`, `flow_table.txt`).

## References

- Use `job-manager` for task discovery/cancel flows
- Use workspace `ml_task.md` for `volc ml_task` command patterns
