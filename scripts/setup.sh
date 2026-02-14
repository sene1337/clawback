#!/bin/bash
# ClawBack setup — bootstraps PRINCIPLES.md with a Regressions section.
# Safe to run multiple times — won't overwrite existing content.

set -euo pipefail

WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$WORKSPACE" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

PRINCIPLES="$WORKSPACE/PRINCIPLES.md"

if [ -f "$PRINCIPLES" ]; then
  if grep -q "^## Regressions" "$PRINCIPLES"; then
    echo "SETUP: PRINCIPLES.md already has a Regressions section. Nothing to do."
    exit 0
  else
    printf "\n\n## Regressions\n\nFailures logged against the principle they tested. Format: what broke → why → what changed. Flag: 🔴 prompted (human caught it) | 🟢 autonomous (self-caught).\n" >> "$PRINCIPLES"
    echo "SETUP: Added Regressions section to existing PRINCIPLES.md"
  fi
else
  cat > "$PRINCIPLES" << 'EOF'
# PRINCIPLES.md

Operating principles for this agent. Add your own — these are just the starting structure.

## Regressions

Failures logged against the principle they tested. Format: what broke → why → what changed. Flag: 🔴 prompted (human caught it) | 🟢 autonomous (self-caught).

EOF
  echo "SETUP: Created PRINCIPLES.md with Regressions section"
fi
