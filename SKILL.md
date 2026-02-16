---
name: clawback
description: Git workflow for AI agents — commit-as-you-go, checkpoints before risk, rollback when things break. Also governs daily log discipline and .gitignore hygiene. Use for all version control decisions, before destructive operations, and when writing daily memory logs.
---

# ClawBack

A complete git workflow for AI agents. Three modes: **Commit** (your default), **Checkpoint** (before risk), **Rollback** (when things break).

## Mode 1: Commit (Default Working Mode)

**This is your primary mode.** Commit after every logical unit of work — one fix, one feature, one config change. Your git log should read like a changelog.

### When to commit

- After fixing a bug
- After adding a feature or capability
- After a config change
- After writing or updating documentation
- After refactoring code
- Basically: after every distinct thing you complete

### How to commit

```bash
cd $(git rev-parse --show-toplevel)
git add -A  # or specific files
git commit -m "type: what changed — why"
```

No script needed. Keep friction near zero so you commit more, not less.

### Commit message format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type: concise description of what changed — why (if not obvious)
```

**Types:**
| Type | When |
|------|------|
| `feat:` | New capability or feature |
| `fix:` | Bug fix |
| `docs:` | Documentation only |
| `refactor:` | Code change that neither fixes a bug nor adds a feature |
| `chore:` | Maintenance, dependencies, config, cleanup |
| `perf:` | Performance improvement |

**Examples:**
```
feat: replace Chatterbox with Piper TTS — 30x faster, Chatterbox took 30+ seconds
fix: Safari AudioContext — init on user gesture, not on chunk arrival
docs: add social consensus spec for benchmark governance
refactor: split voice handler into separate STT and TTS modules
chore: update .gitignore, remove tracked log files
```

**Rules from [How to Write a Git Commit Message](https://cbea.ms/git-commit/):**
- Limit subject line to ~72 characters
- Use imperative mood ("add" not "added", "fix" not "fixed")
- Don't end with a period
- If the "why" is obvious from the "what", skip it

### Why this matters

Your git history IS your debug log. If you commit properly during work:

```
e3ce305 fix: Safari AudioContext — init on user gesture, not on chunk arrival
a2b1f09 feat: replace Chatterbox with Piper TTS — 30x faster
6fc28af fix: resample 48kHz→16kHz for Whisper, cast float64→float32
b8d9e12 feat: add LaunchAgent for auto-start on boot
```

That tells the full story. Each change is individually revertable. The daily log becomes a 5-line summary referencing commit hashes — not a 70-line debugging transcript. Detail lives in git (free, searchable, zero boot tokens), not in memory files (expensive, reloads every session).

### What NOT to commit

- Log files or runtime output (`*.log`, `logs/`)
- Secrets, tokens, passwords, API keys
- Temp files, cache directories
- Large binary files (media, datasets >1MB)
- Node modules, Python venvs, build artifacts

## Mode 2: Checkpoint (Before Risk)

Same as before. Use before any operation you'd regret if it failed.

```bash
bash scripts/checkpoint.sh "reason for checkpoint"
```

Returns a commit hash — your rollback point.

### When to checkpoint

- Before `update.run` or `config.apply`
- Before bulk file deletions or moves
- Before config/architecture changes
- Before any operation that could break the workspace

## Mode 3: Rollback (When Things Break)

```bash
bash scripts/rollback.sh <commit-hash> "what broke" "why it broke" "which principle it tests"
```

Reverts to checkpoint (non-destructive) AND appends a regression entry to PRINCIPLES.md.

**All three reason arguments are required.** You can't rollback without logging what went wrong. Failures are data.

### Regression format

Auto-appended to `## Regressions` in PRINCIPLES.md:

```
N. 🟢 **<what broke>** (<date>) — <what broke> → <why> → Rolled back to <hash>. Tests "<principle>".
```

## Daily Log Discipline

Daily logs (`memory/YYYY-MM-DD.md`) are **standup updates, not debug transcripts.**

### Format per project entry

```markdown
### Project Name
- What changed (reference commit hashes for detail)
- What's blocked
- What's next
```

**Max 5 lines per project.** If a fix needs documentation for future reference, write it in the relevant `docs/` file — not the daily log.

