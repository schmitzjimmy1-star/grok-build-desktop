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
turn, and a deliberate **Stop turn**). Captured `LEFT/RIGHT child echo` rows are
the settled presentation of successful `spawn_subagent` receipts; fixture
coverage keeps those rows classified as child spawns rather than generic tools.
Slice 5's three-route 1.5m ceiling
manifest remains the default.

The Official Runtime Alignment v2 manifest is deliberately **paid-locked**.
It plans 3M tokens plus a 1M reserve, but official usage arrives after model work,
so the reactive app Stop guard cannot prove the absolute 4M ceiling. V2 billable
preflight refuses before launch until a hard official or worst-case bound exists.
Legacy v1 billable execution is retired. V2 receipts are owner-only append-only
triples: reservation, typed terminal evidence, then exact local cleanup.
Schema-4 `_billable_4c` plus `manifests/official-provider-slice4c-paid.json`
plan the 20M/19M/1M native → direct → brokered matrix as dry-run only.
`--billable` still refuses at the absolute ceiling. Do not treat that executor
as paid unlock.

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
| [`acceptance/harness/provenance_v3.py`](acceptance/harness/provenance_v3.py) | Independent 4B.3 canonical provenance verifier, including nested `v3Authority` projection checks. Historical v2 schemas stay in `authority_v2.py`. |
| [`acceptance/harness/candidate_install.py`](acceptance/harness/candidate_install.py) | Slice 4B.6 signed pager install/rollback. Byte-copies into an owner-private digest directory; never writes `~/.grok/bin/grok`. Rollback removes only `runtime-selection.json` after two empty process-zero samples. |

## Packaging scripts

| Script | Purpose |
|--------|---------|
| [`build-dev-app.sh`](build-dev-app.sh) | Assemble a lightweight **dev** app bundle at `.build/GrokBuild.app` from an existing SPM binary. Bundles skills, brand assets, browser MCP, install helper, and `agent-desktop`. Uses `com.grokbuild.app` so Accessibility settings match packaged builds. |
| [`build-macos-app.sh`](build-macos-app.sh) | Build a **distributable** app under `dist/GrokBuild.app` (runs `swift build -c release`), bundle resources, optional DMG, optional codesign. Primary path for `make app` / `make dmg`. |
| [`build-identity.sh`](build-identity.sh) | Shared personal-build provenance: canonical repository, branch, exact commit, channel, dirty state, and plist-safe values for both bundle builders. |
| [`package-app-icon.sh`](package-app-icon.sh) | Shared dev/release AppIcon packager. Renders the vector master, creates every ICNS slot, verifies all ten representations, and fails closed on conversion errors. |
| [`render-app-icon.swift`](render-app-icon.swift) | Deterministically rasterize `AppIcon.svg` to the committed 1024×1024 PNG fallback used by the packager. |

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

Output: `dist/GrokBuild.app` and `dist/GrokBuild-macOS.dmg` (release.sh copies the DMG to a versioned `GrokBuild-{tag}-macOS.dmg` name at publish time). Both bundle paths package `AppIcon.svg` through the shared icon script and copy the separate menu-bar mark from `GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset/`.

Both bundle paths stamp the source receipt into `Contents/Info.plist`; inspect
the `GrokBuildSource*` and `GrokBuildBuildChannel` keys when proving an installed
artifact. The default repository is Jimmy's personal fork and may be overridden
only deliberately through the matching `GROKBUILD_SOURCE_*` environment values.

---

## Signing (Apple Development on this Mac)

| Script | Purpose |
|--------|---------|
| [`codesign-app-bundle.sh`](codesign-app-bundle.sh) | Sign `GrokBuild.app` and nested binaries (`GrokBuild`, `GrokBuildComputerUseMCP`, `agent-desktop`) with a shared bundle ID for Accessibility. Ad-hoc (`-`) when no identity is passed. |
| [`notarize.sh`](notarize.sh) | Unused on this personal line. `make notarize` is refused. |

**`codesign-app-bundle.sh`**

```bash
./scripts/codesign-app-bundle.sh /path/to/GrokBuild.app              # ad-hoc
./scripts/codesign-app-bundle.sh /path/to/GrokBuild.app "Developer ID Application: ..."
```

**`notarize.sh`**

Do not run this on the personal line. `make notarize` exits with an error and tells you to use `make ship`.

---

## Release

| Script | Purpose |
|--------|---------|
| [`release.sh`](release.sh) | Unsigned personal GitHub release only if explicitly asked. Refuses `RELEASE_TYPE=notarized`. |
| [`load-dotenv.sh`](load-dotenv.sh) | Shell helper sourced by `release.sh`: load `.env` without overriding variables already set by `make` or CI. Not invoked directly. |

**`release.sh`**

```bash
make ship
```

`make release RELEASE_TYPE=notarized` is refused. The install path is `make ship` under Apple Development. See [BUILDING.md](../BUILDING.md).

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
| [`bundle-agent-desktop.sh`](bundle-agent-desktop.sh) | Locate `agent-desktop` (`AGENT_DESKTOP_PATH`, then `~/.grokbuild/computer-use/agent-desktop`, Homebrew/local bins, `$PATH`) and copy it into `Contents/MacOS/` for Computer Use. Called by both build scripts. |
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
| `make app`, `make dmg`, `make signed`, `make install`, `make ship` | `build-macos-app.sh`, `codesign-app-bundle.sh` |
| `make notarize` | Refused. Use `make ship`. |
| `make release` | Refuses `RELEASE_TYPE=notarized`. Not the install path. |

```bash
make help
```
