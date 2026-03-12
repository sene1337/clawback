# 🦀 ClawBack

**Git checkpoint, runtime-state recovery, and regression tracking for OpenClaw agents.**

Checkpoint before risky operations. Rollback when things break. Isolate risky parallel work in worktrees. Enforce version/changelog discipline before publishing.

## Why This Exists

AI agents make mistakes. They delete files, push bad configs, run updates that break things. That's expected — they're operating autonomously in complex environments.

What's *not* expected is making the same mistake twice.

Most agents have no mechanism for learning from operational failures. They forget between sessions. Context gets compacted. The same error happens again three days later because nothing was recorded.

**ClawBack solves this with three linked mechanisms:**

### 1. Checkpoint & Rollback (Safety Net)

Before any destructive operation — updates, deletions, config changes — the agent commits everything to git. If the operation fails, it reverts cleanly. No lost work, no panic.

### 2. Forced Regression Logging (Learning Loop)

Here's the key insight: **you can't rollback without explaining what went wrong.**

When an agent rolls back, ClawBack requires three things:
- **What broke** — the specific failure
- **Why it broke** — root cause, not just symptoms
- **What principle it tests** — which operating rule was violated

This gets appended to `ops/continuous-improvement/regressions.md` as a regression entry. Over time, this creates a failure log that:

- **Survives context compaction** — it's in a file, not chat history
- **Shows patterns** — repeated failures in the same area reveal systemic issues
- **Creates accountability** — you can see whether your agent self-catches failures (🟢) or needs to be corrected (🔴)
- **Measures growth** — a rising 🟢/🔴 ratio means your agent is actually learning

### 3. Option C Runtime-State Recovery

Workspace git only protects files inside the workspace repo. ClawBack's Option C flow adds a second local-only git surface, `ops-state`, for:

- checkpoint manifests
- checkpoint indexes
- restore event notes

Raw runtime payloads stay local in ignored snapshot files, not in git. This makes it possible to checkpoint selected out-of-workspace state like `~/.openclaw/lcm.db` or session directories without pushing volatile payloads into the workspace history.

### For Humans

Your agent is going to break things. The question isn't *if* — it's whether you have a record of what broke and evidence that it learned. ClawBack gives you that record automatically.

Review your agent's regression log periodically. Look for:
- **Repeated failures** — same principle violated twice = the principle isn't internalized
- **🔴 dominance** — you're catching more failures than the agent = it's not self-correcting
- **Empty log** — either your agent is perfect (unlikely) or it's not logging (fix this)

### For Agents

Every failure is data. The regression log isn't punishment — it's your memory. Without it, you'll repeat the same mistakes after every context reset. With it, you compound operational knowledge across sessions.

The 🟢/🔴 flag is your scorecard. 🟢 means you caught it yourself. 🔴 means your human had to point it out. Track your ratio. Improve it.

## Install

Copy the `skills/clawback` folder into your OpenClaw workspace's `skills/` directory, or clone:

```bash
git clone https://github.com/sene1337/clawback.git skills/clawback
```

## Setup

Run the setup scripts to create the regression log and local ops-state surface:

```bash
bash skills/clawback/scripts/setup.sh
bash skills/clawback/scripts/init-ops-state.sh
```

This creates:

- `ops/continuous-improvement/regressions.md` in the workspace repo
- `~/.openclaw/ops-state` as a local-only git repo for manifests and restore notes

See [references/ops-state.md](references/ops-state.md) for the dual-surface model and guardrails.

## Usage

### Commit as you go
```bash
git add -A
git commit -m "type: what changed — why"
```

### Before risky operations:
```bash
bash skills/clawback/scripts/checkpoint.sh "reason for checkpoint"
# Returns: commit hash (save this)
```

### Before touching out-of-workspace runtime state:
```bash
bash skills/clawback/scripts/state-checkpoint.sh --name "before live queue migration"
# Captures selected runtime payloads into ignored local snapshots
# Commits the manifest and checkpoint index to ops-state
```

Dry-run a restore:
```bash
bash skills/clawback/scripts/state-restore.sh <checkpoint-id> --dry-run
```

### If the operation fails:
```bash
bash skills/clawback/scripts/rollback.sh <hash> "what broke" "why" "principle tested"
# Reverts files AND logs regression to ops/continuous-improvement/regressions.md
# Add --prompted flag if a human caught the error (🔴)
```

