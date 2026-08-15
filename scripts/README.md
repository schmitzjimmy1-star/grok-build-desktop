# Scripts

Command-line helpers for building, signing, releasing, and bundling GrokBuild. Prefer **`make`** targets when available — see [BUILDING.md](../BUILDING.md) for the full workflow.

## Local development & packaging

`performance-ledger.sh` starts the signed installed app with an opt-in, redacted
JSONL stage ledger and reports stage-to-stage timings. Cold samples refuse to start
unless GrokBuild is process-zero. Rows contain only stage, time, and PID; prompt
bodies, tool arguments, credentials, URLs, and environment contents are excluded.

```bash
scripts/performance-ledger.sh start cold /tmp/grokbuild-s7-cold-1.jsonl
scripts/performance-ledger.sh report /tmp/grokbuild-s7-cold-1.jsonl
```

## Agentic acceptance harness

`scripts/acceptance/run.py` is the agentic acceptance harness. Dry-run is the
default and prints the frozen plan without credentials or response bodies.
Fixture mode (`--fixture`) evaluates synthetic receipts at zero provider
cost. Fresh provider Sends require explicit `--billable` plus a UTC `--run-id`
after installed stamp/signing/hash, CLI version, model availability, process-zero,
marker uniqueness, and a clean test ledger. Cleanup accepts only exact IDs from
`--ids-from-ledger` and refuses guessed identities. The harness never bypasses
`/Applications/GrokBuild.app` or fakes ACP authority. Live driving opens that
installed bundle only and refuses `.build` or `dist` copies if they are running.
After quit/relaunch, continuation packets click **Resume current task** (ACP
`session/load`, no prompt) then Send, which may be labeled **Send and resume
session** while continuity is verifying. Slice 6 uses
`manifests/installed-slice6-packet-v1.json` (250k actual-token ceiling, one
grok-4.6 packet with three ordered tools, two read-only children, one follow-up
turn, and a deliberate **Stop turn**). Slice 5's three-route 1.5m ceiling
manifest remains the default.

```bash
python3 scripts/acceptance/run.py
python3 scripts/acceptance/run.py --fixture scripts/acceptance/fixtures/happy-path
python3 scripts/acceptance/run.py --billable --run-id 20260814T180000Z \
  --ledger /tmp/grokbuild-s5-ledger.jsonl
python3 scripts/acceptance/run.py --manifest scripts/acceptance/manifests/installed-slice6-packet-v1.json \
  --billable --run-id 20260815T020000Z --ledger /tmp/grokbuild-s6-ledger.jsonl
python3 scripts/acceptance/run.py --cleanup --ids-from-ledger /tmp/grokbuild-s6-ledger.jsonl
```

Focused tests: `swift test --filter AcceptanceHarnessTests`.

| Script | Purpose |
|--------|---------|
| [`acceptance/run.py`](acceptance/run.py) | Versioned agentic acceptance harness. Dry-run default; `--fixture` for zero-cost rejection; `--billable` for installed-UI Sends after preflight. |

## Packaging scripts

| Script | Purpose |
|--------|---------|
| [`build-dev-app.sh`](build-dev-app.sh) | Assemble a lightweight **dev** app bundle at `.build/GrokBuild.app` from an existing SPM binary. Bundles skills, brand assets, browser MCP, install helper, and `agent-desktop`. Uses `com.grokbuild.app` so Accessibility settings match packaged builds. |
| [`build-macos-app.sh`](build-macos-app.sh) | Build a **distributable** app under `dist/GrokBuild.app` (runs `swift build -c release`), bundle resources, optional DMG, optional codesign. Primary path for `make app` / `make dmg`. |
| [`build-identity.sh`](build-identity.sh) | Shared personal-build provenance: canonical repository, branch, exact commit, channel, dirty state, and plist-safe values for both bundle builders. |

**`build-dev-app.sh`**

```bash
make build          # or make build-debug
BUILD_CONFIG=debug ./scripts/build-dev-app.sh   # default: release
```

**`build-macos-app.sh`**

```bash
./scripts/build-macos-app.sh
./scripts/build-macos-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
make app
make dmg
```

Output: `dist/GrokBuild.app` and `dist/GrokBuild-macOS.dmg` (release.sh copies the DMG to a versioned `GrokBuild-{tag}-macOS.dmg` name at publish time). Copies the Grok mark from `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/` (or legacy project-root PNGs).

