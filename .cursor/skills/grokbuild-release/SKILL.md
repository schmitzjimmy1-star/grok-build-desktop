---
name: grokbuild-release
description: Versions and installs GrokBuild on this Mac via make ship. Use when bumping VERSION, running make ship, or editing local signing docs. Do not notarize or publish GitHub (Notarized) releases on this personal line.
---

# GrokBuild local install

This personal line is Mac-only. The install identity is **Apple Development** on Jimmy's Team `DD2GCQJVB4`. Do not chase Developer ID, notary profiles, or GitHub titles that say `(Notarized)`.

## Version files

- `VERSION` — semver shown in About (e.g. `0.1.22`)
- Installed proof is `/Applications/GrokBuild.app` after `make ship`, not a GitHub tag

## Install

```bash
make ship
make open
```

`make ship` tests, signs with the local Apple Development identity, installs to `/Applications/GrokBuild.app`, and checks stamp == HEAD, team `DD2GCQJVB4`, deep/strict signing, and no quarantine.

`make notarize` and `make release RELEASE_TYPE=notarized` are refused.

## Checklist

1. Canonical worktree only. `personal` is `schmitzjimmy1-star/grok-build-desktop`. `origin` (`rimusz/grok-build-desktop`) is read-only. Never push tags to `origin`.
2. Bump `VERSION` only when the marketing version should change.
3. **`make test`** — must pass; add tests if install/updater logic changed
4. **`make ship`** — installed About / Settings → App must show Apple Development, personal repo, branch, commit, and dirty state
5. **Update docs** — `BUILDING.md`, `README.md`, `ARCHITECTURE.md`, `scripts/README.md` if install scripts changed
6. Commit on a feature branch only when authorized
7. Do not force-push `main`, write `origin`, or publish a `(Notarized)` GitHub release

## Update checking in app

The in-app GrokBuild app-release feed stays off on this line. `UpdateChecker` can still parse notarized GitHub titles if someone turns that feed on later; that is not an install path. CLI updates remain `grok update --check --json`.
