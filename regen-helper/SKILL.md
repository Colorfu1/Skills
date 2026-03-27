---
name: Regen-helper
description: Help run regen cases inside docker container `mipilot_l3_omd_etxp`, copy `/MCAP/tools/*` into `/mipilot_root`, build `/tmp/mipilot_whole`, optionally enable `LidarBboxDetectionPreprocessUnit` debug saving under `/MCAP/g_npy/...`, and run `multi_regen.sh`. Always ask for `start_ts` and `end_ts` before regen when debug save is requested, and prefer saved logs plus compact status checks over streaming the full regen output.
---

# Regen Helper

Use this skill for the user's local regen workflow inside docker container `mipilot_l3_omd_etxp`.

## What This Skill Owns

- regen runs must happen inside docker
- source tools/data live under `/MCAP`
- runtime work dir is `/mipilot_root`
- initialize the container shell with `source ~/.bashrc` semantics before event lookup or regen; plain `bash -lc` can miss the `ad_cloud` environment
- `/MCAP/tools/*` must be copied into `/mipilot_root` before running
- the execute folder is `/tmp/mipilot_whole`
- build from `/mipilot_root` with `bash mipilot/modules/L3/scripts/build_l3_to_tmp.sh`
- `multi_regen.sh` is `/MCAP/tools/multi_regen.sh`, but it must be run from `/mipilot_root` after the tool copy because it uses relative paths like `regen.sh` and `tools/get_event_id.py`

## Required User Prompt

If the user wants to save debug data from `LidarBboxDetectionPreprocessUnit`, ask for:

- `start_ts`
- `end_ts`

Do this before regen. Do not guess or reuse old timestamps silently.

Also confirm or infer:

- `data_ids` for `multi_regen.sh`
- download directory
- output directory
- debug save directory, usually `/MCAP/g_npy/<case-or-ticket>/`

## Config To Patch

Patch this file inside the container after the build step and before regen:

- `/tmp/mipilot_whole/conf/L3/l3lpp/config/perception_module/lidar_perception.yaml`

Update the first `LidarBboxDetectionPreprocessUnit` block to:

```yaml
debug_mode: true
debug_mode_path: "/MCAP/g_npy/<target>/"
debug_start_ts: <start_ts>
debug_end_ts: <end_ts>
```

Create `debug_mode_path` first.

Do not edit unrelated debug blocks such as `LidarMirrorPointsUnit`, `LidarSegVizUnit`, or `LidarSegCreateSegProto`.

## Workflow

1. Gather required inputs.
2. If debug saving is requested, ask for `start_ts` and `end_ts`.
3. Run the helper script:
   - `scripts/run_regen_in_docker.sh`
4. Prefer this script form:

```bash
~/.codex/skills/regen-helper/scripts/run_regen_in_docker.sh \
  --data-ids "<id1,id2>" \
  --download-dir "/MCAP/<download-dir>" \
  --output-dir "/MCAP/<output-dir>" \
  --regen-log "/tmp/regen_<case>.log" \
  --debug-save-dir "/MCAP/g_npy/<ticket>/" \
  --start-ts "<start_ts>" \
  --end-ts "<end_ts>"
```

If debug saving is not needed, omit the debug flags.

## Log Discipline

- Never stream the full regen log into the conversation by default.
- Always redirect `multi_regen.sh` stdout/stderr into a container log file.
- Monitor progress with compact checks:
  - process still alive or exited
  - output file exists and size is stable or still growing
  - success markers such as `Successfully processed ID` and `All records have been processed`
- If the run looks wrong, use targeted `grep` against the saved log for:
  - `Failed to get data_id`
  - `Failed to process data`
  - `Traceback`
  - `IdentifyException`
  - `ERROR|Error|Exception`
- Only fall back to a short tail of the log if the targeted grep did not explain the failure.

## Token Budget

- Default to the shortest useful reply.
- During a healthy run, do not send repeated progress updates unless blocked or the user asks.
- Avoid repeating build details, shell warnings, config snippets, or file samples unless needed to explain a problem.
- If inputs are complete, start the run directly after the safety check for an existing debug directory.
- If debug saving is requested and the directory is empty, do not pause for an extra confirmation.
- If something fails or looks suspicious, then provide a compact diagnosis.

## Expected Results

- regen results come from `multi_regen.sh` output
- saved debug data is written during regen into `debug_mode_path`
- typical regen output file lands under `<output_dir>/<case-id>/regen_<event_id>.mcap`

After the run, summarize:

- one short line or one short paragraph by default
- include only:
  - case id
  - success or failure
  - output mcap path and size
  - debug save dir and file count when enabled
  - log file path
- do not include the exact command, build recap, config recap, or sample file listing unless the user asks or the run failed

## Safety Rules

- treat docker exec, build, config patch, and regen as state-changing operations
- if the debug save directory already contains files and the user did not ask to reuse it, warn before continuing
- patch only the first `LidarBboxDetectionPreprocessUnit` block
- do not overwrite other yaml fields
- if event lookup fails, verify the command used shell init equivalent to `source ~/.bashrc`; do not assume plain `bash -lc` is enough
- if docker access is sandbox-blocked, request escalation instead of falling back to a fake dry run

## References

- helper script: `scripts/run_regen_in_docker.sh`
- UI metadata: `agents/openai.yaml`
