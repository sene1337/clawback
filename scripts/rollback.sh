#!/bin/bash
# ClawBack rollback — revert to checkpoint AND log regression.
# Usage: rollback.sh <commit-hash> "what broke" "why it broke" "principle tested" [--prompted]
# All 4 main arguments required. --prompted flag marks it as 🔴 (human-caught). Default: 🟢 (self-caught).

set -euo pipefail

TARGET="${1:-}"
WHAT="${2:-}"
WHY="${3:-}"
PRINCIPLE="${4:-}"
FLAG="🟢"

# Check for --prompted flag in any position
for arg in "$@"; do
  if [ "$arg" = "--prompted" ]; then
    FLAG="🔴"
  fi
done

if [ -z "$TARGET" ] || [ -z "$WHAT" ] || [ -z "$WHY" ] || [ -z "$PRINCIPLE" ]; then
  echo "ERROR: All 4 arguments required" >&2
  echo "Usage: rollback.sh <commit-hash> \"what broke\" \"why it broke\" \"principle tested\" [--prompted]" >&2
  echo "" >&2
  echo "  --prompted    Mark as 🔴 (human-caught). Default: 🟢 (self-caught)." >&2
  echo "" >&2
  echo "You can't rollback without logging what went wrong." >&2
  exit 1
fi

WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$WORKSPACE" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

cd "$WORKSPACE"

# Verify the target commit exists
if ! git cat-file -t "$TARGET" &>/dev/null; then
  echo "ERROR: Commit $TARGET not found" >&2
  exit 1
fi

CURRENT=$(git rev-parse --short HEAD)
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d-%H%M)

# --- Rollback the files ---
git read-tree "$TARGET"
git checkout-index -a -f

# Clean untracked files created after the checkpoint
# Only clean files that were added after the target commit, not all untracked files
git diff --name-only --diff-filter=A "$TARGET" HEAD 2>/dev/null | while read -r f; do
  [ -f "$f" ] && rm -f "$f"
done

git add -A

# --- Log regression to docs/ops/regressions.md ---
REGRESSIONS="$WORKSPACE/docs/ops/regressions.md"

# Create regressions file if it doesn't exist
if [ ! -f "$REGRESSIONS" ]; then
  mkdir -p "$(dirname "$REGRESSIONS")"
  cat > "$REGRESSIONS" << 'HEREDOC'
# Regressions

Failures logged against the principle they tested. Format: what broke → why → what changed.
Flag: 🔴 prompted (human caught it) | 🟢 autonomous (self-caught).

---

**Policy:** Active file holds last 10. Older entries archived to `regression-archive.md`.
HEREDOC
  echo "SETUP: Created docs/ops/regressions.md"
fi

# Find the highest regression number
LAST_NUM=$(grep -oE '^[0-9]+\.' "$REGRESSIONS" | tail -1 | tr -d '.' || echo "0")
if [ -z "$LAST_NUM" ]; then LAST_NUM=0; fi
NEXT_NUM=$((LAST_NUM + 1))

REGRESSION_LINE="${NEXT_NUM}. ${FLAG} **${WHAT}** (${TODAY}) — ${WHAT} → ${WHY} → Rolled back to ${TARGET}. Tests \"${PRINCIPLE}\"."

# Insert before the separator + policy line at the bottom
if grep -q "^\*\*Policy:\*\*" "$REGRESSIONS"; then
  awk -v entry="$REGRESSION_LINE" '
    /^---$/ && !inserted { print entry; print ""; inserted=1 }
    { print }
  ' "$REGRESSIONS" > "${REGRESSIONS}.tmp" && mv "${REGRESSIONS}.tmp" "$REGRESSIONS"
else
  echo "$REGRESSION_LINE" >> "$REGRESSIONS"
fi

echo "REGRESSION: Logged #${NEXT_NUM} (${FLAG}) to docs/ops/regressions.md"

# --- Auto-archive if over 10 ---
ENTRY_COUNT=$(grep -cE '^[0-9]+\.' "$REGRESSIONS" || echo "0")
if [ "$ENTRY_COUNT" -gt 10 ]; then
  ARCHIVE="$WORKSPACE/docs/ops/regression-archive.md"
  if [ ! -f "$ARCHIVE" ]; then
    echo "# Regression Archive" > "$ARCHIVE"
    echo "" >> "$ARCHIVE"
  fi
  # Move the oldest entry (first numbered line) to archive
  OLDEST=$(grep -m1 -E '^[0-9]+\.' "$REGRESSIONS")
  echo "$OLDEST" >> "$ARCHIVE"
  # Remove the oldest entry — cross-platform (no BSD-only sed -i '')
  OLDEST_LINE=$(grep -m1 -n -E '^[0-9]+\.' "$REGRESSIONS" | cut -d: -f1)
  awk -v line="$OLDEST_LINE" 'NR != line' "$REGRESSIONS" > "${REGRESSIONS}.tmp" && mv "${REGRESSIONS}.tmp" "$REGRESSIONS"
  echo "ARCHIVE: Moved oldest regression to docs/ops/regression-archive.md (${ENTRY_COUNT} → $((ENTRY_COUNT - 1)) active)"
fi

# --- Commit the rollback + regression log together ---
git add -A
git commit -m "rollback: reverted to $TARGET from $CURRENT ($TIMESTAMP) — $WHAT" --allow-empty --quiet

NEW_HASH=$(git rev-parse --short HEAD)
echo "ROLLBACK: $CURRENT → $TARGET (new commit: $NEW_HASH)"
