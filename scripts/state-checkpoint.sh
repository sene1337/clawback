#!/bin/bash
# Capture selected out-of-workspace runtime state into a local-only snapshot plus git-tracked manifest.
# Usage:
#   state-checkpoint.sh [--ops-state <path>] [--name <label>] [--path <abs-path>]... [--profile openclaw-core] [--manifest-only] [--dry-run]

set -euo pipefail

WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || true)
OPS_STATE_DIR="${CLAWBACK_OPS_STATE_DIR:-}"
CHECKPOINT_NAME="runtime-state checkpoint"
PROFILE="openclaw-core"
MANIFEST_ONLY=0
DRY_RUN=0
SELECTED_PATHS=()

usage() {
  cat <<'EOF'
Usage:
  bash scripts/state-checkpoint.sh [options]

Options:
  --ops-state <path>   Override the local ops-state repo path.
  --name <label>       Human label for the checkpoint.
  --path <path>        Add an explicit out-of-workspace path to capture.
  --profile <name>     Default path profile when no --path flags are given.
  --manifest-only      Record manifest metadata without creating a snapshot.
  --dry-run            Print the capture plan without writing files.

Default profile: openclaw-core
  - ~/.openclaw/lcm.db
  - ~/.openclaw/agents/*/sessions
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
  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
    return
  fi
  echo "$target"
}

canonical_existing_path() {
  local target="$1"

  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
    return
  fi

  if [ -e "$target" ]; then
    echo "$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
    return
  fi

  return 1
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

append_default_profile_paths() {
  local root="${CLAWBACK_OPENCLAW_ROOT:-$HOME/.openclaw}"
  local dir

  case "$PROFILE" in
    openclaw-core)
      if [ -f "$root/lcm.db" ]; then
        SELECTED_PATHS+=("$root/lcm.db")
      fi
      if [ -d "$root/agents" ]; then
        while IFS= read -r dir; do
          [ -n "$dir" ] || continue
          SELECTED_PATHS+=("$dir")
        done < <(find "$root/agents" -mindepth 2 -maxdepth 2 -type d -name sessions 2>/dev/null | sort)
      fi
      ;;
    none)
      ;;
    *)
      echo "ERROR: Unknown profile: $PROFILE" >&2
      exit 1
      ;;
  esac
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
    --name)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --name requires a value" >&2
        exit 1
      fi
      CHECKPOINT_NAME="$2"
      shift 2
      ;;
    --path)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --path requires a value" >&2
        exit 1
      fi
      SELECTED_PATHS+=("$2")
      shift 2
      ;;
    --profile)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --profile requires a value" >&2
        exit 1
      fi
      PROFILE="$2"
      shift 2
      ;;
    --manifest-only)
      MANIFEST_ONLY=1
      shift
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

OPS_STATE_DIR=$(canonical_dir "$(default_ops_state_dir)")

if [ ! -d "$OPS_STATE_DIR/.git" ] || [ ! -f "$OPS_STATE_DIR/.clawback-ops-state" ]; then
  echo "ERROR: ops-state repo is not initialized at $OPS_STATE_DIR" >&2
  echo "Run: bash scripts/init-ops-state.sh --ops-state \"$OPS_STATE_DIR\"" >&2
  exit 1
fi

if [ -n "$(git -C "$OPS_STATE_DIR" remote)" ]; then
  echo "ERROR: ops-state must remain local-only. Remove git remotes from $OPS_STATE_DIR" >&2
  exit 1
fi

if [ "${#SELECTED_PATHS[@]}" -eq 0 ]; then
  append_default_profile_paths
fi

if [ "${#SELECTED_PATHS[@]}" -eq 0 ]; then
  echo "ERROR: No runtime-state paths resolved. Add --path or adjust --profile." >&2
  exit 1
fi

CHECKPOINT_ID=$(date +%Y%m%d-%H%M%S)
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SNAPSHOT_REL="snapshots/${CHECKPOINT_ID}.tar.gz"
MANIFEST_PATH="$OPS_STATE_DIR/manifests/${CHECKPOINT_ID}.manifest"
CHECKSUM_PATH="$OPS_STATE_DIR/manifests/${CHECKPOINT_ID}.sha256"
INDEX_PATH="$OPS_STATE_DIR/indexes/checkpoints.tsv"
MODE="snapshot"
ITEM_COUNT=0

if [ "$MANIFEST_ONLY" -eq 1 ]; then
  MODE="manifest-only"
fi

TMP_DIR=""
if [ "$DRY_RUN" -ne 1 ]; then
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clawback-state-checkpoint.XXXXXX")
  trap 'rm -rf "$TMP_DIR"' EXIT
  mkdir -p "$TMP_DIR/payload"
fi

MANIFEST_BODY=""

for path in "${SELECTED_PATHS[@]}"; do
  ABS_PATH=$(canonical_existing_path "$path") || {
    echo "ERROR: Path not found: $path" >&2
    exit 1
  }

  if path_is_within "$ABS_PATH" "$WORKSPACE"; then
    echo "ERROR: Refusing to checkpoint workspace path: $ABS_PATH" >&2
    exit 1
  fi

  if path_is_within "$ABS_PATH" "$OPS_STATE_DIR"; then
    echo "ERROR: Refusing to checkpoint ops-state internals: $ABS_PATH" >&2
    exit 1
  fi

  ITEM_COUNT=$((ITEM_COUNT + 1))
  ITEM_REL=$(printf 'items/%03d' "$ITEM_COUNT")

  if [ -L "$ABS_PATH" ]; then
    ITEM_TYPE="symlink"
  elif [ -d "$ABS_PATH" ]; then
    ITEM_TYPE="dir"
  elif [ -f "$ABS_PATH" ]; then
    ITEM_TYPE="file"
  else
    echo "ERROR: Unsupported path type: $ABS_PATH" >&2
    exit 1
  fi

  MANIFEST_BODY="${MANIFEST_BODY}${ITEM_TYPE}"$'\t'"${ABS_PATH}"$'\t'"${ITEM_REL}"$'\n'

  if [ "$DRY_RUN" -eq 1 ] || [ "$MANIFEST_ONLY" -eq 1 ]; then
    continue
  fi

  mkdir -p "$TMP_DIR/payload/$(dirname "$ITEM_REL")"
  case "$ITEM_TYPE" in
    dir)
      mkdir -p "$TMP_DIR/payload/$ITEM_REL"
      cp -R "$ABS_PATH/." "$TMP_DIR/payload/$ITEM_REL/"
      ;;
    symlink)
      cp -P "$ABS_PATH" "$TMP_DIR/payload/$ITEM_REL"
      ;;
    file)
      cp -p "$ABS_PATH" "$TMP_DIR/payload/$ITEM_REL"
      ;;
  esac
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN: checkpoint id would be $CHECKPOINT_ID"
  echo "DRY-RUN: ops-state repo $OPS_STATE_DIR"
  echo "DRY-RUN: mode $MODE"
  printf '%s' "$MANIFEST_BODY"
  exit 0
fi

mkdir -p "$OPS_STATE_DIR/manifests" "$OPS_STATE_DIR/indexes" "$OPS_STATE_DIR/snapshots"

{
  printf 'checkpoint_id=%s\n' "$CHECKPOINT_ID"
  printf 'created_at=%s\n' "$CREATED_AT"
  printf 'name=%s\n' "$(printf '%s' "$CHECKPOINT_NAME" | tr '\t\n' '  ')"
  printf 'mode=%s\n' "$MODE"
  printf 'snapshot_rel=%s\n' "$SNAPSHOT_REL"
  printf 'item_count=%s\n' "$ITEM_COUNT"
  printf -- '---\n'
  printf '%s' "$MANIFEST_BODY"
} > "$MANIFEST_PATH"

if [ "$MANIFEST_ONLY" -eq 0 ]; then
  tar -czf "$OPS_STATE_DIR/$SNAPSHOT_REL" -C "$TMP_DIR" payload
  shasum -a 256 "$OPS_STATE_DIR/$SNAPSHOT_REL" | awk '{print $1}' > "$CHECKSUM_PATH"
else
  printf 'manifest-only\n' > "$CHECKSUM_PATH"
fi

if [ ! -f "$INDEX_PATH" ]; then
  printf 'checkpoint_id\tcreated_at\tname\tmode\titem_count\tsnapshot\n' > "$INDEX_PATH"
fi

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$CHECKPOINT_ID" \
  "$CREATED_AT" \
  "$(printf '%s' "$CHECKPOINT_NAME" | tr '\t\n' '  ')" \
  "$MODE" \
  "$ITEM_COUNT" \
  "$SNAPSHOT_REL" >> "$INDEX_PATH"

git -C "$OPS_STATE_DIR" add "$MANIFEST_PATH" "$CHECKSUM_PATH" "$INDEX_PATH"
if ! git -C "$OPS_STATE_DIR" diff --cached --quiet; then
  git -C "$OPS_STATE_DIR" commit -m "checkpoint: $CHECKPOINT_NAME ($CHECKPOINT_ID)" --quiet
fi

echo "STATE CHECKPOINT: $CHECKPOINT_ID"
echo "STATE CHECKPOINT: mode=$MODE items=$ITEM_COUNT"
echo "STATE CHECKPOINT: manifest=$(basename "$MANIFEST_PATH")"
if [ "$MANIFEST_ONLY" -eq 0 ]; then
  echo "STATE CHECKPOINT: snapshot=$SNAPSHOT_REL"
fi
