#!/bin/bash
# Rollback to a checkpoint — creates a revert commit (non-destructive).
# Usage: rollback.sh <commit-hash>
# Safe: never force-pushes or rewrites history.

set -euo pipefail

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "ERROR: Provide a commit hash to rollback to" >&2
  echo "Usage: rollback.sh <commit-hash>" >&2
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
TIMESTAMP=$(date +%Y-%m-%d-%H%M)

# Restore the tree state from target commit, then commit as a new commit
git read-tree "$TARGET"
git checkout-index -a -f
git add -A
git commit -m "rollback: reverted to $TARGET from $CURRENT ($TIMESTAMP)" --allow-empty --quiet

NEW_HASH=$(git rev-parse --short HEAD)
echo "ROLLBACK: $CURRENT → $TARGET (new commit: $NEW_HASH)"
