#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  publish_skills.sh --src <skills-dir> --repo <git-repo-dir> [options]

Options:
  --src <dir>              Source skills directory (required)
  --repo <dir>             Target git repo directory (required)
  --export <dir>           Staging/export directory for sanitized copies (optional)
  --skills <a,b,c>         Comma-separated skill folder names (default: all dirs under --src)
  --owner-from <text>      Replace this text in copied files (optional)
  --owner-to <text>        Replacement for --owner-from (default: owner-tag)
  --readme <file>          Copy this file to <repo>/README.md (optional)
  --backup-tar <file>      Create a tar.gz backup of published files after sync/push (optional)
  --commit                 Create a git commit
  --push                   Push current branch after commit (implies repo must be a git repo)
  --commit-message <msg>   Commit message (default: "Update skills")
  --dry-run                Print planned actions without modifying files
  --help                   Show this help

Examples:
  publish_skills.sh --src ./skills --repo ./gitlab/skills --skills job-uploader,job-manager
  publish_skills.sh --src ./skills --repo ./gitlab/skills --export ./redacted/skills-public \
    --owner-from owner-tag --owner-to owner-tag --commit --push \
    --backup-tar /home/mi/codes/workspace/all.tar.gz
EOF
}

SRC_DIR=""
REPO_DIR=""
EXPORT_DIR=""
SKILLS_CSV=""
OWNER_FROM=""
OWNER_TO="owner-tag"
README_FILE=""
BACKUP_TAR=""
DO_COMMIT=0
DO_PUSH=0
DRY_RUN=0
COMMIT_MSG="Update skills"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC_DIR="${2:-}"; shift 2 ;;
    --repo) REPO_DIR="${2:-}"; shift 2 ;;
    --export) EXPORT_DIR="${2:-}"; shift 2 ;;
    --skills) SKILLS_CSV="${2:-}"; shift 2 ;;
    --owner-from) OWNER_FROM="${2:-}"; shift 2 ;;
    --owner-to) OWNER_TO="${2:-}"; shift 2 ;;
    --readme) README_FILE="${2:-}"; shift 2 ;;
    --backup-tar) BACKUP_TAR="${2:-}"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    --push) DO_PUSH=1; shift ;;
    --commit-message) COMMIT_MSG="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$SRC_DIR" ]] || { echo "--src is required" >&2; exit 1; }
[[ -n "$REPO_DIR" ]] || { echo "--repo is required" >&2; exit 1; }
[[ -d "$SRC_DIR" ]] || { echo "Source dir not found: $SRC_DIR" >&2; exit 1; }
[[ -d "$REPO_DIR" ]] || { echo "Repo dir not found: $REPO_DIR" >&2; exit 1; }

if [[ -n "$SKILLS_CSV" ]]; then
  IFS=',' read -r -a SKILLS <<<"$SKILLS_CSV"
else
  mapfile -t SKILLS < <(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi

if [[ "${#SKILLS[@]}" -eq 0 ]]; then
  echo "No skills selected" >&2
  exit 1
fi

STAGE_DIR="$SRC_DIR"
if [[ -n "$EXPORT_DIR" ]]; then
  STAGE_DIR="$EXPORT_DIR"
fi

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

echo "Source: $SRC_DIR"
echo "Repo:   $REPO_DIR"
echo "Stage:  $STAGE_DIR"
echo "Skills: ${SKILLS[*]}"

if [[ -n "$EXPORT_DIR" ]]; then
  run "mkdir -p \"${EXPORT_DIR}\""
  for skill in "${SKILLS[@]}"; do
    [[ -d "$SRC_DIR/$skill" ]] || { echo "Missing skill: $SRC_DIR/$skill" >&2; exit 1; }
    run "rm -rf \"${EXPORT_DIR}/${skill}\""
    run "cp -r \"${SRC_DIR}/${skill}\" \"${EXPORT_DIR}/\""
  done
fi

if [[ -n "$OWNER_FROM" ]]; then
  echo "Applying text replacement in stage: '$OWNER_FROM' -> '$OWNER_TO'"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] replace in copied files under %s\n' "$STAGE_DIR"
  else
    while IFS= read -r -d '' f; do
      perl -0pi -e "s/\Q$OWNER_FROM\E/$OWNER_TO/g" "$f"
    done < <(find "$STAGE_DIR" -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.txt' -o -name '*.sh' \) -print0)
  fi
fi

for skill in "${SKILLS[@]}"; do
  [[ -d "$STAGE_DIR/$skill" ]] || { echo "Missing staged skill: $STAGE_DIR/$skill" >&2; exit 1; }
  run "rm -rf \"${REPO_DIR}/${skill}\""
  run "cp -r \"${STAGE_DIR}/${skill}\" \"${REPO_DIR}/\""
done

if [[ -n "$README_FILE" ]]; then
  [[ -f "$README_FILE" ]] || { echo "README file not found: $README_FILE" >&2; exit 1; }
  run "cp \"${README_FILE}\" \"${REPO_DIR}/README.md\""
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

git -C "$REPO_DIR" status --short
git -C "$REPO_DIR" diff --stat || true

if [[ "$DO_COMMIT" -eq 1 ]]; then
  git -C "$REPO_DIR" add README.md "${SKILLS[@]}"
  if git -C "$REPO_DIR" diff --cached --quiet; then
    echo "No staged changes to commit"
  else
    git -C "$REPO_DIR" commit -m "$COMMIT_MSG"
  fi
fi

if [[ "$DO_PUSH" -eq 1 ]]; then
  git -C "$REPO_DIR" push
fi

if [[ -n "$BACKUP_TAR" ]]; then
  backup_dir="$(dirname "$BACKUP_TAR")"
  mkdir -p "$backup_dir"

  # Prefer archiving the sanitized stage/export copy when available.
  tar_source="$STAGE_DIR"
  tar_items=("${SKILLS[@]}")

  if [[ -n "$README_FILE" ]]; then
    if [[ "$STAGE_DIR" == "$REPO_DIR" ]]; then
      tar_items=("README.md" "${tar_items[@]}")
    elif [[ -f "$STAGE_DIR/README.md" ]]; then
      tar_items=("README.md" "${tar_items[@]}")
    fi
  fi

  echo "Creating backup tarball: $BACKUP_TAR"
  # tar from the chosen source to avoid including repo .git metadata
  tar -czf "$BACKUP_TAR" -C "$tar_source" "${tar_items[@]}"
fi
