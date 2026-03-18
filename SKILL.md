---
name: clawback
description: >
  Git safety workflow for AI agents. Use when the request says checkpoint,
  rollback, commit hygiene, worktree isolation, ops-state, runtime-state
  checkpoint/restore, or release hygiene for this skill. Do NOT use for general
  git tutoring, everyday branching advice, or non-agent
  backup/version-control workflows.
---

# ClawBack

Router for agent-safe git operations: commit-as-you-go, pre-risk checkpoints, rollback, worktree isolation, local-only runtime-state capture, and release checks.

## Workflow Map

- **Mode 1: Commit** — default working mode after every logical unit of work
- **Mode 2: Checkpoint** — create a rollback point before risky changes
- **Option C: Dual-Surface Setup** — initialize local-only `ops-state` for runtime-state manifests
- **Mode 3: Runtime State Checkpoint** — capture selected out-of-workspace state into ignored snapshots plus committed manifests
- **Mode 4: Runtime State Restore** — rehearse or run a checksum-verified overlay restore
- **Mode 5: Rollback** — revert to a safe commit and append a regression entry
- **Mode 6: Isolate** — use worktrees for risky or parallel branches
- **Mode 7: Release Hygiene** — enforce `VERSION` + `CHANGELOG.md` before publishing this skill

## Mode 1: Commit (Default Working Mode)

Commit after every logical unit of work: one fix, one feature, one config change, one doc change, or one refactor.

### How to commit

```bash
cd "$(git rev-parse --show-toplevel)"
git add -A  # or specific files
git commit -m "type: what changed — why"
```

