#!/bin/bash
# ClawBack pre-commit guardrails for local-only ops-state repos and generic secret blocking.
# Usage:
#   pre-commit-guard.sh [--repo <path>]
#   pre-commit-guard.sh --install [repo-path]

set -euo pipefail

SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")
REPO_DIR=""
INSTALL_MODE=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/pre-commit-guard.sh [--repo <path>]
  bash scripts/pre-commit-guard.sh --install [repo-path]

Runs secret/path guardrails against staged changes. If the repo contains
`.clawback-ops-state`, stricter allow/deny rules are enforced.
EOF
}

resolve_repo_dir() {
  local target="${1:-}"

  if [ -n "$target" ]; then
    if [ ! -d "$target" ]; then
      echo "ERROR: Repo path not found: $target" >&2
      exit 1
    fi
    (cd "$target" && git rev-parse --show-toplevel 2>/dev/null) || {
      echo "ERROR: Not a git repository: $target" >&2
      exit 1
    }
    return
  fi

  git rev-parse --show-toplevel 2>/dev/null || {
    echo "ERROR: Not inside a git repository" >&2
    exit 1
  }
}

install_hook() {
  local repo="$1"
  local hook

  hook="$repo/.git/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  cat > "$hook" <<EOF
#!/bin/bash
exec bash "$SCRIPT_PATH" --repo "$repo"
EOF
  chmod +x "$hook"
  echo "HOOK: Installed pre-commit guard at $hook"
}

is_ops_state_repo() {
  [ -f "$REPO_DIR/.clawback-ops-state" ]
}

path_denied_for_ops_state() {
  case "$1" in
    .git/*|snapshots/*|restore-staging/*|backups/*|*.tar|*.tar.gz|*.tgz|*.zip|*.db|*.sqlite|*.sqlite3|*.log|*.env|*.env.*|*.key|*.pem|*.p12|*.kdbx|*.jsonl)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_allowed_for_ops_state() {
  case "$1" in
    .clawback-ops-state|.gitignore|README.md|hooks/README.md|manifests/*|indexes/*|restores/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

scan_staged_paths() {
  local failed=0
  local path
  local remotes

  if is_ops_state_repo; then
    remotes=$(git -C "$REPO_DIR" remote)
    if [ -n "$remotes" ]; then
      echo "BLOCK: ops-state must remain local-only. Remove git remotes before committing." >&2
      failed=1
    fi
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue

    if is_ops_state_repo; then
      if path_denied_for_ops_state "$path"; then
        echo "BLOCK: Denied ops-state path staged: $path" >&2
        failed=1
        continue
      fi

      if ! path_allowed_for_ops_state "$path"; then
        echo "BLOCK: Path outside ops-state allowlist: $path" >&2
        failed=1
      fi
    fi
  done < <(git -C "$REPO_DIR" diff --cached --name-only --diff-filter=ACMR)

  return "$failed"
}

scan_staged_content() {
  local diff_output
  local pattern

  diff_output=$(git -C "$REPO_DIR" diff --cached --no-color --unified=0 --no-ext-diff || true)

  pattern='BEGIN [A-Z0-9 ]*PRIVATE KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|GITHUB_TOKEN|GH_TOKEN|ALBY_JWT|SLACK_BOT_TOKEN|TELEGRAM_BOT_TOKEN|AWS_SECRET_ACCESS_KEY|xox[baprs]-|ghp_[A-Za-z0-9]+|gho_[A-Za-z0-9]+|sk-[A-Za-z0-9]+'

  if printf '%s\n' "$diff_output" | grep -E "$pattern" >/dev/null 2>&1; then
    echo "BLOCK: Secret-like content detected in staged diff." >&2
    echo "Guidance: keep raw tokens/keys out of git; commit manifests and redacted metadata only." >&2
    return 1
  fi

  return 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --repo requires a path" >&2
        exit 1
      fi
      REPO_DIR="$2"
      shift 2
      ;;
    --install)
      INSTALL_MODE=1
      if [ "$#" -ge 2 ] && [ "${2#--}" = "$2" ]; then
        REPO_DIR="$2"
        shift 2
      else
        shift
      fi
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

REPO_DIR=$(resolve_repo_dir "$REPO_DIR")

if [ "$INSTALL_MODE" -eq 1 ]; then
  install_hook "$REPO_DIR"
  exit 0
fi

if ! scan_staged_paths; then
  echo "Guidance: ops-state git history is for manifests, indexes, and restore notes only." >&2
  exit 1
fi

if ! scan_staged_content; then
  exit 1
fi

exit 0
