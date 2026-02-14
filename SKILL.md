---
name: pre-flight
description: Git checkpoint before destructive or risky operations. Use before updating OpenClaw, deleting files, changing config, running migrations, or any operation that could break the workspace. Also supports rollback if something goes wrong.
---

# Pre-Flight Checkpoint

Run `scripts/checkpoint.sh` before any destructive operation. Run `scripts/rollback.sh` to undo if the operation fails.

## When to Use

- Before `update.run` or `config.apply`
- Before bulk file deletions or moves
- Before config/architecture changes
- Before any operation you'd regret if it failed

## Checkpoint

```bash
# On the node where the workspace lives:
bash /path/to/skills/pre-flight/scripts/checkpoint.sh "reason for checkpoint"
```

Returns a commit hash. Save it — that's your rollback point.

If nothing has changed since last commit, it prints the current HEAD hash (no empty commits).

## Rollback

```bash
bash /path/to/skills/pre-flight/scripts/rollback.sh <commit-hash>
```

Creates a revert commit (non-destructive — doesn't rewrite history).

## Notes

- Works on any OpenClaw workspace with git initialized
- Auto-detects workspace root via `git rev-parse --show-toplevel`
- Never force-pushes or rewrites history
- Checkpoint messages include timestamp + reason for auditability
