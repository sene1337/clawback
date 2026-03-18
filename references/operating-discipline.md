# Operating Discipline

Read this when you need the rationale and longer examples behind ClawBack's working rules.

## Contents

- [Commit discipline](#commit-discipline)
- [Heartbeat enforcement](#heartbeat-enforcement)
- [Subagent commit ownership](#subagent-commit-ownership)
- [Daily log discipline](#daily-log-discipline)
- [Context hygiene](#context-hygiene)
- [.gitignore baseline](#gitignore-baseline)

## Commit Discipline

### Why this matters

Your git history is your debug log. If you commit properly during work:

```text
e3ce305 fix: Safari AudioContext — init on user gesture, not on chunk arrival
a2b1f09 feat: replace Chatterbox with Piper TTS — 30x faster
6fc28af fix: resample 48kHz→16kHz for Whisper, cast float64→float32
b8d9e12 feat: add LaunchAgent for auto-start on boot
```

That tells the full story. Each change is individually revertable. The daily log becomes a short summary that references commit hashes instead of replaying the full debug session. Detail lives in git, not in memory files that reload every session.

## Heartbeat Enforcement

### Why mechanical enforcement

The commit rule works when it is fresh in context. After compaction, it drifts: you batch changes, forget to commit, and `git log` stops being a reliable record. When that happens:

- Post-compaction sessions cannot tell what was already done
- You recommend changes that are already live
- You revert working fixes because you do not trust your own history

The heartbeat check catches that drift automatically. It is a safety net, not a replacement for committing in the moment.

### Anti-patterns

- **Batch commits at end of session** — each change needs its own commit when it happens
- **Catch-up commits with vague messages** — `"commit various changes"` is useless in `git log`
- **Reverting without checking git log first** — if you are unsure whether a change already landed, start with `git log --oneline -20`

## Subagent Commit Ownership

Subagents write and save files only. The main session:

1. Reviews the output against the quality gate
2. Commits accepted work with the right message
3. Updates task state and daily log in the same step
4. Fixes or rejects bad output without committing garbage to history

### Why main session owns commits

When subagents self-commit:

- Garbage output can land in git history before anyone reviews it
- The commit message is written by the subagent, not the session with full context
- The log update step gets skipped because it happened "elsewhere"
- Post-compaction, you cannot tell whether the commit represents good or bad output

Quality gate and git history stay with the main session. Do not delegate them.

### AGENTS.md snippet

```text
Subagents write/save files only. Main session owns all git commits, quality review, and log entries.
```

## Daily Log Discipline

Daily logs (`memory/YYYY-MM-DD.md`) are standup updates, not debug transcripts.

### Format per project entry

```markdown
### Project Name
- What changed (reference commit hashes for detail)
- What's blocked
- What's next
```

### Line budget

- Target: 60-80 lines total per day
- Hard cap: 100 lines
- If you are over 100 lines, move the detail into git commits or `docs/`

### Routing rules

- "Fixed X, working now" -> daily log with a commit hash
- Step-by-step debugging -> git history
- How a system works -> `docs/`
- Error messages and stack traces -> do not keep them as durable notes unless they serve a later doc

### Example

```markdown
### openclaw-voice
- Two-way voice working: Piper TTS + Whisper STT, Safari frontend (`a2b1f09`..`b8d9e12`)
- Key fixes: AudioContext user gesture init, 48→16kHz resampling for Whisper
- Pending: LaunchAgent for auto-start, VAD chunk size fix
```

## Context Hygiene

Your context window is finite. Treat it like RAM.

- After any large tool result, extract what you need and write it to a file immediately
- Batch external calls and write between batches
- Reference saved file paths instead of repeating large payloads in chat
- Checkpoint before long or fragile operations so you can resume cleanly

Warning signs:

- You have done several large fetches without writing anything to disk
- You are holding multiple big tool results while still deciding what to do
- The session is already long and you keep adding large outputs

## .gitignore Baseline

Every workspace should ignore the usual runtime noise:

```text
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

If a log file or runtime artifact is already tracked:

```bash
git rm --cached path/to/file.log
echo "path/to/file.log" >> .gitignore
git commit -m "chore: remove tracked log file, update .gitignore"
```
