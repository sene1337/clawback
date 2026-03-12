# Option C Ops-State Model

ClawBack's Option C flow uses two local surfaces:

1. `workspace/` git repo for source, docs, scripts, and durable project artifacts
2. `ops-state/` local-only git repo for runtime-state manifests, checkpoint indexes, and restore notes

## What belongs in `ops-state`

- checkpoint manifests
- checkpoint index files
- restore event notes
- hook/policy docs

## What stays out of git

- raw runtime snapshots
- sqlite/db payloads
- raw session exports
- logs, caches, temp output
- secrets, keys, tokens, `.env` material

Raw snapshots are stored under `ops-state/snapshots/`, but that directory is gitignored and blocked by the pre-commit guard.

## Scripts

Bootstrap the local repo:

```bash
bash scripts/init-ops-state.sh
```

Create a runtime-state checkpoint:

```bash
bash scripts/state-checkpoint.sh --name "before queue migration"
```

Dry-run a restore:

```bash
bash scripts/state-restore.sh <checkpoint-id> --dry-run
```

Install or re-install guardrails:

```bash
bash scripts/pre-commit-guard.sh --install ~/.openclaw/ops-state
```

## Restore semantics

- `state-restore.sh` verifies the recorded checksum before acting
- restore is dry-run by default
- real restore requires `--yes-restore`
- restore is an overlay copy, not a destructive prune
- workspace paths and ops-state internals are refused

## Guardrails

The pre-commit guard blocks:

- git remotes on `ops-state` (must stay local-only)
- raw snapshots, DBs, session exports, logs, `.env` files, keys, and archives
- obvious secret-like staged content

This keeps Option C aligned with the workspace rule: manifests in git, runtime payloads local-only.
