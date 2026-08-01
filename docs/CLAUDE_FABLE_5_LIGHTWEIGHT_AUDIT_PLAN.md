# Claude Fable 5 — GrokBuild Lightweight Architecture and Bolt-On Audit

> **Execution packet for:** Claude Fable 5 (`claude-fable-5`)
>
> **Repository:** `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
>
> **Current branch:** `codex/warm-glass-ui`
>
> **Baseline commit:** `ac31979438bccc5d6f2c1b90d01eda047543b859`
>
> **Installed application:** `/Applications/GrokBuild.app`
>
> **Prepared:** July 31, 2026
>
> **Mode:** Evidence-first architecture audit, followed by small implementation slices only when authorized
>
> **Primary objective:** Keep GrokBuild a small, native macOS shell around Grok—not a second Grok runtime, generic agent platform, or bundled web stack.

---

## 0. Your Role and Operating Contract

You are Claude Fable 5 working on a long-horizon native macOS architecture audit. Treat this document as an execution contract, not a brainstorming prompt.

Your job is to:

1. reconstruct the actual product from source, tests, build scripts, the installed app, and the Grok CLI;
2. find functionality that is duplicated, carelessly bolted on, unreachable, over-broad, or owned by the wrong layer;
3. make lightweight product choices that fit the software already in use;
4. identify correctness, security, lifecycle, and interaction defects before aesthetic refactors;
5. preserve the product invariant that Grok owns the agent runtime and GrokBuild owns the native shell;
6. produce evidence-backed Keep, Fix, Spike, Defer, or Delete decisions for every material component; and
7. implement only the slices Jimmy explicitly authorizes.

Do not reward yourself for deleting lines, splitting a large file, or adopting a fashionable framework. A change is justified only if it produces a measurable improvement in ownership, correctness, security, startup/resource behavior, interaction reliability, or maintenance cost.

### Authority boundary

This packet authorizes a read-only audit and creation of audit documents inside the repository. It does **not** independently authorize:

- deleting caches or user data;
- changing live provider credentials, OAuth grants, Keychain entries, or account state;
- running billable provider prompts;
- replacing `/Applications/GrokBuild.app`;
- installing dependencies, plugins, launch agents, login items, or background services;
- modifying `~/.grok/config.toml`;
- committing, pushing, publishing, notarizing, or releasing; or
- rewriting unrelated dirty worktree changes.

If Jimmy separately says **execute this plan** or **full send**, repository-local implementation and proportionate local verification are authorized. Destructive cleanup, billable calls, account authorization, app installation, signing/notarization, publication, and release still require explicit scope or an already-clear instruction covering that action.

### Dirty-worktree rule

The current working tree contains intentional in-progress work. Before any edit:

```bash
cd '/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop'
git status --short
git branch --show-current
git rev-parse HEAD
```

Record the output in the audit evidence. Do not reset, stash, revert, reformat, or overwrite existing changes. Stage nothing unless publication is separately authorized. If a proposed edit overlaps an existing modification, read the diff and preserve both intents.

---

## 1. Mission Outcome

At completion, Jimmy should be able to answer five questions without hand-waving:

1. **What does GrokBuild own?** Every visible capability has one traceable UI → state/service → Grok or macOS owner → persistence → process impact → result path.
2. **What is unnecessarily heavy?** Bundle bytes, memory, processes, dependencies, resources, and background work are measured—not guessed.
3. **What is bolted on?** Duplicate state, compatibility shims, dead fallbacks, broad notifications, shell wrappers, hidden-pane work, and orphaned packaged resources are classified with evidence.
4. **Are providers trustworthy and understandable?** Authentication, endpoint policy, model availability, redirects, errors, and reload effects are explicit.
5. **What should happen next?** Findings are converted into ordered, reversible slices with acceptance tests and clear stop gates.

The desired product shape is:

```text
SwiftUI/AppKit shell
    ├── native interaction, settings, persistence metadata, Keychain access
    ├── narrow macOS helpers only where a system boundary requires them
    └── Grok CLI through ACP
            ├── model/provider execution
            ├── tools and skills
            ├── browser MCP ownership
            └── session runtime
