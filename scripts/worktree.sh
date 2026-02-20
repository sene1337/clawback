#!/bin/bash
# ClawBack worktree manager - deterministic wrapper around git worktree.
# Usage:
#   worktree.sh create <branch> [base-branch]
#   worktree.sh list
#   worktree.sh path <branch>
#   worktree.sh remove <branch>
#   worktree.sh cleanup
#   worktree.sh help

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

WORKTREE_DIR="$ROOT/.worktrees"

default_branch() {
  local branch

  branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
  if [ -n "$branch" ]; then
    echo "$branch"
    return
  fi

  if git show-ref --verify --quiet refs/heads/main || git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "main"
    return
  fi

  if git show-ref --verify --quiet refs/heads/master || git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "master"
    return
  fi

  git rev-parse --abbrev-ref HEAD
}

ensure_gitignore() {
  local gitignore="$ROOT/.gitignore"

  if [ ! -f "$gitignore" ]; then
    echo ".worktrees/" > "$gitignore"
    return
  fi

  if ! grep -Eq '^\.worktrees/?$' "$gitignore"; then
    echo ".worktrees/" >> "$gitignore"
  fi
}

resolve_base_ref() {
  local base="$1"

  if git rev-parse --verify --quiet "origin/$base" >/dev/null; then
    echo "origin/$base"
    return
  fi

  if git rev-parse --verify --quiet "$base" >/dev/null; then
    echo "$base"
    return
  fi

  echo ""
}

create_worktree() {
  local branch="${1:-}"
  local base="${2:-}"
  local base_ref
  local path

  if [ -z "$branch" ]; then
    echo "ERROR: Branch name required" >&2
    echo "Usage: worktree.sh create <branch> [base-branch]" >&2
    exit 1
  fi

  if [ -z "$base" ]; then
    base=$(default_branch)
  fi

  base_ref=$(resolve_base_ref "$base")
  if [ -z "$base_ref" ]; then
    echo "ERROR: Base branch '$base' not found locally or on origin" >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/$branch" || git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    echo "ERROR: Branch '$branch' already exists" >&2
    exit 1
  fi

  path="$WORKTREE_DIR/$branch"
  if [ -e "$path" ]; then
    echo "ERROR: Worktree path already exists: $path" >&2
    exit 1
  fi

  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  git worktree add -b "$branch" "$path" "$base_ref" >/dev/null
  echo "WORKTREE: Created $branch from $base_ref at $path" >&2
  echo "$path"
}

list_worktrees() {
  git worktree list
}

worktree_path() {
  local branch="${1:-}"
  local path

  if [ -z "$branch" ]; then
    echo "ERROR: Branch name required" >&2
    echo "Usage: worktree.sh path <branch>" >&2
    exit 1
  fi

  path="$WORKTREE_DIR/$branch"
  if [ ! -e "$path" ]; then
    echo "ERROR: Worktree not found: $branch" >&2
    exit 1
  fi

  echo "$path"
}

remove_worktree() {
  local branch="${1:-}"
  local path
  local current_root

  if [ -z "$branch" ]; then
    echo "ERROR: Branch name required" >&2
    echo "Usage: worktree.sh remove <branch>" >&2
    exit 1
  fi

  path="$WORKTREE_DIR/$branch"
  if [ ! -e "$path" ]; then
    echo "ERROR: Worktree not found: $branch" >&2
    exit 1
  fi

  current_root=$(git rev-parse --show-toplevel)
  if [ "$current_root" = "$(cd "$path" && pwd -P)" ]; then
    echo "ERROR: Refusing to remove current worktree: $path" >&2
    exit 1
  fi

  git worktree remove "$path" --force
  echo "WORKTREE: Removed $branch"
}

cleanup_worktrees() {
  local main
  local current_root
  local removed=0

  if [ ! -d "$WORKTREE_DIR" ]; then
    echo "WORKTREE: No .worktrees directory found."
    return
  fi

  main=$(cd "$ROOT" && pwd -P)
  current_root=$(git rev-parse --show-toplevel)

  while IFS= read -r line; do
    local path
    path=$(echo "$line" | awk '{print $1}')

    if [[ "$path" != "$WORKTREE_DIR/"* ]]; then
      continue
    fi

    if [ "$(cd "$path" && pwd -P)" = "$main" ]; then
      continue
    fi

    if [ "$(cd "$path" && pwd -P)" = "$current_root" ]; then
      continue
    fi

    if git worktree remove "$path" --force; then
      removed=$((removed + 1))
    fi
  done < <(git worktree list)

  if [ "$removed" -eq 0 ]; then
    echo "WORKTREE: No removable worktrees found."
  else
    echo "WORKTREE: Removed $removed worktree(s)."
  fi

  if [ -d "$WORKTREE_DIR" ] && [ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]; then
    rmdir "$WORKTREE_DIR" 2>/dev/null || true
  fi
}

show_help() {
  cat <<'EOF'
ClawBack worktree manager

Usage:
  worktree.sh create <branch> [base-branch]
  worktree.sh list
  worktree.sh path <branch>
  worktree.sh remove <branch>
  worktree.sh cleanup
  worktree.sh help
EOF
}

main() {
  local cmd="${1:-help}"

  case "$cmd" in
    create)
      create_worktree "${2:-}" "${3:-}"
      ;;
    list|ls)
      list_worktrees
      ;;
    path)
      worktree_path "${2:-}"
      ;;
    remove|rm)
      remove_worktree "${2:-}"
      ;;
    cleanup|clean)
      cleanup_worktrees
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      echo "ERROR: Unknown command '$cmd'" >&2
      show_help
      exit 1
      ;;
  esac
}

main "$@"
