---
name: l3-data-script-runner
description: Safely prepare and run repository scripts under local `./data` on the corresponding remote repo path `/remote/repo/data`. Use when Codex needs to (1) fix or patch local `data/*` scripts, (2) commit/push changes to a Git remote, (3) SSH to the target host and update the remote repo, (4) show the exact remote launch command and ask for confirmation, and (5) run the script in the background with `nohup` (or equivalent) and capture logs/PID.
---

# L3 Data Script Runner

## Overview

Use this skill for the specific local-to-remote workflow where a script under `./data` in the current repo maps to the remote repo under:

- `/remote/repo/data`

Treat this as a state-changing workflow. Always show exact commands and ask for explicit confirmation before:

- local `git add` / `git commit` / `git push`
- remote `git pull` (or other repo updates)
- remote background launch (`nohup`, `setsid`, `tmux`, etc.)

## Path Mapping

Assume:

- local repo root = `git rev-parse --show-toplevel`
- remote repo root = `/remote/repo`

Mapping rule:

- local `data/foo.py` -> remote `/remote/repo/data/foo.py`

Reject launches for paths outside local `data/` unless the user explicitly asks for a different mapping.

## Workflow

### 1. Inspect and Patch Locally

1. Identify the target script and arguments (for example `data/my_job.py --cfg data/config/x.yaml`).
2. Review related files only as needed (target script, imported helpers, config files).
3. Patch locally if needed.
4. Run a small local smoke check when practical (syntax check, `--help`, or dry-run mode).

Prefer minimal edits. Do not change unrelated files.

### 2. Prepare Git Update (Local)

Before pushing, show exact commands and ask for confirmation.

Typical command sequence:

```bash
git status --short
git add data/<script>.py [other-needed-files]
git commit -m "<clear message>"
git push
```

If the branch is unclear, inspect `git branch --show-current` and `git remote -v` first.

### 3. Update Remote Repo

Use SSH to the existing tunnel target:

- host: `<user>@<host>`
- port: `<port>`

Default remote update command (show first, then confirm):

```bash
ssh -p <port> <user>@<host> 'cd /remote/repo && git status --short && git pull --ff-only'
```

If `git pull --ff-only` fails, stop and show the error. Do not use destructive recovery (`reset --hard`) unless the user explicitly approves.

### 4. Build the Launch Command and Confirm

Use `scripts/build_remote_data_run_cmd.sh` in this skill to print the exact commands.

Example:

```bash
~/.codex/skills/l3-data-script-runner/scripts/build_remote_data_run_cmd.sh \
  --script data/my_job.py -- --cfg data/config/x.yaml --workers 8
```

The helper prints:

- remote repo update command
- remote `nohup` launch command
- log file path
- PID file path

Show the generated launch command to the user and ask for confirmation before execution.

### 5. Launch in Background and Return Tracking Info

After confirmation, run the printed remote launch command.

Return:

1. exact command executed
2. remote log path
3. remote PID file path
4. PID (if available)
5. suggested follow-up command to tail logs

Example follow-up:

```bash
ssh -p <port> <user>@<host> 'tail -f /remote/repo/data/nohup_logs/<name>.log'
```

## Safety Rules

- Always confirm state-changing commands before running them.
- Prefer `git pull --ff-only` on remote; avoid merge commits unless the user requests them.
- Keep stdout/stderr redirected to a log file for background runs.
- Store a PID file when launching with `nohup`.
- For `mi_pyvista` visualization workflows, prefer foreground interactive runs (no `nohup`) unless the user explicitly asks for background mode.
- For `mi_pyvista` visualization workflows, always create a fresh remote `script` log and always open an extra local terminal to `tail -n +1 -F` that exact log while the visualization is running.
- If the script writes outputs, ask the user where outputs should go if not obvious from arguments.
- If the user says "just prepare command", stop after printing commands.

## Known User Workflows

The following user files/workflows are known entry points for this skill and can be referenced directly in future turns:

- `data/run_val_centerpoint_seg.sh`: model evaluation workflow (inference and summary).
- `data/raw_L3_OD_anno_to_pkl.py`: create OD data and save final data files on the remote machine.
- `data/raw_L3_FS_anno_to_pkl.py`: create FS data and save final data files on the remote machine.
- `data/raw_anno_split_train_and_val_bin.py`: split the full dataset into train/val using compact clips.
- `data/mi_pyvista_vis_multi.py`: visualization client on the remote machine; use the validated workflow below (local server first, then remote client in foreground, no `nohup`).
- `data/config/generate_training_pkl.yaml`: collect required data and generate a training PKL.

For `mi_pyvista` workflows, treat the local server command as a separate explicit step because it runs outside the standard local `./data` -> remote `/remote/repo/data` path mapping.

