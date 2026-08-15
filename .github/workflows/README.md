# GitHub Actions workflows

CI/CD for GrokBuild on `macos-latest`. This personal line installs with `make ship` under Apple Development. Do not dispatch the Release workflow for a notarized GitHub title. See [BUILDING.md](../../BUILDING.md).

| Workflow | File | When it runs |
|----------|------|--------------|
| **PR Checks** | [`pr.yml`](pr.yml) | Pull requests to `main`; manual dispatch |
| **Release** | [`release.yml`](release.yml) | Manual dispatch only (tag push trigger is disabled) |

---

## PR Checks (`pr.yml`)

Validates that the project builds and tests pass on macOS before merge.

### Triggers

- **`pull_request`** → branch `main`
- **`workflow_dispatch`** — run manually from **Actions → PR Checks → Run workflow**

The workflow token is explicitly read-only (`contents: read`).

### Concurrency

One run per ref (`pr-checks-${{ github.ref }}`). A newer push cancels an in-progress run for the same PR.

### Job: `test-and-build`

| Step | What it does |
|------|----------------|
| Checkout | `actions/checkout@v4` |
| Show Swift version | `swift --version` |
| Run tests | `make test` |
| Setup Node.js 22 | For bundling Computer Use |
| Install agent-desktop | `npm install -g agent-desktop` |
| Build unsigned app | `make app` |
| Verify bundle | Asserts `dist/GrokBuild.app` exists and `Contents/MacOS/agent-desktop` is executable |

### What it does **not** do

- No codesigning or notarization
- No DMG packaging
- No GitHub release publish

### Local equivalent

```bash
make test
npm install -g agent-desktop   # if testing full bundle like CI
make app
```

### Merge-gate contract

The `Test and Build App` job from the GitHub Actions app is a required check on
the personal fork's `main`
branch. GitHub must run it against the exact pull-request head SHA, and the pull
request must remain blocked while that check is pending or failing. A successful
run permits the merge; it does not replace merged-main packaging, signing, or
installed-app acceptance when a product slice requires those gates.

`release.yml` remains manual and is not part of this required pull-request check.

### Activation receipt — 2026-08-14 UTC

- Repository Actions: enabled, all actions allowed; `PR Checks` active.
- Automatic events resumed after an explicit repository-level Actions disable/enable
  transition; the earlier enabled/active API state had produced zero runs.
- Required branch check: `Test and Build App`, GitHub Actions app ID `15368`, strict
  and enforced for administrators on the personal fork's `main`.
- PR #68 head `031747d3c3ee0115128dc93f75ea5bff71439cd9` passed `make test`
  (802/802), `make app`, and bundled `agent-desktop version` in
  [run 31770647721](https://github.com/schmitzjimmy1-star/grok-build-desktop/actions/runs/31770647721).

---

## Release (`release.yml`)

Builds distributable assets and publishes a **GitHub Release** for tag `v{VERSION}`.

### Triggers

**Manual dispatch only** — **Actions → Release → Run workflow**.

Tag push auto-release is commented out in the workflow file:

```yaml
# push:
#   tags:
#     - 'v*'
```

### Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `release_type` | `notarized` | `notarized` or `unsigned` |
| `version` | *(empty)* | Optional tag override; must match `VERSION` (e.g. `v0.1.11`). Empty uses `v$(cat VERSION)`. |

### Preconditions

1. **`VERSION`** matches the release you intend to ship.
2. Changes are committed and pushed to the branch you release from.

The workflow **fails** if the release tag does not match `VERSION`.

### Job: `build`

Runs on `macos-latest` with `contents: write` (to create the release).

```mermaid
flowchart LR
  A[workflow_dispatch] --> B{release_type}
  B -->|unsigned| C[make app + dmg-package]
  B -->|notarized| D[Import cert + make signed]
  D --> E[notarize.sh + dmg-package]
  C --> F[Zip .app + publish Release]
  E --> F
```

#### Shared steps

- Validate tag against `VERSION`
- Install Node.js 22 and `agent-desktop` (bundled into the app)
- Create versioned assets:
  - `dist/GrokBuild-{tag}.app.zip`
  - `dist/GrokBuild-{tag}-macOS.dmg`
- Publish via `softprops/action-gh-release@v2` with generated changelog + custom body

#### Unsigned path (`release_type: unsigned`)

```bash
make app
make dmg-package
```

No Apple signing secrets required. Release title: **`v{VERSION} (Unsigned)`**. Notes include Gatekeeper bypass instructions.

#### Notarized path (`release_type: notarized`, default)

1. Import Developer ID certificate from secrets (`apple-actions/import-codesign-certs@v3`)
2. `make signed SIGN_IDENTITY=...`
3. `./scripts/notarize.sh dist/GrokBuild.app` (Apple API key from secrets)
4. `make dmg-package`

Release title: **`v{VERSION} (Notarized)`**. **Required for in-app GrokBuild updates** — the updater only offers notarized releases.

### Required secrets (notarized only)

| Secret | Purpose |
|--------|---------|
| `MACOS_CERTIFICATE` | Base64-encoded `.p12` Developer ID certificate |
| `MACOS_CERTIFICATE_PWD` | Password for the `.p12` |
| `SIGN_IDENTITY` | Codesign identity (optional; defaults to `Developer ID Application`) |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_BASE64` | Base64-encoded `.p8` API key |

`GITHUB_TOKEN` is provided automatically for release creation.

**Note:** CI uses Apple API keys for notarization. Local builds can use a keychain profile (`NOTARY_PROFILE`) via `make notarize`; see [`scripts/notarize.sh`](../../scripts/notarize.sh).

### Release outputs

| Asset | In-app updater |
|-------|----------------|
| `GrokBuild-{tag}.app.zip` | Yes — downloaded by **Update App** when release is notarized |
| `GrokBuild-{tag}-macOS.dmg` | Manual install only |

### Local equivalent

This personal line does not use the Release workflow. Install with:

```bash
make ship
```

`make release RELEASE_TYPE=notarized` is refused.

---

## Choosing a workflow

| Goal | Use |
|------|-----|
| Verify a PR before merge | **PR Checks** (automatic on PRs to `main`) |
| Install on this Mac | `make ship` |
| Quick local validation | `make test && make app` |