```

It is **not**:

```text
SwiftUI shell + embedded second agent SDK + embedded browser runtime
+ provider proxy + generic OAuth platform + generic Mac cleaner
```

---

## 2. Current Verified Truth — Recheck, Do Not Blindly Inherit

These are receipts from the immediately preceding GrokBuild work. Reverify cheap or drift-prone facts before relying on them.

### Repository and test state

- Branch: `codex/warm-glass-ui`.
- Recorded HEAD: `ac31979438bccc5d6f2c1b90d01eda047543b859`.
- The worktree is intentionally dirty with architecture, provider, configuration, UI, test, and documentation changes.
- Latest completed test receipt: **307 tests, 0 failures** from `make test`.
- No commit, publication, or release has been authorized.

### Architecture and provider work already completed

- Grok configuration writes now go through one serialized `GrokConfigRepository`.
- Writes reread current TOML, preserve unrelated content, use atomic replacement, and enforce mode `0600`.
- Provider credentials moved from UserDefaults to macOS Keychain.
- UserDefaults retains provider metadata, not provider secrets.
- Grok CLI compatibility still requires a plaintext credential projection in each applicable TOML model table; the file permission boundary is therefore critical.
- Provider authentication and validation failures are typed rather than collapsed into one generic error.
- Model/provider configuration changes use targeted `ConfigurationChange` impact rather than an opaque restart-everything callback.
- Models settings state was extracted into a dedicated view model.
- Main navigation controls have larger native hit targets and explicit busy/disabled states.
- Settings navigation preserves the active session model.

### CLI configuration corrections already completed

- GrokBuild-only model metadata moved out of `~/.grok/config.toml` into a UserDefaults sidecar.
- `context_window` and `api_backend` use Grok-native TOML fields.
- The OpenAI preset defaults to the Responses backend.
- The configured `gpt-5.6-terra` model was migrated to `api_backend = "responses"`.
- Compatibility toggles map to the thirteen cells Grok actually understands.
- Legacy `disabled_mcp_servers` and `grokbuild_*` unknown fields were removed.
- `~/.grok/config.toml` was verified at mode `0600`.

### Backend smoke receipts

- OpenAI exact `OK`: exit 0; 11,539 input tokens; 5 output tokens; 0 reasoning tokens; no warning lines.
- Kimi/Moonshot exact `OK`: exit 0; 10,325 input tokens; 2,560 cached tokens; 39 output tokens; 23 reasoning tokens; no warning lines.
- Neither smoke returned a cost value.
- These are historical receipts. Do not repeat billable calls merely to regenerate them.

### Plugin cleanup and process state

- Postman and Bright Data were uninstalled from Grok.
- The Grok uninstaller left stale `[plugins].enabled` entries; those two exact entries were removed from `~/.grok/config.toml`.
- Last verification found zero matching config references, files, processes, or warning lines for Postman/Bright Data.
- Remaining plugin state at that receipt:
  - enabled: Chrome DevTools MCP, Base44, 42Crunch API Security;
  - disabled: Tinyfish, AWS Amplify;
  - Grok MCP list: Chrome DevTools only.
- GrokBuild and its helper were idle at 0% CPU.
- Port 9222 had no listener.
- The preceding 30-minute log window had no GrokBuild warning/error/connection-refused lines.

### Installed application and package baseline

- Installed version: `0.1.20` at `/Applications/GrokBuild.app`.
- Bundle identifier: `com.grokbuild.app`.
- Signing receipt: Apple Development, Team `DD2GCQJVB4`.
- Prior `codesign --verify --deep --strict` passed.
- Installed main binary matched the `dist` build at the last receipt.
- `Package.swift` uses Swift tools 5.9 and macOS 26.0.
- SwiftPM products:
  - `GrokBuild` executable;
  - `GrokBuildComputerUseMCP` executable.
- SwiftPM targets:
  - `GrokBuildComputerUseCore`;
  - main application executable;
  - Computer Use MCP helper executable;
  - test target.
- Swift package dependencies: **none**.
- Current bundle sizes, approximately:
  - `/Applications/GrokBuild.app`: 16 MB;
  - `.build/GrokBuild.app`: 15 MB;
  - `dist/GrokBuild.app`: 16 MB;
  - `dist/GrokBuild-macOS.dmg`: 4.9 MB.
- Largest installed payloads at the last receipt:
  - main native binary: 13,704,160 bytes;
  - bundled `agent-desktop`: 2,251,376 bytes;
  - `AppIcon.icns`: 305,895 bytes;
  - Computer Use MCP helper: 195,872 bytes;
  - browser MCP script: 5,547 bytes;
  - update installer: 1,775 bytes.
- The main binary linked Apple/system frameworks and Swift runtime libraries; no third-party dynamic libraries were bundled.

This is already a small native app. Do not create performative “lightweight” churn that makes the architecture worse to save trivial bytes.

---

## 3. Exact Source-of-Truth Reading Order

Read each file completely in this order before forming conclusions. Relative references below are anchored at:

`/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`

### Governing and architecture documents

1. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/AGENTS.md`
2. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/ARCHITECTURE.md`
3. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/docs/ARCHITECTURE_AUDIT.md`
4. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/docs/UI_ACCEPTANCE_MATRIX.md`
5. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/docs/OAUTH_OPENROUTER_ACP_PLAN.md`
6. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/README.md`
7. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/BUILDING.md`
8. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/scripts/README.md`
9. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/Package.swift`
10. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/Makefile`

If documents conflict, prefer executable source and tests, then update the documents as an explicit finding. Do not silently choose the prose that supports a preconceived design.

### Configuration, credentials, and provider path

- `GrokBuild/Services/GrokConfigRepository.swift`
- `GrokBuild/Services/GrokConfigLegacyMigration.swift`
- `GrokBuild/Services/ProviderCredentials.swift`
- `GrokBuild/Services/CustomModelSettings.swift`
- `GrokBuild/Services/CustomModelsSettingsViewModel.swift`
- `GrokBuild/Services/CustomModelMetadataStore.swift`
- `GrokBuild/Services/CompatConfigStore.swift`
- `GrokBuild/Services/WorkflowsConfigStore.swift`

### Runtime and lifecycle path

- `GrokBuild/Services/GrokProcess.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Services/AgentBrowserService.swift`
- `GrokBuild/Services/ComputerUseService.swift`
- `GrokBuildComputerUseCore/ComputerUseCore.swift`
- `GrokBuildComputerUseMCP/main.swift`
- `GrokBuild/AppDelegate.swift`

### Interaction and navigation path

- `GrokBuild/ContentView.swift`
- `GrokBuild/Views/ChatView.swift`
- `GrokBuild/Views/SettingsView.swift`
- `GrokBuild/AppTheme.swift`

### Packaging, signing, and update path

- `scripts/build-macos-app.sh`
- `scripts/build-dev-app.sh`
- `scripts/bundle-agent-desktop.sh`
- `scripts/codesign-app-bundle.sh`
- `scripts/grokbuild-install-update.sh`
- `scripts/notarize.sh`
- `scripts/release.sh`

### High-value regression tests

- `Tests/GrokBuildTests/ProviderReliabilityTests.swift`
- `Tests/GrokBuildTests/GrokConfigLegacyMigrationTests.swift`
- `Tests/GrokBuildTests/CustomModelTests.swift`
- `Tests/GrokBuildTests/CompatConfigTests.swift`
- `Tests/GrokBuildTests/BrowserIntegrationTests.swift`
- `Tests/GrokBuildTests/ComputerUseIntegrationTests.swift`
- `Tests/GrokBuildTests/MainWindowLayoutTests.swift`
- `Tests/GrokBuildTests/SettingsTabTests.swift`

Read the rest of `Tests/GrokBuildTests/` by capability during the ownership trace. Tests are evidence of intended behavior, not proof that production wiring reaches that behavior.

---

## 4. External Runtime Map and Secret Boundaries

Inspect these paths only as needed. Never print secret values into a terminal transcript, report, diff, test fixture, or log.

| Purpose | Exact path or identifier | Rule |
|---|---|---|
| Installed app | `/Applications/GrokBuild.app` | Read-only until install is explicitly authorized. |
| Grok CLI | `/Users/jimmyschmitz/.grok/bin/grok` | Verify version and behavior; do not replace it casually. |
| Grok config | `/Users/jimmyschmitz/.grok/config.toml` | Inspect structure with redaction. Never print `api_key` values. |
| Grok plugins | `/Users/jimmyschmitz/.grok/installed-plugins` | Inventory ownership and live registration separately. |
| Provider metadata | `/Users/jimmyschmitz/Library/Preferences/com.grokbuild.app.plist` | Do not dump wholesale. Confirm secrets are absent with redacted tooling. |
| Provider secrets | Keychain service `com.grokbuild.provider-credential` | Test presence/contract, never extract credential material. |
| App support | `/Users/jimmyschmitz/Library/Application Support/GrokBuild` | Classify durable user state versus rebuildable state. |
| App caches | `/Users/jimmyschmitz/Library/Caches/com.grokbuild.app` and discovered GrokBuild cache paths | Measure and classify before cleanup. |
| Saved state | `/Users/jimmyschmitz/Library/Saved Application State/com.grokbuild.app.savedState` | Treat as OS-managed, rebuildable state. |
| Logs | macOS unified log plus GrokBuild/Grok log paths discovered from source | Redact prompts, paths, tokens, and credentials. |
| Browser/Computer Use profile | `/Users/jimmyschmitz/.grokbuild/computer-use` | Do not delete without explicit approval; it may contain durable browser state. |
| Build products | `.build/` and `dist/` inside the repository | Rebuildable, but deletion is destructive and not audit-default behavior. |
| Release environment | project `.env`, if present | It is for signing/notarization variables—not provider keys. Never print it. |

Provider keys do **not** belong in a project `.env`. The current contract is Keychain for GrokBuild plus the minimum CLI-required TOML projection protected by `0600`.

---

## 5. Non-Negotiable Product Decisions

Use these as defaults unless the audit produces stronger contradictory evidence.

### Keep Grok as the agent harness

GrokBuild already speaks to Grok through ACP. Do not embed Cursor’s harness, the OpenAI Agents SDK, Claude Agent SDK, OpenHands, a Node orchestration runtime, or a homegrown generic agent loop into the main app. That would duplicate Grok’s ownership and make the app heavier and harder to reason about.

ACP is the agnostic seam worth preserving. A future backend can earn support by proving it can satisfy a narrow, versioned backend protocol without leaking provider-specific state across sessions.

### OpenRouter is an optional provider, not a new runtime

OpenRouter is the best next multi-model provider option because it expands catalog reach behind a single provider contract. It must remain:

- opt-in;
- visibly labeled “via OpenRouter”;
- never a silent fallback for a direct provider;
- implemented with native URL loading and system security primitives;
- isolated behind the existing provider capability model; and
- absent from the running process unless configured or being validated.

Do not add an OpenRouter Swift SDK merely for convenience. The package currently has `dependencies: []`; preserving that is a hard default.

### OAuth should be native, narrow, and provider-scoped

OAuth support should use S256 PKCE, system browser authorization, an ephemeral bounded loopback callback only if the provider requires it, Keychain storage, state verification, exact redirect matching, and explicit disconnect/revocation behavior.

Prefer Foundation, Security, CryptoKit, AuthenticationServices, Network, and AppKit APIs already available on macOS. Do not add a generic “Open Authenticator” platform, embedded web server framework, or arbitrary issuer engine until two real providers demonstrate the need.

### Dock persistence is an operating-system concern

Keeping GrokBuild’s icon in the Dock when the app is not running does not justify a daemon, menu-bar process, login item, or background helper. The correct solution is:

1. keep the signed app at the stable path `/Applications/GrokBuild.app`;
2. launch that installed copy;
3. use macOS **Options → Keep in Dock** once; and
4. ensure installs preserve bundle identity and stable path.

Audit whether updater/install behavior breaks the Dock tile identity. Add code only if an actual bundle replacement defect is proven.

### Cache cleanup is an operational audit, not a product feature

Do not bolt a generic Mac cleaner into GrokBuild. Produce a classified storage report. Only propose deletion of exact, rebuildable GrokBuild/GrokBuild-development artifacts, and keep durable sessions, browser profiles, credentials, plugins, and user-created data out of bulk cleanup.

---

## 6. Lightweight Baseline and Measurement Rules

“Light” means more than app bundle size. Measure all of the following before and after any accepted change:

| Dimension | Baseline evidence | Failure smell |
|---|---|---|
| Package graph | SwiftPM dependency graph and linked libraries | New third-party runtime for a capability system APIs already cover |
| Bundle bytes | Total and per-file size | Duplicate binaries, unused resources, unstripped debug payloads |
| Cold launch | Process start to responsive main window | Synchronous migrations, eager services, hidden network work |
| Idle CPU | App and helpers after settling | Timers, retry loops, WebKit/browser churn, hidden-pane work |
| Idle RSS | Main app plus helpers | Always-resident optional engines or caches |
| Process count | Main app, Grok, helper, browser child processes | Duplicate Grok/browser/helper instances |
| Network listeners | `lsof`/Network inspection | Unbounded OAuth callback or stale port 9222 listener |
| Disk growth | Cache/support/log deltas across one session | Unbounded logs, duplicated artifacts, retained temp directories |
| Interaction latency | First-click Settings/Session and provider actions | Main-thread I/O, broad reloads, invisible busy work |
| Restart impact | Per configuration change | Full-process restart for default-only or unrelated changes |

Do not use a large Swift source file as proof of runtime bloat. The largest current files include `SettingsView.swift`, `ChatView.swift`, `ChatStore.swift`, `CustomModelSettings.swift`, `ContentView.swift`, and `GrokProcess.swift`. Split only where ownership, hidden work, correctness, testability, or merge safety materially improves.

Likewise, `otool -L` proving that WebKit, Speech, AVFAudio, or another Apple framework is linked is only a lead. Map the framework to imported symbols and reachable product features before proposing removal.

### Safe measurement commands

Run from the repository root. Redirect or redact any output that could include secrets.

```bash
swift package show-dependencies
swift build -c release
make test

