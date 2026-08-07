---
name: grokbuild-release
description: Versions, packages, signs, notarizes, and publishes GrokBuild GitHub releases. Use when bumping VERSION, running make release, editing release.yml, or helping with codesigning/notarization.
---

# GrokBuild release

## Version files

- `VERSION` — semver shown in About and used for release tags (e.g. `0.1.3`)
- Tag format: `v{VERSION}` (e.g. `v0.1.3`)

## Local release

```bash
cp .env.example .env   # optional: SIGN_IDENTITY, NOTARY_PROFILE
make release           # unsigned, publishes via gh
make release RELEASE_TYPE=notarized
```

Script: `scripts/release.sh`. Requires `gh auth login`.

## CI release

- **Manual workflow dispatch** only — Actions → Release → Run workflow (see `BUILDING.md`)
- Choose `notarized` (default) or `unsigned`
- Tag push auto-release is disabled in `release.yml`

## Checklist

1. Verify the canonical publication target before making release artifacts: `personal` must resolve to `schmitzjimmy1-star/grok-build-desktop`; `origin` is the preserved third-party upstream and is never the publication target.
2. Run `gh auth status` and `gh repo view schmitzjimmy1-star/grok-build-desktop --json isArchived,viewerPermission,defaultBranchRef`. If an explicitly authorized publication finds the repository archived, unarchive it with `gh repo unarchive schmitzjimmy1-star/grok-build-desktop --yes` and verify `isArchived:false` before committing or pushing.
3. Bump `VERSION`
4. **`make test`** — must pass; add tests if release/updater logic changed
5. `make app` or `make dmg` to verify packaging
6. Inspect `GrokBuildSource*` and `GrokBuildBuildChannel` in the packaged `Info.plist`; About and Settings → App must show the same clean branch/commit receipt
7. **Update docs** — `BUILDING.md`, `README.md` (install/updates), `ARCHITECTURE.md` (in-app updates section), `scripts/README.md` if scripts changed
8. Commit on a feature branch only when authorized. Prefer the GitHub connector for PR creation, but if it returns HTTP 422 or "must be a collaborator" after `gh` proves write access and the branch push succeeds, immediately use authenticated `gh pr create`; do not call the repository blocked.
9. When merge is explicitly authorized, match the expected head SHA, merge, fetch `personal`, fast-forward local `main`, run `make ship`, and prove the installed commit stamp equals merged `HEAD`.
10. Do not force-push `main` or skip git hooks unless asked

## Update checking in app

`UpdateChecker` compares installed `AppVersion.short` to the newest **notarized** GitHub release (title contains `(Notarized)` or notes mention notarization); unsigned releases are ignored. CLI via `grok update --check --json`.

When changing release naming, assets, or updater behavior, update `ARCHITECTURE.md`, `BUILDING.md`, and `UpdateCheckerTests.swift`.