Both bundle paths stamp the source receipt into `Contents/Info.plist`; inspect
the `GrokBuildSource*` and `GrokBuildBuildChannel` keys when proving an installed
artifact. The default repository is Jimmy's personal fork and may be overridden
only deliberately through the matching `GROKBUILD_SOURCE_*` environment values.

---

## Signing & notarization

| Script | Purpose |
|--------|---------|
| [`codesign-app-bundle.sh`](codesign-app-bundle.sh) | Sign `GrokBuild.app` and nested binaries (`GrokBuild`, `GrokBuildComputerUseMCP`, `agent-desktop`) with a shared bundle ID for Accessibility. Ad-hoc (`-`) when no identity is passed. |
| [`notarize.sh`](notarize.sh) | Submit `.app`, `.dmg`, or `.zip` to Apple notary service, wait, staple, clean up temp zip. Used by `make notarize` and notarized release flows. |

**`codesign-app-bundle.sh`**

```bash
./scripts/codesign-app-bundle.sh /path/to/GrokBuild.app              # ad-hoc
./scripts/codesign-app-bundle.sh /path/to/GrokBuild.app "Developer ID Application: ..."
```

**`notarize.sh`**

```bash
NOTARY_PROFILE=AC_PASSWORD ./scripts/notarize.sh
NOTARY_PROFILE=AC_PASSWORD ./scripts/notarize.sh dist/GrokBuild.app

# CI / API key
APPLE_API_KEY_PATH=... APPLE_API_KEY_ID=... APPLE_API_ISSUER_ID=... \
  ./scripts/notarize.sh dist/GrokBuild.app
```

---

## Release

| Script | Purpose |
|--------|---------|
| [`release.sh`](release.sh) | Build, tag, and publish a GitHub release via `gh` (mirrors CI). Supports unsigned and notarized release types. |
| [`load-dotenv.sh`](load-dotenv.sh) | Shell helper sourced by `release.sh`: load `.env` without overriding variables already set by `make` or CI. Not invoked directly. |

**`release.sh`**

```bash
make release
make release RELEASE_TYPE=notarized SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=AC_PASSWORD
```

Requires `gh` (`brew install gh && gh auth login`). Release tag must match `VERSION`. See [BUILDING.md](../BUILDING.md#github-releases).

---

## In-app updates

| Script | Purpose |
|--------|---------|
| [`grokbuild-install-update.sh`](grokbuild-install-update.sh) | **Install helper** bundled as `Contents/Resources/grokbuild-install-update`. Waits for the running app PID, replaces the target bundle with `ditto`, clears quarantine, relaunches. Used by **Install and Restart** in the updater. |

**Normal install** (real update — replaces the running app in place):

```bash
grokbuild-install-update --target /Applications/GrokBuild.app \
  --new-app /path/to/extracted/GrokBuild.app --pid 12345
```

**Debug simulation** (`--relaunch-only` — restart without replacing the binary):

```bash
grokbuild-install-update --relaunch-only --target /path/to/GrokBuild.app --pid 12345
```

The app passes `--target` as `Bundle.main.bundleURL` (wherever GrokBuild is running from).

---

## Bundled runtime tools

These are copied into the app bundle during packaging; they are not usually run from the command line during development.

| Script | Purpose |
|--------|---------|
| [`bundle-agent-desktop.sh`](bundle-agent-desktop.sh) | Locate `agent-desktop` on the system (or `AGENT_DESKTOP_PATH`) and copy it into `Contents/MacOS/` for Computer Use. Called by both build scripts. |
| [`grokbuild-browser-mcp`](grokbuild-browser-mcp) | Python MCP stdio server exposing browser tools via `agent-browser`. Copied to `Contents/Resources/grokbuild-browser-mcp`. |

**`bundle-agent-desktop.sh`**

```bash
./scripts/bundle-agent-desktop.sh /path/to/GrokBuild.app/Contents/MacOS
AGENT_DESKTOP_PATH=/custom/path/agent-desktop ./scripts/bundle-agent-desktop.sh ...
```

---

## Makefile entry points

| Make target | Scripts involved |
|-------------|------------------|
| `make build`, `make build-debug` | *(SwiftPM only)* |
| `make run`, `make run-debug`, `make run-app` | `build-dev-app.sh` |
| `make app`, `make dmg`, `make signed`, `make install` | `build-macos-app.sh`, `codesign-app-bundle.sh`, optionally `notarize.sh` |
| `make notarize` | `notarize.sh` |
| `make release` | `release.sh` (+ build/sign/notarize chain) |

```bash
make help
```
