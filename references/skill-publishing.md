# Skill Publishing SOP

Standard workflow for publishing skill updates to GitHub. Follow this every time — no exceptions, no shortcuts.

## Rule Zero: Know Where You Are

Before ANY `git push`:

    pwd
    git remote -v

- If `git remote -v` returns **nothing** → you're in the workspace. STOP. Do not add a remote. Do not push. The workspace is local-only. This is a non-negotiable security boundary.
- If `git remote -v` returns a GitHub URL → you're in a standalone skill repo. Safe to push.

## Skill Repo Standard

Every skill in `workspace/skills/<name>/` **must** have its own git repo with a remote (GitHub, Gitea, self-hosted — whatever fits your security model). No exceptions.

### Checking compliance

```bash
for d in workspace/skills/*/; do
  name=$(basename "$d")
  if [ -d "$d/.git" ]; then
    remote=$(cd "$d" && git remote get-url origin 2>/dev/null || echo 'no remote set')
    echo "✅ $name → $remote"
  else
    echo "❌ $name — no .git"
  fi
done
```

If any skill shows ❌, initialize it before doing anything else:

```bash
cd workspace/skills/<name>
git init
git remote add origin <your-remote-url>
git add -A
git commit -m "init: sync local repo with workspace skill"
```

If you need to create the remote repo first, use your platform's CLI (e.g. `gh repo create <name> --public` for GitHub).

### Remote URL hygiene

**Never embed tokens in remote URLs.** Use `https://github.com/...` (no credentials). Authentication goes through `gh auth` or SSH keys — not inline tokens.

If you find a token in a remote URL: `git remote set-url origin https://github.com/<org>/<repo>.git`

## The Workflow

### 1. Develop Locally (in workspace)

All skill development happens in `workspace/skills/<name>/`. Edit, test, iterate here. Commit to the workspace repo as you go (ClawBack Mode 1). These commits stay local.

### 2. Verify the Change

Before publishing:
- Re-read the SKILL.md — does it make sense standalone?
- If the skill has scripts, test them
- Make sure all file paths are relative (not absolute workspace paths)
- Remove any agent-specific references (your name, your org, your config)

### 3. Sync to Standalone Repo

Each publishable skill has its own repo. Copy the changed files:

    rsync -a --exclude='.git' workspace/skills/<name>/ ~/<standalone-repo-dir>/
    cd ~/<standalone-repo-dir>/

**Never copy these into a skill dir:** MEMORY.md, USER.md, SOUL.md, daily logs, inbox files, or anything from `memory/`, `docs/`, or `data/`. If it's not part of the skill, it doesn't leave the workspace.

After copying, review what landed:

    git status

If anything unexpected showed up, remove it before proceeding.

### 4. Verify You're in the Right Repo

This step is mandatory. Do not skip it.

    pwd               # should NOT be workspace/
    git remote -v     # should show a GitHub URL

If either check fails, STOP.

### 5. Review, Commit & Push

    git add -A
    git diff --cached --stat    # review what's about to be committed
    git commit -m "type: what changed — why"
    git push origin main

If `git diff --stat` shows files you don't recognize or didn't intend to publish, unstage them before committing. Also verify the standalone repo has a `.gitignore` — if it doesn't, create one before your first push.

### 6. Artifact Hygiene Check (Required)

Before release/upload, inspect the packaged `.skill` archive and confirm it contains no VCS internals.

```bash
unzip -l tmp/<skill-name>.skill | grep -E '\.git/' && echo 'FAIL: .git leaked' || echo 'OK: clean'
```

If `.git/` appears, fail the release and rebuild from a clean staging directory (e.g., `rsync --exclude='.git'`).

### 7. Log It

Add a one-liner to the daily log:

    - Published <skill-name> update: <what changed> (<commit-hash>)

## Safety Rails (Non-Negotiable)

1. **Never run `git push` from the workspace root.** The workspace has no remote. This is intentional. It contains MEMORY.md, USER.md, daily logs, credential paths — none of which should ever be public.
2. **Never run `git remote add` in the workspace.** If you find yourself wanting to, stop and re-read this SOP.
3. **Always verify `pwd` and `git remote -v` before pushing.** 2 seconds prevents catastrophic leaks.
4. **If you're unsure which repo you're in, stop and check.** Uncertainty is the danger zone.

## Rollback Protocol

If sensitive data was pushed to GitHub:

1. **Immediately revert:** `git revert HEAD && git push origin main`
2. **If the commit contained credentials or private data:** Force-push to remove history: `git reset --hard HEAD~1 && git push --force origin main`
3. **Rotate any exposed credentials.** Assume they're compromised the moment they hit a public repo — even if reverted within seconds.
4. **Log the incident** in the daily log and `docs/security/hack-audit-log.md`.

Speed matters. GitHub caches and scrapers index fast.

## Why This Exists

AI agents with high autonomy and git push access can accidentally publish private data if they forget which repo they're operating in. Compaction erases the context where "workspace is local-only" was decided. This SOP replaces memory with process — you don't need to remember the decision, you just follow the checklist.
