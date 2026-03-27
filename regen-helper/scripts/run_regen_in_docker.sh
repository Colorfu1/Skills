#!/usr/bin/env bash
set -euo pipefail

CONTAINER="mipilot_l3_omd_etxp"
TOOLS_DIR="/MCAP/tools"
WORKDIR="/mipilot_root"
BUILD_SCRIPT="mipilot/modules/L3/scripts/build_l3_to_tmp.sh"
EXEC_DIR="/tmp/mipilot_whole"
LIDAR_CFG="$EXEC_DIR/conf/L3/l3lpp/config/perception_module/lidar_perception.yaml"

DATA_IDS=""
DOWNLOAD_DIR=""
OUTPUT_DIR=""
DEBUG_SAVE_DIR=""
START_TS=""
END_TS=""
REGEN_LOG=""
PID_FILE=""
STATUS_FILE=""
POLL_SECONDS=5
SKIP_BUILD=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  run_regen_in_docker.sh --data-ids "<id1,id2>" --download-dir <dir> --output-dir <dir> [options]

Options:
  --container <name>         Docker container name. Default: mipilot_l3_omd_etxp
  --data-ids <csv>           Comma-separated data ids for multi_regen.sh
  --download-dir <dir>       Download directory passed to multi_regen.sh
  --output-dir <dir>         Output directory passed to multi_regen.sh
  --regen-log <path>         Container log path for multi_regen.sh output
  --pid-file <path>          Container pid file for the launched regen process
  --poll-seconds <n>         Poll interval while waiting for regen completion. Default: 5
  --debug-save-dir <dir>     Debug output directory, for example /MCAP/g_npy/ADLSVC-185387/
  --start-ts <ts>            Required when --debug-save-dir is set
  --end-ts <ts>              Required when --debug-save-dir is set
  --skip-build               Skip build_l3_to_tmp.sh
  --dry-run                  Print docker commands without executing
  -h, --help                 Show this help
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

shell_quote() {
  printf "%q" "$1"
}