## mi_pyvista Visualization (Validated Workflow)

Use this exact sequence for `mi_pyvista` visualization unless the user asks otherwise.

### Start Order (Required)

1. Start the local server first in a local shell (outside the repo mapping):

```bash
conda activate mi_vista
python /home/mi/codes/data/mi_pyvista_vis.py --server
```

2. Confirm the local server is listening before starting the remote client:

```bash
ss -ltnp | rg ':9998\b'
```

3. Start the remote client in the foreground (no `nohup`) from the remote `data/` directory with `script` and a fresh timestamped log file:

```bash
ssh -t -p <port> <user>@<host> '
  cd /remote/repo/data &&
  LOG=/tmp/mi_pyvista_vis_multi_$(date +%Y%m%d_%H%M%S).session.log &&
  echo REMOTE_LOG=$LOG &&
  script -qefc "python -u mi_pyvista_vis_multi.py" "$LOG"
'
```

4. Always open an extra local terminal to show the full remote log from the beginning and follow it:

```bash
gnome-terminal -- bash -lc \
  "ssh -t -p <port> <user>@<host> 'tail -n +1 -F /tmp/mi_pyvista_vis_multi_<timestamp>.session.log'; exec bash"
```

### Important Behavior / Pitfalls

- `data/mi_pyvista_vis_multi.py` parses CLI flags like `--client`, `--server`, `--pkl_file`, and `--eval_dir`, but the current script behavior is driven by `data/config/mi_pyvista_vis_multi.yaml`. Check the YAML for the actual PKL/eval target being browsed.
- Run `mi_pyvista_vis_multi.py` from the remote `data/` directory so relative config path `config/mi_pyvista_vis_multi.yaml` resolves correctly.
- Do not trust process existence alone for local server health. A running `mi_pyvista_vis.py --server` process can be unhealthy. Always verify listener state with `ss -ltnp | rg ':9998\\b'` and confirm it is bound to the expected IP/port before remote launch.
- If the remote client fails with `ConnectionRefusedError`, the local server is not listening on `10.189.141.246:9998` (or is not reachable).
- Local server startup depends on a working local environment that can import `ad_cloud`; the user-validated command is `conda activate mi_vista` before starting `/home/mi/codes/data/mi_pyvista_vis.py --server`.
- Non-interactive SSH launches may fail SDK initialization (`ad_cloud` identify/runtime errors) even when manual interactive SSH works. For visualization, prefer interactive `ssh -t` unless the user explicitly wants automation/background mode.
- Even with `ssh -t ... 'script -qefc "python -u mi_pyvista_vis_multi.py" ...'`, `ad_cloud` initialization may fail in some sessions. Fallback: open interactive remote shell first (`ssh -t -p <port> <user>@<host>`), then run the client command inside that shell.
- Reusing an old remote log file can mix stale failures with a healthy current run. Always create a fresh timestamped log path per restart (for example `/tmp/mi_pyvista_vis_multi_YYYYmmdd_HHMMSS.session.log`) and tail that exact file.
- Always verify the extra local tail terminal is attached to the same fresh log path printed as `REMOTE_LOG=...` in the remote client shell.
- Warning bursts like `Unrecognized server reply: . Still waiting!` are not enough to diagnose current state if logs are reused. Confirm current health from new-log signals such as `Target IP Port ... connected!` and periodic `Client sent ... bytes!`.

### Required Remote Log Capture (Whole Session)

For every `mi_pyvista` visualization run, capture full remote output with `script` and show it in an extra local tail terminal:

```bash
# Remote client window (foreground)
ssh -t -p <port> <user>@<host> '
  cd /remote/repo/data &&
  LOG=/tmp/mi_pyvista_vis_multi_$(date +%Y%m%d_%H%M%S).session.log &&
  echo REMOTE_LOG=$LOG &&
  script -qefc "python -u mi_pyvista_vis_multi.py" "$LOG"
'
```

```bash
# Extra log window (show full file + follow)
ssh -t -p <port> <user>@<host> 'tail -n +1 -F /tmp/mi_pyvista_vis_multi_<timestamp>.session.log'
```

If the user asks for a separate local terminal that shows remote logs, open one explicitly (for example with `gnome-terminal`) and run the remote `tail -n +1 -F` command inside it.

### Stop Order (Required)

If an extra remote log tail is running, stop in this order:

1. Remote visualization client (`Ctrl+C`)
2. Remote log tail (`Ctrl+C`)
3. Local server (`Ctrl+C`)

If the local server does not exit on `Ctrl+C`, terminate the local Python server process explicitly as a fallback.

## References

- Helper script: `scripts/build_remote_data_run_cmd.sh`
- Agents metadata: `agents/openai.yaml`
