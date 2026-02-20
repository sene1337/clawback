# Versioning & Changelog Rules

ClawBack adopts the same release hygiene used in the Compound Engineering plugin: versioning is mandatory, changelog is mandatory, and releases are never "silent."

## Required for Every Published Change

If any skill behavior changes (`SKILL.md`, `scripts/`, `references/`, `README.md`), you must update all of:

1. `VERSION` (semantic versioning)
2. `CHANGELOG.md` (Keep a Changelog style)
3. Published docs affected by the behavior change (usually `README.md` and/or `SKILL.md`)

Do not publish partial updates.

## SemVer Policy

- `MAJOR` (`X.0.0`): breaking behavior or incompatible workflow changes
- `MINOR` (`X.Y.0`): new mode, command, script, or non-breaking capability
- `PATCH` (`X.Y.Z`): bug fixes, docs clarifications, compatibility fixes

## Changelog Format

Use:

```markdown
## [X.Y.Z] - YYYY-MM-DD
### Added
- ...
### Changed
- ...
### Fixed
- ...
```

Use only relevant sections (`Added`, `Changed`, `Fixed`, `Removed`, `Security`).

## Pre-Publish Gate

Run:

```bash
bash scripts/release-check.sh [base-ref]
```

Default `base-ref` is `origin/main` with local fallbacks (`main`, `HEAD~1`).

The script fails when:

- `VERSION` is missing or not semver
- `CHANGELOG.md` has no section for current `VERSION`
- Skill files changed without `VERSION` and `CHANGELOG.md` updates
- `VERSION` does not increase relative to `base-ref`

## Suggested Publish Checklist

- [ ] `bash scripts/release-check.sh`
- [ ] `git diff --cached --stat` reviewed
- [ ] `SKILL.md` examples still match scripts
- [ ] `README.md` usage examples still match scripts
- [ ] Commit message follows Conventional Commits