run_in_container() {
  local script="$1"
  if (( DRY_RUN )); then
    printf 'docker exec %s bash -lc %s\n' "$(shell_quote "$CONTAINER")" "$(shell_quote "export PS1=codex; source ~/.bashrc >/dev/null 2>&1 || true; $script")"
  else
    docker exec "$CONTAINER" bash -lc "export PS1=codex; source ~/.bashrc >/dev/null 2>&1 || true; $script"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      [[ $# -ge 2 ]] || die "--container requires a value"
      CONTAINER="$2"
      shift 2
      ;;
    --data-ids)
      [[ $# -ge 2 ]] || die "--data-ids requires a value"
      DATA_IDS="$2"
      shift 2
      ;;
    --download-dir)
      [[ $# -ge 2 ]] || die "--download-dir requires a value"
      DOWNLOAD_DIR="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --regen-log)
      [[ $# -ge 2 ]] || die "--regen-log requires a value"
      REGEN_LOG="$2"
      shift 2
      ;;
    --pid-file)
      [[ $# -ge 2 ]] || die "--pid-file requires a value"
      PID_FILE="$2"
      shift 2
      ;;
    --poll-seconds)
      [[ $# -ge 2 ]] || die "--poll-seconds requires a value"
      POLL_SECONDS="$2"
      shift 2
      ;;
    --debug-save-dir)
      [[ $# -ge 2 ]] || die "--debug-save-dir requires a value"
      DEBUG_SAVE_DIR="$2"
      shift 2
      ;;
    --start-ts)
      [[ $# -ge 2 ]] || die "--start-ts requires a value"
      START_TS="$2"
      shift 2
      ;;
    --end-ts)
      [[ $# -ge 2 ]] || die "--end-ts requires a value"
      END_TS="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_cmd docker

[[ -n "$DATA_IDS" ]] || die "--data-ids is required"
[[ -n "$DOWNLOAD_DIR" ]] || die "--download-dir is required"
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
[[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || die "--poll-seconds must be an integer"

if [[ -n "$DEBUG_SAVE_DIR" || -n "$START_TS" || -n "$END_TS" ]]; then
  [[ -n "$DEBUG_SAVE_DIR" ]] || die "--debug-save-dir is required when debug timestamps are set"
  [[ -n "$START_TS" ]] || die "--start-ts is required when --debug-save-dir is set"
  [[ -n "$END_TS" ]] || die "--end-ts is required when --debug-save-dir is set"
fi

FIRST_ID="${DATA_IDS%%,*}"
STAMP="$(date +%Y%m%d_%H%M%S)"
SAFE_FIRST_ID="${FIRST_ID//[^A-Za-z0-9_.-]/_}"
REGEN_LOG="${REGEN_LOG:-/tmp/regen_${SAFE_FIRST_ID}_${STAMP}.log}"
PID_FILE="${PID_FILE:-/tmp/regen_${SAFE_FIRST_ID}_${STAMP}.pid}"
STATUS_FILE="${STATUS_FILE:-${PID_FILE}.status}"

run_in_container "set -euo pipefail; test -d /MCAP; test -d $WORKDIR; test -d $TOOLS_DIR"

TOOLS_Q=$(shell_quote "$TOOLS_DIR")
WORKDIR_Q=$(shell_quote "$WORKDIR")
BUILD_SCRIPT_Q=$(shell_quote "$BUILD_SCRIPT")
LIDAR_CFG_Q=$(shell_quote "$LIDAR_CFG")
DATA_IDS_Q=$(shell_quote "$DATA_IDS")
DOWNLOAD_DIR_Q=$(shell_quote "$DOWNLOAD_DIR")
OUTPUT_DIR_Q=$(shell_quote "$OUTPUT_DIR")
REGEN_LOG_Q=$(shell_quote "$REGEN_LOG")
PID_FILE_Q=$(shell_quote "$PID_FILE")
STATUS_FILE_Q=$(shell_quote "$STATUS_FILE")

echo "Syncing /MCAP/tools into $WORKDIR inside $CONTAINER"
run_in_container "set -euo pipefail; mkdir -p $WORKDIR_Q; cp -rf $TOOLS_Q/. $WORKDIR_Q/"

if (( ! SKIP_BUILD )); then
  echo "Building $EXEC_DIR from $WORKDIR"
  run_in_container "set -euo pipefail; cd $WORKDIR_Q; bash $BUILD_SCRIPT_Q; test -f $LIDAR_CFG_Q"
else
  echo "Skipping build step"
  run_in_container "set -euo pipefail; test -f $LIDAR_CFG_Q"
fi

if [[ -n "$DEBUG_SAVE_DIR" ]]; then
  DEBUG_SAVE_DIR_Q=$(shell_quote "$DEBUG_SAVE_DIR")
  echo "Preparing debug output dir $DEBUG_SAVE_DIR"
  run_in_container "set -euo pipefail; mkdir -p $DEBUG_SAVE_DIR_Q"

  if (( DRY_RUN )); then
    cat <<EOF
Would patch:
  container: $CONTAINER
  config: $LIDAR_CFG
  debug_mode: true
  debug_mode_path: $DEBUG_SAVE_DIR
  debug_start_ts: $START_TS
  debug_end_ts: $END_TS
EOF
  else
    docker exec -i "$CONTAINER" python3 - "$LIDAR_CFG" "$DEBUG_SAVE_DIR" "$START_TS" "$END_TS" <<'PY'
import json
import pathlib
import re
import sys

cfg_path = pathlib.Path(sys.argv[1])
debug_path = sys.argv[2]
start_ts = sys.argv[3]
end_ts = sys.argv[4]

text = cfg_path.read_text()
block_pattern = re.compile(
    r"(?ms)(^- LidarBboxDetectionPreprocessUnit:\s*\{\n)(.*?)(^\})",
)
match = block_pattern.search(text)
if not match:
    raise SystemExit("Could not find LidarBboxDetectionPreprocessUnit block")

body = match.group(2)

def replace_once(src: str, key: str, value: str) -> str:
    pattern = re.compile(rf"(?m)^(\s*{re.escape(key)}:\s*).*,\s*$")
    if not pattern.search(src):
        raise SystemExit(f"Could not find key in target block: {key}")
    return pattern.sub(lambda m: f"{m.group(1)}{value},", src, count=1)

body = replace_once(body, "debug_mode", "true")
body = replace_once(body, "debug_mode_path", json.dumps(debug_path))
body = replace_once(body, "debug_start_ts", start_ts)
body = replace_once(body, "debug_end_ts", end_ts)

updated = text[:match.start(2)] + body + text[match.end(2):]
backup_path = cfg_path.with_suffix(cfg_path.suffix + ".bak")
backup_path.write_text(text)
cfg_path.write_text(updated)
PY
  fi

  echo "Effective preprocess debug config:"
  run_in_container "set -euo pipefail; sed -n '28,42p' $LIDAR_CFG_Q"
fi

if (( DRY_RUN )); then
  echo "Would run multi_regen.sh in background with log capture"
  echo "  log file: $REGEN_LOG"
  echo "  pid file: $PID_FILE"
  echo "  status file: $STATUS_FILE"
else
  echo "Launching multi_regen.sh with saved log"
  run_in_container "set -euo pipefail; cd $WORKDIR_Q; mkdir -p \$(dirname $REGEN_LOG_Q) \$(dirname $PID_FILE_Q) \$(dirname $STATUS_FILE_Q); rm -f $PID_FILE_Q $STATUS_FILE_Q; nohup bash -lc 'bash multi_regen.sh $DATA_IDS_Q $DOWNLOAD_DIR_Q $OUTPUT_DIR_Q > $REGEN_LOG_Q 2>&1; printf \"%s\n\" \"\$?\" > $STATUS_FILE_Q' >/dev/null 2>&1 & pid=\$!; printf '%s\n' \"\$pid\" > $PID_FILE_Q; printf 'pid=%s\nlog=%s\nstatus=%s\n' \"\$pid\" $REGEN_LOG_Q $STATUS_FILE_Q"

  while true; do
    if run_in_container "set -euo pipefail; test -f $PID_FILE_Q; pid=\$(cat $PID_FILE_Q); kill -0 \"\$pid\" 2>/dev/null"; then
      echo "Regen still running. log=$REGEN_LOG pid=$(run_in_container "set -euo pipefail; cat $PID_FILE_Q")"
      run_in_container "set -euo pipefail; find $OUTPUT_DIR_Q -maxdepth 2 -type f -name 'regen_*.mcap' -printf '%T@ %p %s\n' 2>/dev/null | sort -nr | head -n 1 || true"
      sleep "$POLL_SECONDS"
      continue
    fi
    break
  done

  echo "Regen process exited. log=$REGEN_LOG"
  run_in_container "set -euo pipefail; test -f $STATUS_FILE_Q && printf 'exit_status=%s\n' \"\$(cat $STATUS_FILE_Q)\" || printf 'exit_status=unknown\n'"
  run_in_container "set -euo pipefail; grep -nE 'Successfully processed ID|All records have been processed|Failed to get data_id|Failed to process data|Traceback|IdentifyException|ERROR|Error|Exception' $REGEN_LOG_Q | tail -n 40 || true"
  run_in_container "set -euo pipefail; find $OUTPUT_DIR_Q -maxdepth 2 -type f -name 'regen_*.mcap' -printf '%T@ %p %s\n' 2>/dev/null | sort -nr | head -n 5 || true"
fi

if [[ -n "$DEBUG_SAVE_DIR" ]]; then
  echo "Saved files under $DEBUG_SAVE_DIR:"
  run_in_container "set -euo pipefail; find $DEBUG_SAVE_DIR_Q -maxdepth 2 -type f | sort | sed -n '1,200p'"
fi
