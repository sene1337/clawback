# Crash Recovery Rules

Rules for long-running and batch operations. Learned the hard way when a Mac Mini reboot wiped ~50% of a Whisper batch (Phase 2, Feb 2026) because logs were in `/tmp/` and there was no resume manifest.

## 1. No Ephemeral Logs
Never write important logs to `/tmp/` or any location that doesn't survive a reboot. All batch job logs go to workspace directories (`logs/`, `docs/<project>/logs/`, or project-specific folders). If it matters, it lives in the workspace.

## 2. Manifest-Driven Batch Jobs
Any long-running task (transcription, bulk processing, migrations, etc.) must maintain a **progress manifest** in the workspace — a Markdown file tracking each item's status: pending, running, done, failed. Update it after every completion so you can resume from exactly where you left off. Logs tell you what happened; the manifest tells you where to restart.

## 3. Git Checkpoint Protocol
During batch jobs, commit the **manifest and progress files** to git **every ~10 completions or every 30 minutes**, whichever comes first. If the workspace file gets corrupted or the process dies, git has the last known-good state. This is in addition to the pre-operation checkpoint.

**Note:** Commit manifests and progress files — not raw log output. Log files (`*.log`, `logs/`) stay in `.gitignore`. The manifest IS your durable log.

## 4. Detached Execution
Batch processes must run **detached from the session** (`nohup`, LaunchAgent, or background process). Never tie a multi-hour job to a foreground session that dies on compaction, timeout, or reboot. The job must survive the agent dying.

## 5. Plan → Track → Verify (Project Files)
For any multi-step project or complex task, maintain structured project files:
- **Plan:** A plan file with steps, risks, and Definition of Done (if the user requests one)
- **Progress:** A progress file updated after each step
- If the plan changes mid-execution, update the plan file and note the pivot.

**File location:** If the workspace already has a project management structure, integrate into it. Otherwise default to `docs/projects/<name>/plan.md` and `docs/projects/<name>/progress.md`.
