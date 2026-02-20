# Changelog

All notable changes to ClawBack are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-20

### Added

- `VERSION` + `CHANGELOG.md` as the first explicit, versioned release baseline
- `scripts/worktree.sh` for deterministic worktree management (`create`, `list`, `path`, `remove`, `cleanup`)
- `scripts/release-check.sh` release gate for version/changelog enforcement
- `references/versioning.md` with semver and publish checklist guidance

### Changed

- `SKILL.md` now includes Mode 4 (worktree isolation) and Mode 5 (release hygiene)
- `README.md` updated with new version-control workflow and release gating steps

### Notes

- This repo previously shipped changes without an explicit version file; `1.0.0` establishes the baseline for future releases.