du -sh .build dist /Applications/GrokBuild.app 2>/dev/null
find /Applications/GrokBuild.app -type f -print0 \
  | xargs -0 stat -f '%z %N' \
  | sort -nr \
  | head -40

otool -L /Applications/GrokBuild.app/Contents/MacOS/GrokBuild
codesign --verify --deep --strict /Applications/GrokBuild.app
/usr/bin/codesign -dv --verbose=4 /Applications/GrokBuild.app 2>&1

/Users/jimmyschmitz/.grok/bin/grok --version
```

Inspect `scripts/build-macos-app.sh` and `scripts/build-dev-app.sh` before suggesting compiler or stripping flags. Compare release symbols and size with `size`, `nm`, and `otool`; do not strip blindly and then discover crash reports or signatures became useless.

`make install` replaces `/Applications/GrokBuild.app`. `make clean` removes `.build` and `dist`. Neither command belongs in a read-only audit.

---

## 7. Fable Execution Protocol

Maintain an evidence ledger throughout the run. Every assertion must be one of:

- **Observed:** directly seen in current source/runtime output;
- **Proven:** covered by an executable test or reproducible acceptance receipt;
- **Inferred:** a reasoned conclusion that still needs verification; or
- **Historical:** inherited from the receipt above and potentially stale.

For every finding, record:

```markdown
### [Severity] Short finding title

