#!/bin/bash
# Bootstrap a local-only ops-state repo for Option C runtime-state tracking.
# Usage:
#   init-ops-state.sh [--ops-state <path>] [--dry-run]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || true)
OPS_STATE_DIR=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/init-ops-state.sh [--ops-state <path>] [--dry-run]

Creates a local-only ops-state git repo beside the workspace (default:
~/.openclaw/ops-state), installs ClawBack pre-commit guardrails, and commits
the bootstrap metadata.
EOF
}

default_ops_state_dir() {
  if [ -n "${CLAWBACK_OPS_STATE_DIR:-}" ]; then
    echo "$CLAWBACK_OPS_STATE_DIR"
    return
  fi

  if [ -n "$WORKSPACE" ] && [ "$(basename "$WORKSPACE")" = "workspace" ]; then
    echo "$(cd "$WORKSPACE/.." && pwd -P)/ops-state"
    return
  fi

  echo "$HOME/.openclaw/ops-state"
}

canonical_dir() {
  local target="$1"
  local parent

  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
    return
  fi

  parent=$(dirname "$target")
  if [ -d "$parent" ]; then
    echo "$(cd "$parent" && pwd -P)/$(basename "$target")"
    return
  fi

  echo "$target"
}

path_is_within() {
  case "$1/" in
    "$2/"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_line() {
  local file="$1"
  local line="$2"

  if [ ! -f "$file" ]; then
    printf '%s\n' "$line" > "$file"
    return
  fi

  if ! grep -Fxq "$line" "$file"; then
    printf '%s\n' "$line" >> "$file"
  fi
}

write_file_if_missing() {
  local path="$1"
  local content="$2"

  if [ ! -f "$path" ]; then
    printf '%s' "$content" > "$path"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ops-state)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --ops-state requires a path" >&2
        exit 1
      fi
      OPS_STATE_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$WORKSPACE" ]; then
  echo "ERROR: Not inside a git workspace" >&2
  exit 1
fi

if [ -z "$OPS_STATE_DIR" ]; then
  OPS_STATE_DIR=$(default_ops_state_dir)
fi

OPS_STATE_DIR=$(canonical_dir "$OPS_STATE_DIR")

if path_is_within "$OPS_STATE_DIR" "$WORKSPACE"; then
  echo "ERROR: ops-state must live outside the workspace repo: $OPS_STATE_DIR" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: would bootstrap local-only ops-state repo at $OPS_STATE_DIR"
  echo "DRY-RUN: would create manifests/, indexes/, restores/, snapshots/, restore-staging/, hooks/"
  echo "DRY-RUN: would install scripts/pre-commit-guard.sh as the git pre-commit hook"
  exit 0
fi

mkdir -p "$OPS_STATE_DIR" \
  "$OPS_STATE_DIR/manifests" \
  "$OPS_STATE_DIR/indexes" \
  "$OPS_STATE_DIR/restores" \
  "$OPS_STATE_DIR/snapshots" \
  "$OPS_STATE_DIR/restore-staging" \
  "$OPS_STATE_DIR/hooks"

if [ ! -d "$OPS_STATE_DIR/.git" ]; then
  git -C "$OPS_STATE_DIR" init --quiet
fi

if [ -n "$(git -C "$OPS_STATE_DIR" remote)" ]; then
  echo "ERROR: $OPS_STATE_DIR already has a git remote. ops-state must remain local-only." >&2
  exit 1
fi

ensure_line "$OPS_STATE_DIR/.gitignore" "snapshots/"
ensure_line "$OPS_STATE_DIR/.gitignore" "restore-staging/"
ensure_line "$OPS_STATE_DIR/.gitignore" "backups/"
ensure_line "$OPS_STATE_DIR/.gitignore" "*.tar"
ensure_line "$OPS_STATE_DIR/.gitignore" "*.tar.gz"
ensure_line "$OPS_STATE_DIR/.gitignore" "*.tgz"
ensure_line "$OPS_STATE_DIR/.gitignore" "*.tmp"
ensure_line "$OPS_STATE_DIR/.gitignore" ".DS_Store"

write_file_if_missing "$OPS_STATE_DIR/.clawback-ops-state" "local-only ops-state repo\n"
write_file_if_missing "$OPS_STATE_DIR/README.md" "# ops-state\n\nLocal-only ClawBack runtime-state metadata surface.\n\nTracked here:\n- manifests and checkpoint indexes\n- restore event notes\n- hook/policy docs\n\nIgnored here:\n- raw snapshots\n- restore staging dirs\n- backups\n- logs, caches, and secrets\n"
write_file_if_missing "$OPS_STATE_DIR/hooks/README.md" "# Hook Policy\n\npre-commit is installed by scripts/init-ops-state.sh and runs ClawBack's scripts/pre-commit-guard.sh.\n\nPurpose:\n- keep ops-state local-only\n- block raw snapshots and runtime DBs from git\n- block obvious secrets and keys\n"

if [ ! -f "$OPS_STATE_DIR/indexes/checkpoints.tsv" ]; then
  printf 'checkpoint_id\tcreated_at\tname\tmode\titem_count\tsnapshot\n' > "$OPS_STATE_DIR/indexes/checkpoints.tsv"
fi

bash "$SCRIPT_DIR/pre-commit-guard.sh" --install "$OPS_STATE_DIR" >/dev/null

git -C "$OPS_STATE_DIR" add .clawback-ops-state .gitignore README.md hooks/README.md indexes/checkpoints.tsv

if ! git -C "$OPS_STATE_DIR" diff --cached --quiet; then
  if git -C "$OPS_STATE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$OPS_STATE_DIR" commit -m "chore: bootstrap local ops-state surface" --quiet
  else
    git -C "$OPS_STATE_DIR" commit -m "chore: bootstrap local ops-state surface" --quiet
  fi
fi

echo "OPS-STATE: Ready at $OPS_STATE_DIR"
echo "OPS-STATE: pre-commit guard installed and local-only policy enforced"
