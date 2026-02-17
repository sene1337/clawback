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

# Check for --brad flag in any position
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

# Clean untracked files created after the checkpoint (safe rollback)
git clean -fd --quiet

git add -A

# --- Log regression to docs/ops/regressions.md ---
REGRESSIONS="$WORKSPACE/docs/ops/regressions.md"

if [ -f "$REGRESSIONS" ]; then
  # Find the highest regression number — scoped to numbered list items only
  LAST_NUM=$(grep -oE '^[0-9]+\.' "$REGRESSIONS" | tail -1 | tr -d '.' || echo "0")
  if [ -z "$LAST_NUM" ]; then LAST_NUM=0; fi
  NEXT_NUM=$((LAST_NUM + 1))

  REGRESSION_LINE="${NEXT_NUM}. ${FLAG} **${WHAT}** (${TODAY}) — ${WHAT} → ${WHY} → Rolled back to ${TARGET}. Tests \"${PRINCIPLE}\"."

  # Insert before the policy line at the bottom
  if grep -q "^\*\*Policy:\*\*" "$REGRESSIONS"; then
    # Insert before the separator + policy
    awk -v entry="$REGRESSION_LINE" '
      /^---$/ && !inserted { print entry; print ""; inserted=1 }
      { print }
    ' "$REGRESSIONS" > "${REGRESSIONS}.tmp" && mv "${REGRESSIONS}.tmp" "$REGRESSIONS"
  else
    # Just append
    echo "$REGRESSION_LINE" >> "$REGRESSIONS"
  fi

  echo "REGRESSION: Logged #${NEXT_NUM} (${FLAG}) to docs/ops/regressions.md"

  # --- Auto-archive if over 10 ---
  ENTRY_COUNT=$(grep -cE '^[0-9]+\.' "$REGRESSIONS" || echo "0")
  if [ "$ENTRY_COUNT" -gt 10 ]; then
    ARCHIVE="$WORKSPACE/docs/ops/regression-archive.md"
    # Move the oldest entry (first numbered line) to archive
    OLDEST=$(grep -m1 -E '^[0-9]+\.' "$REGRESSIONS")
    echo "$OLDEST" >> "$ARCHIVE"
    # Remove the oldest entry from active file
    grep -m1 -n -E '^[0-9]+\.' "$REGRESSIONS" | cut -d: -f1 | xargs -I{} sed -i '' '{}d' "$REGRESSIONS"
    echo "ARCHIVE: Moved oldest regression to docs/ops/regression-archive.md (${ENTRY_COUNT} → $((ENTRY_COUNT - 1)) active)"
  fi
else
  echo "WARNING: docs/ops/regressions.md not found — regression not logged to file"
  echo "REGRESSION (stdout only): ${FLAG} ${WHAT} → ${WHY} → Tests \"${PRINCIPLE}\""
fi

# --- Commit the rollback + regression log together ---
git add -A
git commit -m "rollback: reverted to $TARGET from $CURRENT ($TIMESTAMP) — $WHAT" --allow-empty --quiet

NEW_HASH=$(git rev-parse --short HEAD)
echo "ROLLBACK: $CURRENT → $TARGET (new commit: $NEW_HASH)"