- Status: Observed | Proven | Inferred | Historical
- Capability:
- Source path and symbols:
- Runtime/process involved:
- Persistence involved:
- User-visible consequence:
- Security/data-loss consequence:
- Weight consequence: bytes | CPU | memory | process | dependency | none
- Evidence:
- Recommended decision: Keep | Fix | Spike | Defer | Delete
- Smallest safe change:
- Tests/acceptance required:
- Rollback:
```

Severity means:

- **P0:** active secret exposure, destructive data loss, or unsafe remote execution;
- **P1:** broken provider/session path, repeated runaway process, or high-probability credential/lifecycle defect;
- **P2:** material interaction failure, duplicated state, hidden work, or maintainability seam likely to cause defects;
- **P3:** polish or low-risk cleanup with no current correctness consequence.

---

## 8. Phase 0 — Freeze the Baseline

Before analysis:

1. capture branch, commit, dirty status, package graph, test count, and installed version;
2. inventory running GrokBuild/Grok/browser/helper processes without killing them;
3. inventory relevant listeners, especially port 9222 and any OAuth callback candidate;
4. verify installed bundle identity and signature without rebuilding;
5. record current app, binary, helper, resource, `.build`, and `dist` sizes;
6. record whether the installed binary matches the current `dist` binary; and
7. record current plugin/MCP names without printing config secrets.

If the baseline differs from this document, update the audit receipt—not the live system—before continuing.

Exit criterion: one reproducible baseline table with commands, timestamps, and redacted outputs.

---

## 9. Phase 1 — Package and Bundle Weight Audit

Build a complete bundle manifest and classify every nontrivial payload.

### Required component decisions

| Component | Starting decision | What could change it |
|---|---|---|
| Main SwiftUI app | Keep | Only feature-level removal changes its role |
| `GrokBuildComputerUseCore` | Keep | Delete only if Computer Use is removed as a product capability |
| `GrokBuildComputerUseMCP` | Keep | Replace only with a demonstrably smaller, equally isolated protocol boundary |
| Bundled `agent-desktop` | Keep | It is intentionally required by packaging; challenge only with real usage and size data |
| Browser MCP script | Keep | Tiny; remove only if unreachable and unregistered |
| Bundled skill folders | Audit individually | Delete if packaging and runtime searches prove one is unused/duplicated |
| Update installer helper | Keep pending trace | Delete only if no signed update path invokes it |
| App icon assets | Keep | Optimize only if asset generation left material duplicate payloads |
| Third-party Swift packages | None; preserve | Addition requires a written system-API insufficiency proof |

Audit the four bundled skill resources individually:

- `grokbuild-browser-control`
- `grokbuild-computer-use`
- `grokbuild-desktop`
- `grokbuild-grok-web`

For each, locate the bundling rule, runtime lookup, invocation path, fallback path, and tests. Search for duplicate copies in source, `.build`, `dist`, app resources, Grok plugin directories, and Application Support. Do not infer use from a folder name.

### Questions Fable must answer

- Is release mode actually used for the installed main binary and helper?
- Are debug symbols or development-only resources embedded in the shipped app?
- Is the same helper or skill copied twice under different resource paths?
- Does the update flow preserve code signing and stable bundle identity?
- Are universal architectures present and intentional?
- Is `agent-desktop` invoked from one canonical owner?
- Would moving an optional capability out-of-process lower idle RSS, or merely add complexity and process overhead?
- Are build artifacts occupying disk but not shipping? Keep operational disk cleanup separate from product bundle optimization.

Exit criterion: a byte-accounted manifest plus Keep/Fix/Defer/Delete decision for every payload over 100 KB and every executable/resource with runtime behavior.

---

## 10. Phase 2 — Capability Ownership and Bolt-On Audit

Create a capability ledger. Trace every meaningful feature through:

```text
User control or event
  → SwiftUI/AppKit action
  → store/view model/service
  → Grok CLI, helper, provider, or macOS owner
  → persistence read/write
  → process/reload effect
  → visible success/failure