### Isolate risky or parallel work (worktrees):
```bash
bash skills/clawback/scripts/worktree.sh create feat-branch-name
bash skills/clawback/scripts/worktree.sh list
cd "$(bash skills/clawback/scripts/worktree.sh path feat-branch-name)"
```

To remove a worktree and also prune its local branch:
```bash
bash skills/clawback/scripts/worktree.sh remove feat-branch-name --prune-branch
```

### Before publishing skill changes:
```bash
bash skills/clawback/scripts/release-check.sh origin/main
# Verifies VERSION + CHANGELOG discipline for skill changes
```

See `references/versioning.md` for full release rules (baseline `1.4.0`).

## Crash Recovery

Added after a Mac Mini reboot wiped ~50% of a Whisper transcription batch. The logs were in `/tmp/`, there was no resume manifest, and the job was tied to a foreground session. Every mistake you can make with a long-running batch job, we made it.

Four rules for any batch or long-running operation:

### 1. No Ephemeral Logs
Never write logs to `/tmp/` or anywhere that doesn't survive a reboot. Batch job logs belong in the workspace (`logs/`, `docs/<project>/logs/`). If it matters, it lives where git can see it.

### 2. Manifest-Driven Batch Jobs
Maintain a progress manifest (Markdown table) tracking each item: pending, running, done, failed. Update after every completion. Logs tell you what happened — the manifest tells you where to resume.

### 3. Periodic Git Checkpoints
During batch jobs, commit the **manifest and progress files** every **~10 completions or 30 minutes** (whichever comes first). Git becomes your last-known-good state even if the workspace file gets corrupted mid-run. Commit manifests — not raw log output. Log files stay in `.gitignore`.

### 4. Detached Execution
Batch processes run detached (`nohup`, LaunchAgent, background). Never tie a multi-hour job to a session that dies on compaction, timeout, or reboot. The job must survive the agent dying.

These aren't suggestions — they're the rules that would have saved us hours of re-transcription.

## Design Principles

- **Zero dependencies** — just bash + git
- **Non-destructive** — never force-pushes or rewrites history
- **Dual-surface** — workspace git for source; local-only `ops-state` for runtime-state manifests and restore notes
- **Cross-platform** — macOS + Linux compatible
- **Mechanically enforced** — can't skip the regression log on rollback
- **Guarded by default** — `ops-state` installs a pre-commit allow/deny hook for secrets and raw payloads
- **Isolated by default for risky parallel work** — worktree wrapper keeps branch state clean
- **Release metadata is a gate, not a suggestion** — version + changelog are validated by script
- **Portable** — works on any OpenClaw workspace with git initialized

## Origin

Built by [Sene](https://github.com/sene1337), an OpenClaw agent, after failing to checkpoint before an update. The human caught it. Now the tooling makes it impossible to skip.

That's the whole point: **turn failures into mechanics, not resolutions.**

## Research & Background

These resources explain why structured failure tracking matters for AI agents:

- **StructMemEval** (Yandex Research, Feb 2026) — [arXiv:2602.11243](https://arxiv.org/abs/2602.11243) — Found that structure hints in agent memory improve recall from 4/10 to 10/10. Consistent templates with explicit section headers act as retrieval anchors. The regression log format in ClawBack is designed around this finding.

- **"Why Your Agent Needs a Principles.md"** (Atlas Forge, Feb 2026) — [Post on X](https://x.com/atlasforgeai/status/2021773566341988758) — Makes the case for a principles file as a decision-making layer separate from personality (SOUL.md) and operations (AGENTS.md). The key insight: untested principles are just vibes. Adversarial review and regression tracking are what make principles real.

- **OpenClaw Agent Memory Patterns** (@kaostyl, Feb 2026) — Validated: memory split (long-term + daily logs), cron over heartbeats for reliability, small HEARTBEAT.md, skill routing with explicit triggers. Introduced the `active-tasks.md` crash recovery pattern. Demonstrated that structured operational memory compounds across sessions.

### The Core Insight

Agents lose context between sessions. Chat history gets compacted. Without a persistent, structured record of failures, agents repeat the same mistakes on a 3-5 day cycle. The regression log breaks this cycle by making failures durable — they survive compaction, restarts, and model swaps.

The 🟢/🔴 flag adds a second dimension: not just *what* failed, but *who caught it*. An agent that self-catches failures (🟢) is developing operational awareness. An agent that only logs when prompted (🔴) is just keeping a diary for its human. The ratio tells you which one you have.

## License

MIT
