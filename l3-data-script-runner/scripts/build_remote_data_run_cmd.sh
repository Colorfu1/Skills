#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-<user>@<host>}"
REMOTE_PORT="${REMOTE_PORT:-<port>}"
REMOTE_REPO="${REMOTE_REPO:-/remote/repo}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
MODE="full"
SCRIPT_PATH=""
SCRIPT_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  build_remote_data_run_cmd.sh --script data/<script>.py [--mode full|update|launch] [--python python3] [-- arg1 arg2 ...]

Examples:
  build_remote_data_run_cmd.sh --script data/job.py
  build_remote_data_run_cmd.sh --script data/job.py -- --cfg data/config/x.yaml --workers 8
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

quote_join() {
  local out=""
  local item
  for item in "$@"; do
    out+=$(printf '%q ' "$item")
  done
  printf '%s' "${out% }"
}

while (($#)); do
  case "$1" in
    --script)
      (($# >= 2)) || die "--script requires a value"
      SCRIPT_PATH="$2"
      shift 2
      ;;
    --mode)
      (($# >= 2)) || die "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    --python)
      (($# >= 2)) || die "--python requires a value"
      PYTHON_BIN="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      SCRIPT_ARGS=("$@")
      break
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$SCRIPT_PATH" ]] || die "missing --script"
[[ "$SCRIPT_PATH" == data/* ]] || die "--script must be under data/ (got: $SCRIPT_PATH)"
case "$MODE" in
  full|update|launch) ;;
  *) die "--mode must be one of: full, update, launch (got: $MODE)" ;;
esac

script_name="$(basename "$SCRIPT_PATH")"
script_stem="${script_name%.*}"
timestamp="$(date +%Y%m%d_%H%M%S)"

remote_script_path="$REMOTE_REPO/$SCRIPT_PATH"
remote_log_dir="$REMOTE_REPO/data/nohup_logs"
remote_log_path="$remote_log_dir/${script_stem}_${timestamp}.log"
remote_pid_path="${remote_log_path}.pid"

update_remote_cmd="cd $(printf '%q' "$REMOTE_REPO") && git status --short && git pull --ff-only"

python_cmd="$(quote_join "$PYTHON_BIN" "$remote_script_path" "${SCRIPT_ARGS[@]}")"
launch_remote_cmd="mkdir -p $(printf '%q' "$remote_log_dir") && nohup $python_cmd > $(printf '%q' "$remote_log_path") 2>&1 < /dev/null & echo \$! | tee $(printf '%q' "$remote_pid_path")"
tail_remote_cmd="tail -f $(printf '%q' "$remote_log_path")"

ssh_update_cmd="$(quote_join ssh -p "$REMOTE_PORT" "$REMOTE_HOST" "$update_remote_cmd")"
ssh_launch_cmd="$(quote_join ssh -p "$REMOTE_PORT" "$REMOTE_HOST" "$launch_remote_cmd")"
ssh_tail_cmd="$(quote_join ssh -p "$REMOTE_PORT" "$REMOTE_HOST" "$tail_remote_cmd")"

echo "REMOTE_REPO=$REMOTE_REPO"
echo "REMOTE_SCRIPT=$remote_script_path"
echo "REMOTE_LOG=$remote_log_path"
echo "REMOTE_PID_FILE=$remote_pid_path"
echo

if [[ "$MODE" == "full" || "$MODE" == "update" ]]; then
  echo "# Remote update command (show + confirm before running)"
  echo "$ssh_update_cmd"
  echo
fi

if [[ "$MODE" == "full" || "$MODE" == "launch" ]]; then
  echo "# Remote launch command (show + confirm before running)"
  echo "$ssh_launch_cmd"
  echo
  echo "# Remote log tail command (optional)"
  echo "$ssh_tail_cmd"
  echo
fi