### Commit message format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type: concise description of what changed — why (if not obvious)
```

Use these types:

- `feat:` new capability or feature
- `fix:` bug fix
- `docs:` documentation only
- `refactor:` code change that neither fixes a bug nor adds a feature
- `chore:` maintenance, dependencies, config, cleanup
- `perf:` performance improvement

Examples:

```
feat: replace Chatterbox with Piper TTS — 30x faster, Chatterbox took 30+ seconds
fix: Safari AudioContext — init on user gesture, not on chunk arrival
docs: add social consensus spec for benchmark governance
refactor: split voice handler into separate STT and TTS modules
chore: update .gitignore, remove tracked log files
```

- Limit the subject line to about 72 characters
- Use imperative mood
- Do not end the subject with a period
- Skip the "why" when it is already obvious

### What not to commit

- Logs or runtime output (`*.log`, `logs/`)
- Secrets, tokens, passwords, API keys
- Temp files or cache directories
- Large binary payloads
- Dependencies or build artifacts

For the rationale, heartbeat enforcement, anti-patterns, and subagent commit ownership, read [references/operating-discipline.md](references/operating-discipline.md).

## Commit Enforcement

### Heartbeat Check

Add to your `HEARTBEAT.md`:

```
- Run `git status --short` in workspace. If dirty, commit each changed file with a descriptive message.
```

Treat the heartbeat check as a safety net, not a replacement for committing in the moment. See [references/operating-discipline.md](references/operating-discipline.md) for drift rationale and anti-patterns.

## Subagent Commit Ownership

Subagents write and save files only. The main session reviews output, commits accepted work, and updates task or log state. See [references/operating-discipline.md](references/operating-discipline.md) for the reasoning and AGENTS.md snippet.

## Mode 2: Checkpoint (Before Risk)

Use before any operation you'd regret if it failed.

```bash
bash scripts/checkpoint.sh "reason for checkpoint"
```

This returns the commit hash you can roll back to.

### When to checkpoint

- Before `update.run` or `config.apply`
- Before bulk deletions or moves
- Before config or architecture changes
- Before any operation that could break the workspace

## Option C: Dual-Surface Setup

Use this when the task touches both the workspace repo and runtime state outside it.

```bash
bash scripts/setup.sh
bash scripts/init-ops-state.sh
```

Surface model:

- **Workspace repo:** source, docs, scripts, and durable project artifacts
- **ops-state repo:** local-only manifests, checkpoint indexes, and restore notes
- **Ignored local payloads:** raw runtime snapshots under `ops-state/snapshots/`

The `ops-state` repo installs `scripts/pre-commit-guard.sh` as a git hook. It blocks remotes, raw snapshots, DB files, session exports, logs, `.env` material, and obvious secret-like staged content. For the full model, see [references/ops-state.md](references/ops-state.md).

## Mode 3: Runtime State Checkpoint

Use this before touching selected out-of-workspace runtime surfaces.

```bash
bash scripts/state-checkpoint.sh --name "before live queue migration"
```

Default profile: `openclaw-core`

- `~/.openclaw/lcm.db`
- `~/.openclaw/agents/*/sessions`

Useful flags:

```bash
bash scripts/state-checkpoint.sh --path ~/.openclaw/lcm.db --path ~/.openclaw/agents/main/sessions
bash scripts/state-checkpoint.sh --manifest-only --name "inventory only"
bash scripts/state-checkpoint.sh --dry-run
```

Safety rules:

- Refuses workspace paths
- Refuses `ops-state` internals
- Stores raw payloads only in ignored local snapshots
- Commits manifests and checkpoint indexes to `ops-state`

## Mode 4: Runtime State Restore

Restore is dry-run by default and verifies the recorded checksum before doing anything.

```bash
bash scripts/state-restore.sh <checkpoint-id> --dry-run
```

Real restore requires explicit confirmation:

```bash
bash scripts/state-restore.sh <checkpoint-id> --yes-restore
```

Restore semantics:

- Overlay restore only; files created after the checkpoint are preserved
- Refuses workspace and `ops-state` paths from the manifest
- Writes a restore note back to the local `ops-state` repo

## Mode 5: Rollback (When Things Break)

```bash
bash scripts/rollback.sh <commit-hash> "what broke" "why it broke" "which principle it tests" [--prompted]
```

This reverts to the checkpoint, cleans untracked files created after it, and appends a regression entry to `ops/continuous-improvement/regressions.md`.

All four reason arguments are required. Failures are data.

The `--prompted` flag marks the regression as human-caught (`🔴`). Default is self-caught (`🟢`).

### Regression storage

- **Active (last 10):** `ops/continuous-improvement/regressions.md`
- **Archive:** `ops/continuous-improvement/regression-archive.md`
- **PRINCIPLES.md:** stable rules only, no volatile history

### Regression format

Auto-appended to `ops/continuous-improvement/regressions.md`:

```
N. 🟢 **<what broke>** (<date>) — <what broke> → <why> → Rolled back to <hash>. Tests "<principle>".
```

## Mode 6: Isolate (Worktree for Parallel or Risky Work)

Use a separate worktree for large refactors, risky migrations, or parallel feature streams.

```bash
bash scripts/worktree.sh create feat-branch-name
bash scripts/worktree.sh list
bash scripts/worktree.sh path feat-branch-name
cd "$(bash scripts/worktree.sh path feat-branch-name)"
```

### Rules

- Do not call `git worktree add` directly; use `scripts/worktree.sh`
- Base new worktrees from the default branch unless you have a reason not to
- Before deleting worktrees, make sure changes are merged or intentionally discarded.
- For cleanup, use `bash scripts/worktree.sh remove <branch> --prune-branch`
- Add `--force-branch` only when intentionally discarding unmerged work

## Mode 7: Release Hygiene (Before Publishing This Skill)

Before publishing this repo, validate release metadata:

```bash
bash scripts/release-check.sh [base-ref]
```

The check enforces:

- `VERSION` exists and is valid semver
- `VERSION` is bumped versus `base-ref` when skill files change
- `CHANGELOG.md` is updated and includes a section for the current `VERSION`

For policy and checklist details, read [references/versioning.md](references/versioning.md).

## Daily Log Discipline

Daily logs (`memory/YYYY-MM-DD.md`) are standup summaries, not debug transcripts.

- Keep each project entry to 5 lines max
- Target 60-80 lines total per day; hard cap at 100
- Put long explanations in git history or the relevant `docs/` file

For formatting examples and routing rules, read [references/operating-discipline.md](references/operating-discipline.md).

## Context Hygiene

If a tool result is large and you need the data, write it to a file immediately. Batch external calls, reference file paths instead of pasting large results, and checkpoint before long or fragile operations. Detailed heuristics live in [references/operating-discipline.md](references/operating-discipline.md).

## .gitignore Rules

Keep logs, caches, secrets, build artifacts, and other runtime payloads out of git. If something is already tracked, remove it with `git rm --cached` and update `.gitignore`. Baseline patterns and cleanup guidance are in [references/operating-discipline.md](references/operating-discipline.md).

## Publishing Skills to GitHub

Before pushing any skill repo to GitHub, read the bundled guide [references/skill-publishing.md](references/skill-publishing.md) and follow the canonical workspace SOP at `ops/playbooks/skill-building/sops/skill-publishing.md`. Keep paths relative in published skill content (no absolute `/Users/...` paths). Never push from the workspace root — workspace git is local-only.

## Crash Recovery

For long-running and batch operations, read [references/crash-recovery.md](references/crash-recovery.md).

## Quick Reference

| Situation | Action |
|-----------|--------|
| Just finished a fix | `git commit -m "fix: what — why"` |
| Just added a feature | `git commit -m "feat: what — why"` |
| About to do something risky | `bash scripts/checkpoint.sh "reason"` |
| Need local runtime-state tracking | `bash scripts/init-ops-state.sh` |
| About to touch out-of-workspace runtime state | `bash scripts/state-checkpoint.sh --name "reason"` |
| Need to rehearse a runtime restore | `bash scripts/state-restore.sh <checkpoint-id> --dry-run` |
| Something broke after a change | `bash scripts/rollback.sh <hash> "what" "why" "principle"` |
| Need isolated parallel work | `bash scripts/worktree.sh create <branch>` |
| Need to clean up old worktrees | `bash scripts/worktree.sh cleanup` |
| Preparing to publish skill updates | `bash scripts/release-check.sh [base-ref]` |
| Writing daily log | Max 5 lines per project, 60-80 lines total |
| Found a log file in git | `git rm --cached`, then update `.gitignore` |

## Notes

- Root `README.md`, `CHANGELOG.md`, and `VERSION` stay because `scripts/release-check.sh` and the publish workflow depend on them.
- Works on any OpenClaw workspace with git initialized
- Auto-detects workspace root via `git rev-parse --show-toplevel`
- Never force-pushes or rewrites history
- Checkpoint messages include timestamp + reason for auditability
- Regressions log to `ops/continuous-improvement/regressions.md`
- Option C adds a local-only `ops-state` repo plus snapshot or restore primitives for selected runtime state
- `scripts/pre-commit-guard.sh` blocks raw payloads and obvious secrets from `ops-state` git history
- Worktrees are managed in `.worktrees/` via `scripts/worktree.sh`
