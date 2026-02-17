#!/bin/bash
# ClawBack setup — bootstraps docs/ops/regressions.md for regression logging.
# Safe to run multiple times — won't overwrite existing content.

set -euo pipefail

WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$WORKSPACE" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

REGRESSIONS="$WORKSPACE/docs/ops/regressions.md"

if [ -f "$REGRESSIONS" ]; then
  echo "SETUP: docs/ops/regressions.md already exists. Nothing to do."
  exit 0
fi

mkdir -p "$(dirname "$REGRESSIONS")"
cat > "$REGRESSIONS" << 'EOF'
# Regressions

Failures logged against the principle they tested. Format: what broke → why → what changed.
Flag: 🔴 prompted (human caught it) | 🟢 autonomous (self-caught).

---

**Policy:** Active file holds last 10. Older entries archived to `regression-archive.md`.
EOF

echo "SETUP: Created docs/ops/regressions.md"
