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

ROOT_RAW=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT_RAW" ]; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

ROOT=$(cd "$ROOT_RAW" && pwd -P)
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
  local last_byte

  if [ ! -f "$gitignore" ]; then
    echo ".worktrees/" > "$gitignore"
    return
  fi

  # Ensure the file ends with a newline before appending.
  if [ -s "$gitignore" ]; then
    last_byte=$(tail -c 1 "$gitignore" | od -An -t u1 | tr -d ' ')
    if [ "$last_byte" != "10" ]; then
      echo >> "$gitignore"
    fi
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
  local prune_branch=0
  local force_branch=0
  local path
  local current_root
  local default

  for arg in "${@:2}"; do
    case "$arg" in
      --prune-branch)
        prune_branch=1
        ;;
      --force-branch)
        force_branch=1
        ;;
      *)
        echo "ERROR: Unknown flag '$arg'" >&2
        echo "Usage: worktree.sh remove <branch> [--prune-branch] [--force-branch]" >&2
        exit 1
        ;;
    esac
  done

  if [ -z "$branch" ]; then
    echo "ERROR: Branch name required" >&2
    echo "Usage: worktree.sh remove <branch> [--prune-branch] [--force-branch]" >&2
    exit 1
  fi

  path="$WORKTREE_DIR/$branch"
  if [ ! -e "$path" ]; then
    echo "ERROR: Worktree not found: $branch" >&2
    exit 1
  fi

  current_root=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
  if [ "$current_root" = "$(cd "$path" && pwd -P)" ]; then
    echo "ERROR: Refusing to remove current worktree: $path" >&2
    exit 1
  fi

  git worktree remove "$path" --force

  if [ "$prune_branch" -eq 1 ]; then
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      default=$(default_branch)
      if [ "$force_branch" -eq 1 ]; then
        git branch -D "$branch" >/dev/null
        echo "WORKTREE: Removed $branch and pruned local branch (forced)"
      else
        if git branch -d "$branch" >/dev/null 2>&1; then
          echo "WORKTREE: Removed $branch and pruned local branch"
        else
          echo "ERROR: Branch '$branch' is not fully merged; refusing to delete." >&2
          echo "Hint: re-run with --force-branch if you intend to discard it." >&2
          exit 1
        fi
      fi
    else
      echo "WORKTREE: Removed $branch (no local branch to prune)"
    fi
  else
    echo "WORKTREE: Removed $branch (branch retained; use --prune-branch to delete)"
  fi
}

cleanup_worktrees() {
  local main
  local current_root
  local removed=0
  local line
  local path

  if [ ! -d "$WORKTREE_DIR" ]; then
    echo "WORKTREE: No .worktrees directory found."
    return
  fi

  main=$(cd "$ROOT" && pwd -P)
  current_root=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)

  while IFS= read -r line; do
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
  worktree.sh remove <branch> [--prune-branch] [--force-branch]
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
