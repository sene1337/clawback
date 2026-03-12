#!/bin/bash
# Restore a runtime-state snapshot by checkpoint id with checksum verification and dry-run by default.
# Usage:
#   state-restore.sh <checkpoint-id> [--ops-state <path>] [--dry-run] [--yes-restore]

set -euo pipefail

WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || true)
CHECKPOINT_ID=""
OPS_STATE_DIR="${CLAWBACK_OPS_STATE_DIR:-}"
DRY_RUN=1
YES_RESTORE=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/state-restore.sh <checkpoint-id> [options]

Options:
  --ops-state <path>   Override the local ops-state repo path.
  --dry-run            Show the restore plan without modifying files (default).
  --yes-restore        Perform a non-destructive overlay restore after verification.

Restore semantics:
  - verifies the stored snapshot checksum
  - refuses workspace and ops-state targets
  - overlays snapshot contents onto the original paths
  - does not prune files that were created after the checkpoint
EOF
}

default_ops_state_dir() {
  if [ -n "$OPS_STATE_DIR" ]; then
    echo "$OPS_STATE_DIR"
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

manifest_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$MANIFEST_PATH"
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
    --yes-restore)
      YES_RESTORE=1
      DRY_RUN=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$CHECKPOINT_ID" ]; then
        echo "ERROR: Multiple checkpoint ids provided: $CHECKPOINT_ID and $1" >&2
        usage >&2
        exit 1
      fi
      CHECKPOINT_ID="$1"
      shift
      ;;
  esac
done

if [ -z "$CHECKPOINT_ID" ]; then
  usage >&2
  exit 1
fi

if [ -z "$WORKSPACE" ]; then
  echo "ERROR: Not inside a git workspace" >&2
  exit 1
fi

OPS_STATE_DIR=$(canonical_dir "$(default_ops_state_dir)")

if [ ! -d "$OPS_STATE_DIR/.git" ] || [ ! -f "$OPS_STATE_DIR/.clawback-ops-state" ]; then
  echo "ERROR: ops-state repo is not initialized at $OPS_STATE_DIR" >&2
  exit 1
fi

if [ -n "$(git -C "$OPS_STATE_DIR" remote)" ]; then
  echo "ERROR: ops-state must remain local-only. Remove git remotes from $OPS_STATE_DIR" >&2
  exit 1
fi

MANIFEST_PATH="$OPS_STATE_DIR/manifests/${CHECKPOINT_ID}.manifest"
CHECKSUM_PATH="$OPS_STATE_DIR/manifests/${CHECKPOINT_ID}.sha256"

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "ERROR: Manifest not found for checkpoint: $CHECKPOINT_ID" >&2
  exit 1
fi

MODE=$(manifest_value mode)
SNAPSHOT_REL=$(manifest_value snapshot_rel)
ITEM_COUNT=$(manifest_value item_count)
SNAPSHOT_PATH="$OPS_STATE_DIR/$SNAPSHOT_REL"

if [ "$MODE" = "manifest-only" ]; then
  echo "ERROR: $CHECKPOINT_ID is manifest-only and cannot be restored." >&2
  exit 1
fi

if [ ! -f "$SNAPSHOT_PATH" ] || [ ! -f "$CHECKSUM_PATH" ]; then
  echo "ERROR: Snapshot or checksum missing for checkpoint: $CHECKPOINT_ID" >&2
  exit 1
fi

EXPECTED_SUM=$(tr -d '[:space:]' < "$CHECKSUM_PATH")
ACTUAL_SUM=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')

if [ "$EXPECTED_SUM" != "$ACTUAL_SUM" ]; then
  echo "ERROR: Snapshot checksum mismatch for $CHECKPOINT_ID" >&2
  exit 1
fi

ITEM_LINES=$(sed -n '/^---$/,$p' "$MANIFEST_PATH" | tail -n +2)

while IFS=$'\t' read -r item_type source_path stored_rel; do
  [ -n "$source_path" ] || continue

  if path_is_within "$source_path" "$WORKSPACE"; then
    echo "ERROR: Manifest includes workspace path, refusing restore: $source_path" >&2
    exit 1
  fi

  if path_is_within "$source_path" "$OPS_STATE_DIR"; then
    echo "ERROR: Manifest includes ops-state path, refusing restore: $source_path" >&2
    exit 1
  fi
done <<EOF
$ITEM_LINES
EOF

tar -tzf "$SNAPSHOT_PATH" >/dev/null

if [ "$YES_RESTORE" -ne 1 ]; then
  echo "DRY-RUN: restore plan for $CHECKPOINT_ID"
  echo "DRY-RUN: verified checksum $ACTUAL_SUM"
  echo "DRY-RUN: item_count=$ITEM_COUNT"
  printf '%s\n' "$ITEM_LINES"
  exit 0
fi

RESTORE_ID=$(date +%Y%m%d-%H%M%S)
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clawback-state-restore.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$OPS_STATE_DIR/restore-staging" "$OPS_STATE_DIR/restores"
tar -xzf "$SNAPSHOT_PATH" -C "$STAGING_DIR"

while IFS=$'\t' read -r item_type source_path stored_rel; do
  [ -n "$source_path" ] || continue

  case "$item_type" in
    dir)
      mkdir -p "$source_path"
      cp -R "$STAGING_DIR/payload/$stored_rel/." "$source_path/"
      ;;
    symlink)
      mkdir -p "$(dirname "$source_path")"
      cp -P "$STAGING_DIR/payload/$stored_rel" "$source_path"
      ;;
    file)
      mkdir -p "$(dirname "$source_path")"
      cp -p "$STAGING_DIR/payload/$stored_rel" "$source_path"
      ;;
    *)
      echo "ERROR: Unsupported manifest item type: $item_type" >&2
      exit 1
      ;;
  esac
done <<EOF
$ITEM_LINES
EOF

RESTORE_LOG="$OPS_STATE_DIR/restores/${RESTORE_ID}-${CHECKPOINT_ID}.txt"
{
  printf 'restore_id=%s\n' "$RESTORE_ID"
  printf 'checkpoint_id=%s\n' "$CHECKPOINT_ID"
  printf 'restored_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'mode=overlay\n'
  printf 'item_count=%s\n' "$ITEM_COUNT"
  printf 'verified_sha256=%s\n' "$ACTUAL_SUM"
} > "$RESTORE_LOG"

git -C "$OPS_STATE_DIR" add "$RESTORE_LOG"
if ! git -C "$OPS_STATE_DIR" diff --cached --quiet; then
  git -C "$OPS_STATE_DIR" commit -m "restore: $CHECKPOINT_ID ($RESTORE_ID)" --quiet
fi

echo "STATE RESTORE: applied checkpoint $CHECKPOINT_ID"
echo "STATE RESTORE: overlay restore complete; files created after the checkpoint were preserved"
