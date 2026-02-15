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

Rules for long-running and batch operations. Learned the hard way when a Mac Mini reboot wiped ~50% of a Whisper batch (Phase 2, Feb 2026) because logs were in `/tmp/` and there was no resume manifest.

### 1. No Ephemeral Logs
Never write important logs to `/tmp/` or any location that doesn't survive a reboot. All batch job logs go to workspace directories (`logs/`, `docs/<project>/logs/`, or project-specific folders). If it matters, it lives in the workspace.

### 2. Manifest-Driven Batch Jobs
Any long-running task (transcription, bulk processing, migrations, etc.) must maintain a **progress manifest** in the workspace — a Markdown file tracking each item's status: pending, running, done, failed. Update it after every completion so you can resume from exactly where you left off. Logs tell you what happened; the manifest tells you where to restart.

### 3. Git Checkpoint Protocol
During batch jobs, commit the manifest and logs to git **every ~10 completions or every 30 minutes**, whichever comes first. If the workspace file gets corrupted or the process dies, git has the last known-good state. This is in addition to the pre-operation checkpoint.

### 4. Detached Execution
Batch processes must run **detached from the session** (`nohup`, LaunchAgent, or background process). Never tie a multi-hour job to a foreground session that dies on compaction, timeout, or reboot. The job must survive the agent dying.

## Notes

- Works on any OpenClaw workspace with git initialized
- Auto-detects workspace root via `git rev-parse --show-toplevel`
- Never force-pushes or rewrites history
- Checkpoint messages include timestamp + reason for auditability
- If PRINCIPLES.md doesn't have a `## Regressions` section, rollback creates one
