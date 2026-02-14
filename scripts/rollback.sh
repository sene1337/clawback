#!/bin/bash
# ClawBack rollback — revert to checkpoint AND log regression.
# Usage: rollback.sh <commit-hash> "what broke" "why it broke" "principle tested"
# All arguments required. You can't rollback without logging the failure.

set -euo pipefail

TARGET="${1:-}"
WHAT="${2:-}"
WHY="${3:-}"
PRINCIPLE="${4:-}"

if [ -z "$TARGET" ] || [ -z "$WHAT" ] || [ -z "$WHY" ] || [ -z "$PRINCIPLE" ]; then
  echo "ERROR: All 4 arguments required" >&2
  echo "Usage: rollback.sh <commit-hash> \"what broke\" \"why it broke\" \"principle tested\"" >&2
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
git add -A

# --- Log regression to PRINCIPLES.md ---
PRINCIPLES="$WORKSPACE/PRINCIPLES.md"

if [ -f "$PRINCIPLES" ]; then
  # Find the highest regression number (macOS + Linux compatible)
  LAST_NUM=$(grep -oE '^[0-9]+\.' "$PRINCIPLES" | tail -1 | tr -d '.' || echo "0")
  if [ -z "$LAST_NUM" ]; then LAST_NUM=0; fi
  NEXT_NUM=$((LAST_NUM + 1))

  # Check if ## Regressions section exists
  if grep -q "^## Regressions" "$PRINCIPLES"; then
    # Find the line after the last regression entry (or after the header + format line)
    # Append after the last numbered entry in the Regressions section
    REGRESSION_LINE="${NEXT_NUM}. 🟢 **${WHAT}** (${TODAY}) — ${WHAT} → ${WHY} → Rolled back to ${TARGET}. Tests \"${PRINCIPLE}\"."

    # Use awk to insert after the last numbered line in Regressions section
    awk -v entry="$REGRESSION_LINE" '
      /^## Regressions/ { in_section=1 }
      in_section && /^---$/ { print entry; print ""; in_section=0 }
      in_section && /^## / && !/^## Regressions/ { print entry; print ""; in_section=0 }
      { print }
      END { if (in_section) { print entry } }
    ' "$PRINCIPLES" > "${PRINCIPLES}.tmp" && mv "${PRINCIPLES}.tmp" "$PRINCIPLES"

    echo "REGRESSION: Logged #${NEXT_NUM} to PRINCIPLES.md"
  else
    # Create the section
    printf "\n\n## Regressions\n\nFailures logged against the principle they tested. Format: what broke → why → what changed. Flag: 🔴 prompted | 🟢 autonomous.\n\n1. 🟢 **${WHAT}** (${TODAY}) — ${WHAT} → ${WHY} → Rolled back to ${TARGET}. Tests \"${PRINCIPLE}\".\n" >> "$PRINCIPLES"
    echo "REGRESSION: Created Regressions section, logged #1 to PRINCIPLES.md"
  fi
else
  echo "WARNING: PRINCIPLES.md not found at $PRINCIPLES — regression not logged to file"
  echo "REGRESSION (stdout only): ${WHAT} → ${WHY} → Tests \"${PRINCIPLE}\""
fi

# --- Commit the rollback + regression log together ---
git add -A
git commit -m "rollback: reverted to $TARGET from $CURRENT ($TIMESTAMP) — $WHAT" --allow-empty --quiet

NEW_HASH=$(git rev-parse --short HEAD)
echo "ROLLBACK: $CURRENT → $TARGET (new commit: $NEW_HASH)"
