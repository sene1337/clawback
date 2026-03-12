#!/bin/bash
# ClawBack release gate.
# Enforces VERSION + CHANGELOG discipline when skill files change.
#
# Usage:
#   release-check.sh [base-ref]
#
# Example:
#   bash scripts/release-check.sh origin/main

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

cd "$ROOT"

BASE_REF="${1:-origin/main}"
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  if git rev-parse --verify --quiet main >/dev/null; then
    BASE_REF="main"
  elif git rev-parse --verify --quiet HEAD~1 >/dev/null; then
    BASE_REF="HEAD~1"
  else
    BASE_REF="HEAD"
  fi
fi

VERSION_FILE="VERSION"
CHANGELOG_FILE="CHANGELOG.md"

if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: Missing VERSION file." >&2
  exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "ERROR: Missing CHANGELOG.md file." >&2
  exit 1
fi

version=$(tr -d '[:space:]' < "$VERSION_FILE")
if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: VERSION must be semver (X.Y.Z). Found: '$version'" >&2
  exit 1
fi

if ! grep -Eq "^## \\[$version\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$CHANGELOG_FILE"; then
  echo "ERROR: CHANGELOG.md must contain '## [$version] - YYYY-MM-DD'" >&2
  exit 1
fi

committed_changes=$(git diff --name-only "$BASE_REF"..HEAD || true)
working_changes=$(git status --porcelain | awk '{print $2}')
all_changes=$(printf '%s\n%s\n' "$committed_changes" "$working_changes" | sed '/^$/d' | sort -u || true)

needs_release_bump=0
while IFS= read -r file; do
  case "$file" in
    SKILL.md|README.md|references/*|scripts/*)
      needs_release_bump=1
      break
      ;;
  esac
done <<< "$all_changes"

if [ "$needs_release_bump" -eq 0 ]; then
  echo "RELEASE CHECK: No skill-file changes detected vs $BASE_REF."
  exit 0
fi

if ! echo "$all_changes" | grep -Fxq "VERSION"; then
  echo "ERROR: Skill files changed, but VERSION was not updated." >&2
  exit 1
fi

if ! echo "$all_changes" | grep -Fxq "CHANGELOG.md"; then
  echo "ERROR: Skill files changed, but CHANGELOG.md was not updated." >&2
  exit 1
fi

base_version=""
if git cat-file -e "$BASE_REF:$VERSION_FILE" 2>/dev/null; then
  base_version=$(git show "$BASE_REF:$VERSION_FILE" | tr -d '[:space:]')
fi

if [ -n "$base_version" ] && echo "$base_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  latest=$(printf '%s\n%s\n' "$base_version" "$version" | sort -V | tail -n 1)
  if [ "$latest" != "$version" ] || [ "$base_version" = "$version" ]; then
    echo "ERROR: VERSION must increase. Base: $base_version, Current: $version" >&2
    exit 1
  fi
fi

echo "RELEASE CHECK: PASS"
echo "  Base ref: $BASE_REF"
echo "  Version:  $version"