```

At minimum, trace:

- new session, send, stop, retry, queue, and transcript replay;
- Settings entry/return and tab routing;
- provider credential save/remove;
- test connection/fetch models;
- default model save;
- provider/model edits and targeted reload;
- compatibility settings;
- workflows, agents, skills, and capabilities;
- browser enable/apply/restart;
- Computer Use start/stop/permission behavior;
- voice/audio behavior;
- updater check/download/install;
- scheduled/background tasks;
- memory/session persistence; and
- app launch, termination, relaunch, and crash recovery.

### Bolt-on heuristics

Search skeptically for:

- two sources of truth for the same provider, model, session, route, or setting;
- UserDefaults values that mirror TOML without a documented projection boundary;
- broad `NotificationCenter` events used where typed ownership exists;
- callbacks that restart every session because impact is unknown;
- fire-and-forget `Task` blocks whose lifetime is not owned;
- timers or observers created by hidden Settings panes;
- services initialized eagerly but used only by an optional feature;
- shell commands that bypass the canonical repository or process owner;
- compatibility fields written only because old Grok versions once accepted them;
- fallback code that silently changes provider, endpoint, auth scheme, or model;
- multiple Grok, browser, helper, or OAuth callback processes;
- resources bundled but never looked up;
- stale feature flags with both branches still alive;
- duplicated URL/auth/error parsing;
- secrets interpolated into command lines, logs, errors, crash metadata, or tests;
- empty catch blocks and errors converted into silent no-ops;
- large views containing service ownership or I/O; and
- main-thread disk, Keychain, subprocess, or network work.

Use compiler warnings, `rg`, call-site tracing, and focused tests. Do not trust an automated “unused code” tool without validating dynamic SwiftUI, Objective-C, notification, menu, selector, and resource lookups.

Exit criterion: every material feature has exactly one declared owner, one persistence contract, one process impact, and one user-visible outcome—or a finding explains the violation.

---

## 11. Phase 3 — Process, Lifecycle, and Concurrency Audit

The previous browser failure mode involved connection attempts to port 9222. Treat lifecycle ownership as a first-class audit, even though the current receipt is quiet.

### Prove these invariants

- One active session maps to the intended one Grok process relationship.
- Default-only model changes affect future sessions and do not restart the current one.
- Provider/model changes reload only idle sessions using affected models.
- Streaming sessions queue reload until the response completes.
- Unaffected sessions do not restart.
- Browser enable/apply/restart cannot leave a stale 9222 retry loop.
- Stopping the browser or Computer Use tears down owned child processes and observers.
- OAuth callback listeners, when added, are bounded to one attempt, loopback-only, and closed on success, error, cancellation, timeout, or app termination.
- Application termination does not orphan Grok, browser, helper, temp, or updater processes.
- Hidden Settings tabs do not continue catalog checks, timers, or model reload work.
- Repeated button presses coalesce or reject duplicate work at the narrow action boundary.

### Concurrency findings to look for

- independent TOML writers that bypass `GrokConfigRepository`;
- actor isolation leaks and `@MainActor` work doing blocking I/O;
- stale async results overwriting newer provider/model selections;
- cancellation not propagating to subprocess or URLSession tasks;
- observer/timer registration without symmetric teardown;
- process stdout/stderr pipes that can deadlock or retain tasks; and
- retry policies without ceilings, backoff, or visible status.

Cross-process TOML locking remains deferred unless the audit proves Grok CLI and GrokBuild can collide in a realistic write window. The in-process repository is necessary; a lock is additional complexity that needs collision evidence.

Exit criterion: lifecycle sequence diagrams and tests/receipts for start, streaming, targeted reload, stop, termination, and browser restart.

---

## 12. Phase 4 — Persistence, Security, and Provider Trust

### Verify the repository contract

Prove with tests that every GrokBuild TOML writer:

- uses `GrokConfigRepository`;
- rereads the latest file before a pure section rewrite;
- preserves unrelated CLI-owned content and comments to the documented extent;
- writes atomically;
- enforces `0600` after every successful write;
- leaves the previous valid file intact on failure; and
- never logs secrets.

### Verify migration and credential boundaries

- UserDefaults contains no provider secrets after migration.
- Keychain service and stable provider IDs are consistent.
- Migration is idempotent.
- A saved provider credential wins over an identical matching model credential.
- Conflicting matching model credentials produce a visible conflict and no guess.
- Keychain writes are read back before legacy values are removed.
- Partial failure restores in-memory state and deletes only newly created Keychain items.
- CLI plaintext projection is the sole necessary duplicate and remains protected by `0600`.

### Fix endpoint trust before adding OAuth/OpenRouter

The next recommended code slice is an explicit endpoint policy. Replace substring-based “local” detection with parsed URL rules:

- `localhost`, IPv4 `127.0.0.0/8`, and IPv6 `::1` are loopback;
- remote presets require HTTPS;
- insecure LAN HTTP requires an advanced, explicit opt-in and a persistent warning;
- provider credentials are never sent after cross-origin redirect;
- HTTPS must not downgrade to HTTP;
- redirect count is bounded;
- catalog and generation requests share the same policy; and
- diagnostics redact query parameters, headers, fragments, and credentials.

Audit and fix the known **remote keyless-auth reconstruction bug**: any `canFetch` or equivalent path must preserve explicit `ProviderAuthScheme.none` rather than reconstructing a provider with default bearer authentication.

### Rich credential envelope for OAuth readiness

The Keychain secret can remain opaque, but metadata must be able to represent:

- credential type: API key, OAuth access token, OAuth refresh token set, or none;
- provider and stable credential ID;
- issuer/origin;
- scopes;
- expiry and refresh eligibility;
- creation/update time;
- revocation/disconnect state; and
- token endpoint/auth method where the provider contract requires it.

Do not place token bodies or refresh tokens in UserDefaults or TOML merely to make the UI easier.

Exit criterion: threat-bound endpoint/auth diagram plus passing migration, permission, redaction, redirect, and provider-status fixtures.

---

## 13. Phase 5 — Interaction, Accessibility, and Hidden Work

Use `docs/UI_ACCEPTANCE_MATRIX.md` as the baseline and expand it wherever the capability trace discovers an unlisted control.

Prove on the installed app—not only a SwiftUI preview—that:

- Main → Settings → Models works on the first click;
- Session and Escape return to the same active session;
- the gear returns to the last Settings tab;
- contextual links route to their requested tab;
- Settings entry, tab changes, validation, and return never silently change the session model;
- toolbar hit regions are at least 32 × 32 points;
- hover, pressed, focus, disabled, and busy states remain distinct;
- only the active asynchronous action is disabled;
- repeated taps cannot launch duplicate requests;
- Checking, Applying, Saved, and actionable failure states are visible;
- a valid key plus absent model says **model unavailable**, not **authentication failed**;
- provider cards show credential presence, validation status, selected model availability, and last check time without leaking secrets;
- keyboard and pointer routes agree;
- VoiceOver names and keyboard focus remain usable; and
- hidden Settings panes are not polling, observing, or doing network/process work without need.

Do not broaden this into a browser back/forward redesign. That remains deferred unless the audit finds the existing route model cannot satisfy the stated flow.

Exit criterion: completed live matrix with one settled receipt per route/action and no unintended model/process change.

---

## 14. Phase 6 — Cache, Temp, Log, and Dock Audit

This phase answers Jimmy’s original operational questions without bolting a cleaner or daemon onto the app.

### Storage classification

Measure likely GrokBuild-owned locations and classify each item:

| Class | Examples | Default action |
|---|---|---|
| Durable user data | sessions, workflows, provider metadata, browser profile | Keep |
| Security-sensitive durable data | Keychain, CLI config, OAuth grants | Keep and protect |
| Rebuildable project output | `.build/`, `dist/` | Report size; delete only with approval |
| Rebuildable application cache | app caches, thumbnails, transient catalogs | Candidate for precise cleanup |
| Historical diagnostics | bounded logs, crash reports | Keep recent; propose retention if growth is material |
| Orphaned temp/update data | abandoned staging directories, stale downloads | Candidate only after owner and age are proven |
| Unrelated system/app data | anything not clearly owned by GrokBuild | Out of scope |

Report exact path, size, owner, newest/oldest modification, regeneration behavior, cleanup risk, and whether the running app has the item open. Never use a broad recursive deletion target, unresolved glob, `$HOME`, or `~` in a destructive command.

### Dock acceptance

Verify:

1. `/Applications/GrokBuild.app` is the launched copy;
2. bundle identifier remains `com.grokbuild.app` across builds/updates;
3. the Dock tile can be set to **Keep in Dock**;
4. quitting the app leaves the tile;
5. relaunching from that tile opens `/Applications/GrokBuild.app`; and
6. an authorized update does not create a duplicate or question-mark tile.

Do not create a background process to keep an icon visible. That would solve the wrong problem and make the app less light.

Exit criterion: a read-only storage report plus Dock behavior receipt and the smallest operational fix, if any.

---

## 15. Phase 7 — OpenRouter and OAuth Decision

The default recommendation is to add OpenRouter only after endpoint policy and keyless-auth correctness are fixed.

### Minimal native design

Implement as an optional provider adapter behind existing typed capabilities:

- native `URLSession` for catalog and validation;
- explicit OpenRouter auth scheme and headers;
- S256 PKCE OAuth only if current OpenRouter documentation and account behavior require/support it for this client;
- system browser, never an embedded credential web view;
- Keychain tokens plus metadata envelope;
- catalog search/filter with model identity, context, capabilities, and pricing metadata where returned;
- model pinning by stable provider model ID;
- clear “via OpenRouter” labeling in provider card, model chooser, session metadata, and diagnostics;
- no silent provider fallback;
- no billable test without explicit action and usage receipt; and
- no third-party Swift dependency unless a written proof shows the native stack cannot safely implement the required protocol.

### Required decision questions

- Does OpenRouter OAuth materially improve setup over a Keychain API key for this native client?
- What redirect URI and app-registration contract is actually supported today?
- Can the provider revoke/refresh cleanly from a native client?
- Does the catalog distinguish modality, tools, context, pricing, availability, and provider routing reliably enough for the UI?
- Which information is advisory and which is safe to enforce?
- How are provider-side aliases and model retirement surfaced without silently changing an existing session?
- Does OpenRouter add value beyond the already-working direct OpenAI and Kimi paths?

If OAuth is not actually supported for this client shape, do not fake it. Ship Keychain-backed API-key configuration first and keep the credential envelope OAuth-ready.

Exit criterion: one current-doc-backed protocol decision, fixtures for auth/catalog/error cases, and a dependency-neutral implementation plan.

---

## 16. Phase 8 — ACP/Goose Backend Spike, Not a Cursor Rewrite

GrokBuild currently uses Grok’s ACP path. The audit should determine whether its backend boundary is truly generic or merely named generically.

### Spike questions

- Does GrokProcess consume ACP initialize/auth/version/capability data, or ignore it?
- Which events and methods are Grok-specific?
- Are session, tool, attachment, permission, reasoning, usage, cancellation, and replay semantics representable across ACP backends?
- Can provider/model configuration remain backend-scoped?
- Can one session bind immutably to one backend without global state bleed?
- Can a second backend be added without adding its SDK to the app target?
- Does Goose expose enough compatible behavior to justify a small adapter?

Perform a bounded design or prototype spike only after the audit. Success means a narrow backend protocol and fixture-driven compatibility evidence. Failure means documenting why Grok remains the only supported backend.

Do **not**:

- make Cursor’s proprietary harness the core;
- embed a general-purpose agent runtime;
- add LiteLLM, OpenHands, AG-UI, or a Node/Python control plane;
- build arbitrary OAuth issuer support; or
- mix two backend processes inside one session.

Exit criterion: Keep Grok-only or approve a narrow Goose/ACP adapter, with measured weight and complexity delta.

---

## 17. Recommended Implementation Order

After the audit is accepted, use small reversible slices in this order:

1. **Endpoint trust policy and remote keyless-auth preservation.** This is foundational security/correctness for every later provider.
2. **Regression fixtures for redirects, loopback/LAN rules, keyless endpoints, redaction, and provider statuses.** Lock the contract before expansion.
3. **Operational cache/Dock closeout.** Prefer documentation and OS behavior; add no resident process.
4. **Credential metadata envelope.** Preserve existing Keychain/TOML behavior while making OAuth state representable.
5. **OpenRouter API-key preset and catalog path.** Keep it opt-in and dependency-free.
6. **OpenRouter OAuth/PKCE only if the live provider contract proves it is appropriate.** Add disconnect, expiry, and refresh acceptance.
7. **Live OpenRouter smoke only with explicit authorization.** Stop on first provider error and report returned usage/cost.
8. **Bounded ACP/Goose spike.** Decide whether a second backend earns product support.
9. **Evidence-backed bolt-on removals or file splits.** Do these after ownership is proven, never as cosmetic cleanup.

Every slice must keep `make test` green and add tests proportionate to the risk introduced.

---

## 18. Explicit Deferrals Unless Evidence Changes

Defer these by default:

- cross-process TOML locking without a reproduced collision;
- replacing all `NotificationCenter` usage merely for stylistic consistency;
- splitting every large Settings/View file solely by line count;
- browser back/forward redesign;
- Cursor harness integration;
- OpenHands, AG-UI, LiteLLM, or generic provider orchestration;
- arbitrary OpenID/OAuth issuer support;
- an embedded browser engine or Electron shell;
- a GrokBuild background daemon, Dock keeper, or generic disk cleaner;
- a second plaintext credential store;
- a project `.env` for provider keys; and
- plugin reinstalls, broader MCP allowlists, or silent provider fallbacks.

Deferral is not neglect. Each item can be reopened only with a reproduced failure, measured benefit, or concrete user capability that cannot fit the current architecture.

---

## 19. Verification and Acceptance Gates

### Automated gate

For each authorized code slice:

```bash
cd '/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop'
make test
git diff --check
```

Add or retain coverage for:

- concurrent TOML mutations and unrelated-section preservation;
- atomic failure behavior and `0600` permissions;
- Keychain migration, rollback, conflicts, and idempotence;
- credential/log/diagnostic redaction;
- provider 200 catalog, empty catalog, missing model, 401, 403, 404, 429, 5xx, malformed JSON, timeout, offline, and keyless local endpoint;
- redirect origin/downgrade/limit policy;
- explicit `.none` auth preservation;
- targeted configuration reload while idle and streaming;
- browser lifecycle and no stale 9222 loop;
- hidden-pane inactivity;
- route/model preservation; and
- OAuth state, PKCE, cancellation, timeout, disconnect, expiry, and refresh if OAuth is implemented.

### Secret-safe backend gate

- Validate with local fixtures before any real provider call.
- Do not print `~/.grok/config.toml` or preferences wholesale.
- Do not pass secrets on command lines.
- Do not snapshot or record Keychain values.
- Treat provider prompts as billable.
- Stop on the first real provider error.
- Record returned token usage and cost when available.

### Live app gate

Project instructions require Computer Use for live UI acceptance after code changes. Test the signed installed app at `/Applications/GrokBuild.app`, not merely a preview. Installation must be explicitly authorized because it replaces the installed bundle.

Check:

- first-click Main ↔ Settings ↔ Models ↔ Session routes;
- pointer, Escape, and keyboard focus equivalence;
- no session model drift;
- visible provider action states and recovery;
- VoiceOver labels;
- Dock persistence after quit;
- browser enable/apply/restart once;
- no port-9222 refused spam;
- idle CPU/process count after settling; and
- signature, bundle identity, version, and stable install path.

### Packaging gate

Compare before/after:

- package dependency graph;
- bundle and DMG size;
- main binary/helper/resource byte table;
- cold launch and idle RSS/CPU;
- process/listener count; and
- disk/cache delta after one controlled session.

Reject a change that claims to be “lighter” while adding an always-resident process, third-party runtime, hidden network work, or duplicated provider/session ownership.

---

## 20. Required Fable Deliverables

Create these standalone Markdown artifacts in the repository:

1. `docs/FABLE_5_AUDIT_FINDINGS.md`
   - current receipts;
   - capability ledger;
   - package/bundle manifest;
   - process/lifecycle map;
   - persistence/security map;
   - interaction matrix gaps;
   - storage/Dock report; and
   - severity-ranked findings with evidence.

2. `docs/FABLE_5_LIGHTWEIGHT_DECISIONS.md`
   - one Keep/Fix/Spike/Defer/Delete row per component and finding;
   - measured weight/resource consequences;
   - system-API versus dependency choice;
   - OpenRouter/OAuth decision;
   - ACP/Goose decision; and
   - explicit rejected alternatives with reasons.

3. `docs/FABLE_5_IMPLEMENTATION_PLAN.md`
   - ordered slices;
   - exact files/symbols expected to change;
   - tests and live acceptance for each slice;
   - migration/rollback plan;
   - authority required; and
   - stop conditions.

If implementation is authorized, update the existing canonical documents rather than creating contradictory architecture:

- `ARCHITECTURE.md`
- `docs/ARCHITECTURE_AUDIT.md`
- `docs/UI_ACCEPTANCE_MATRIX.md`
- `docs/OAUTH_OPENROUTER_ACP_PLAN.md`
- `README.md`
- `BUILDING.md` or `scripts/README.md` when packaging behavior changes.

### Final handoff format

End the Fable run with:

```markdown
# GrokBuild Fable 5 Handoff