### Line budget

- **Target:** 60-80 lines total per day
- **Hard cap:** 100 lines
- **If you're over 100:** you're writing debug transcripts. Move the detail to git commits or docs/ files.

### What goes in daily logs vs. elsewhere

| Detail | Where it goes |
|--------|--------------|
| "Fixed X, working now" | Daily log (1 line + commit hash) |
| Step-by-step debugging | Git commit messages (already there if you committed as you went) |
| How a system works / config details | `docs/` file |
| Decision and reasoning | Daily log (2-3 lines) or decision ledger |
| Error messages, stack traces | Nowhere persistent — they served their purpose |

### Example: good vs. bad

**Bad (50 lines for one project):**
```
### openclaw-voice
- Tried Chatterbox TTS, took 30+ seconds per response
- Found Piper TTS, installed via pip
- Had to fix ONNX runtime dependency
- Piper works but output is 22kHz, need to resample
- Fixed resampling with scipy
- Then Safari wouldn't play audio
- Safari needs user gesture for AudioContext
- Fixed by initializing on button click
- Then Whisper was getting garbled input
- Input was 48kHz, Whisper expects 16kHz
- Added resampling in the receive path too
- Now it works end to end
...
```

**Good (4 lines):**
```
### openclaw-voice
- Two-way voice working: Piper TTS + Whisper STT, Safari frontend (`a2b1f09`..`b8d9e12`)
- Key fixes: AudioContext user gesture init, 48→16kHz resampling for Whisper
- Pending: LaunchAgent for auto-start, VAD chunk size fix
```

## Context Hygiene

Your context window is a finite, non-renewable resource within a session. Treat it like RAM — fill it and you crash.

### The Rule

**If a tool result is large and you need the data, write it to a file immediately.** Don't hold it in context hoping to use it later. Extract what you need, save it, move on.

### Context Budget

- **Total context:** 200K tokens (~800K chars)
- **Compaction reserve:** ~80K tokens
- **Usable working memory:** ~120K tokens (~480K chars)
- **Single web_fetch result:** 50-400K chars (can be 25-80% of your budget in one call)

### Warning Signs

You're about to blow context if:
- You've done 3+ web_fetch calls without writing results to disk
- You're holding multiple large tool results while planning what to do with them
- You're in a long session with lots of back-and-forth AND large tool results

### What To Do

1. **Write to disk immediately.** After any large tool result, extract the data you need and save it to a file.
2. **Batch external calls.** 50 URLs? Do 5-10 at a time with disk writes between batches.
3. **Reference, don't repeat.** Once data is in a file, reference the file path — don't paste the contents back.
4. **Checkpoint before heavy operations.** If a batch job might crash, checkpoint first so you can resume.

## .gitignore Rules

Every workspace should have these in `.gitignore`:

```
*.log
logs/
*.pyc
__pycache__/
node_modules/
.env
*.secret
*.key
data/
```

If you find a log file or runtime artifact tracked in git, remove it:

```bash
git rm --cached path/to/file.log
echo "path/to/file.log" >> .gitignore
git commit -m "chore: remove tracked log file, update .gitignore"
```

## Crash Recovery

For long-running and batch operations, see [references/crash-recovery.md](references/crash-recovery.md) — covers ephemeral log avoidance, manifest-driven batches, git checkpoint protocol, detached execution, and Plan → Track → Verify.

## Quick Reference

| Situation | Action |
|-----------|--------|
| Just finished a fix | `git commit -m "fix: what — why"` |
| Just added a feature | `git commit -m "feat: what — why"` |
| About to do something risky | `bash scripts/checkpoint.sh "reason"` |
| Something broke after a change | `bash scripts/rollback.sh <hash> "what" "why" "principle"` |
| Writing daily log | Max 5 lines/project, reference commits, target 60-80 lines total |
| Found a log file in git | `git rm --cached`, add to `.gitignore` |

## Notes

- Works on any OpenClaw workspace with git initialized
- Auto-detects workspace root via `git rev-parse --show-toplevel`
- Never force-pushes or rewrites history
- Checkpoint messages include timestamp + reason for auditability
- If PRINCIPLES.md doesn't have a `## Regressions` section, rollback creates one
