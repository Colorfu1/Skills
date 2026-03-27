#!/usr/bin/env bash
set -euo pipefail

FILE="data/job_queue.yaml"
STATUS_FILTER=""
PRIORITY_FILTER=""
TYPE_FILTER=""
ID_SUBSTR=""
FORMAT="table"

usage() {
  cat <<'EOF'
Usage:
  job_queue_list.sh [--file PATH] [--status STATUS] [--priority PRIORITY] [--type TYPE] [--id-substr TEXT] [--format table|tsv]

Examples:
  job_queue_list.sh --status todo
  job_queue_list.sh --status todo --priority high
  job_queue_list.sh --type analysis --format tsv
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --file)
      (($# >= 2)) || die "--file requires a value"
      FILE="$2"
      shift 2
      ;;
    --status)
      (($# >= 2)) || die "--status requires a value"
      STATUS_FILTER="$2"
      shift 2
      ;;
    --priority)
      (($# >= 2)) || die "--priority requires a value"
      PRIORITY_FILTER="$2"
      shift 2
      ;;
    --type)
      (($# >= 2)) || die "--type requires a value"
      TYPE_FILTER="$2"
      shift 2
      ;;
    --id-substr)
      (($# >= 2)) || die "--id-substr requires a value"
      ID_SUBSTR="$2"
      shift 2
      ;;
    --format)
      (($# >= 2)) || die "--format requires a value"
      FORMAT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -f "$FILE" ]] || die "file not found: $FILE"
[[ "$FORMAT" == "table" || "$FORMAT" == "tsv" ]] || die "--format must be table or tsv"

rows="$(
  awk \
    -v status_filter="$STATUS_FILTER" \
    -v priority_filter="$PRIORITY_FILTER" \
    -v type_filter="$TYPE_FILTER" \
    -v id_substr="$ID_SUBSTR" '
  function trimq(s) { gsub(/^"|"$/, "", s); return s }
  function prio_rank(p) { return (p=="high" ? 1 : (p=="medium" ? 2 : (p=="low" ? 3 : 9))) }
  function matches_exact(v, f) { return (f == "" || v == f) }
  function matches_substr(v, f) { return (f == "" || index(v, f) > 0) }
  function emit() {
    if (!injob) return
    if (!matches_exact(status, status_filter)) return
    if (!matches_exact(priority, priority_filter)) return
    if (!matches_exact(type, type_filter)) return
    if (!matches_substr(id, id_substr)) return
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\n", prio_rank(priority), id, priority, status, type, name, path
  }
  /^  - id:/ {
    emit()
    injob = 1
    id = $3
    priority = ""
    status = ""
    type = ""
    name = ""
    path = ""
    next
  }
  injob && /^    priority:/ {
    priority = $2
    next
  }
  injob && /^    status:/ {
    status = $2
    next
  }
  injob && /^    type:/ {
    type = $2
    next
  }
  injob && /^    name:/ {
    line = $0
    sub(/^    name: /, "", line)
    name = trimq(line)
    next
  }
  injob && /^    path:/ {
    line = $0
    sub(/^    path: /, "", line)
    path = trimq(line)
    next
  }
  END {
    emit()
  }' "$FILE" | sort -t $'\t' -k1,1n -k2,2
)"

if [[ -z "$rows" ]]; then
  exit 0
fi

if [[ "$FORMAT" == "tsv" ]]; then
  printf "%s\n" "$rows" | cut -f2-
  exit 0
fi

{
  printf "ID\tPriority\tStatus\tType\tName\tPath\n"
  printf "%s\n" "$rows" | cut -f2-
} | {
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t'
  else
    cat
  fi
}