## Current repository/install truth
## What was inspected
## Findings by severity
## Lightweight decisions
## What changed, if authorized
## Tests and live receipts
## Secrets and data safety
## Deferred work and why
## Exact next authorization needed
```

Include exact absolute paths, branch, commit, dirty status, commands run, test counts, app identity, and any remaining uncertainty. Do not call an unverified inference “fixed.”

---

## 21. Definition of Done

This audit is done only when:

- every shipped executable/resource has a proven owner and decision;
- every major user capability has an end-to-end ownership trace;
- duplicate state and restart/reload effects are explicit;
- no secret-handling assertion relies on raw secret output;
- endpoint trust and keyless-provider behavior have a concrete correction plan;
- OpenRouter is either approved as a small optional adapter or rejected with current evidence;
- OAuth is native and provider-scoped or explicitly deferred;
- the ACP/Goose question has a bounded decision rather than an accidental framework rewrite;
- cache/temp candidates are classified without deleting durable data;
- Dock persistence is solved through stable macOS identity, not a daemon;
- bundle/process/resource baselines make “lightweight” measurable;
- `make test` remains green for any authorized code changes;
- installed-app acceptance is completed for any authorized UI/runtime changes; and
- all findings, decisions, deferrals, and next authorization are written into the three Fable deliverables.

The bar is not “the code looks cleaner.” The bar is that GrokBuild is smaller in responsibility, clearer in ownership, safer around credentials and processes, dependable on the first click, and still unmistakably a thin native shell around Grok.
