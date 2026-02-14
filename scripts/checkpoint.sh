#!/bin/bash
# Pre-flight checkpoint — commit all workspace changes before a risky operation.
# Usage: checkpoint.sh "reason"
# Returns: commit hash (rollback point)

set -euo pipefail

REASON="${1:-pre-flight checkpoint}"
WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$WORKSPACE" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

cd "$WORKSPACE"

# Check if there are any changes to commit
if git diff --quiet HEAD && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  HASH=$(git rev-parse --short HEAD)
  echo "CHECKPOINT: No changes to commit. Current HEAD: $HASH"
  echo "$HASH"
  exit 0
fi

TIMESTAMP=$(date +%Y-%m-%d-%H%M)
MSG="checkpoint: ${REASON} (${TIMESTAMP})"

git add -A
git commit -m "$MSG" --quiet

HASH=$(git rev-parse --short HEAD)
echo "CHECKPOINT: $HASH — $MSG"
echo "$HASH"
