---
name: clawback
description: Git checkpoint before destructive or risky operations. Use before updating OpenClaw, deleting files, changing config, running migrations, or any operation that could break the workspace. Also supports rollback if something goes wrong.
---

# ClawBack

Run `scripts/checkpoint.sh` before any destructive operation. Run `scripts/rollback.sh` if the operation fails.

## When to Use

- Before `update.run` or `config.apply`
- Before bulk file deletions or moves
- Before config/architecture changes
- Before any operation you'd regret if it failed

## Checkpoint

```bash
bash scripts/checkpoint.sh "reason for checkpoint"
```

Returns a commit hash. Save it — that's your rollback point.

## Rollback

```bash
bash scripts/rollback.sh <commit-hash> "what broke" "why it broke" "which principle it tests"
```

Reverts to checkpoint (non-destructive) AND appends a regression entry to PRINCIPLES.md.

**All three reason arguments are required.** You can't rollback without logging what went wrong. This is intentional — if you're reverting, something failed, and failures are data.

## Regression Format

Rollback auto-appends to the `## Regressions` section in PRINCIPLES.md:

```
N. 🟢 **<what broke>** (<date>) — <what broke> → <why> → Rolled back to <hash>. Tests "<principle>".
```

Flag is always 🟢 (autonomous) since the skill forces the log mechanically.

## Crash Recovery

For long-running and batch operations, see [references/crash-recovery.md](references/crash-recovery.md) — covers ephemeral log avoidance, manifest-driven batches, git checkpoint protocol, detached execution, and Plan → Track → Verify.

## Notes

- Works on any OpenClaw workspace with git initialized
- Auto-detects workspace root via `git rev-parse --show-toplevel`
- Never force-pushes or rewrites history
- Checkpoint messages include timestamp + reason for auditability
- If PRINCIPLES.md doesn't have a `## Regressions` section, rollback creates one
