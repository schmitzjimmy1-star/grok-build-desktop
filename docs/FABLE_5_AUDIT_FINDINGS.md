# Fable 5 Audit Findings — GrokBuild

> Produced by Claude Fable 5 on **July 31, 2026** against branch `codex/warm-glass-ui`,
> HEAD `ac31979438bccc5d6f2c1b90d01eda047543b859`, intentionally dirty worktree.
> Companion documents: `FABLE_5_LIGHTWEIGHT_DECISIONS.md`, `FABLE_5_IMPLEMENTATION_PLAN.md`.
> Execution contract: `CLAUDE_FABLE_5_LIGHTWEIGHT_AUDIT_PLAN.md`.
>
> Line numbers cite the worktree as audited. The endpoint-trust slice implemented during
> this run (see §9 and the implementation plan) shifted some lines in
> `CustomModelSettings.swift`, `SettingsView.swift`, and `GrokConfigRepository.swift`;
> symbols are stable.

## 1. Baseline receipts (2026-07-31, all reverified live)

| Fact | Value | Status |
|---|---|---|
| Branch / HEAD | `codex/warm-glass-ui` @ `ac31979` ("Collapse repeated identical system notes") | Observed |
| Worktree | Dirty as documented: 14 modified + 13 untracked (architecture/provider/test/docs work) | Observed |
| Tests before this run | `make test` → **307 tests, 0 failures** (6.9 s) | Proven |
| Tests after this run's slice | `make test` → **324 tests, 0 failures** (7.2 s) | Proven |
| Installed app | `/Applications/GrokBuild.app` 0.1.20, `com.grokbuild.app`, 16 MB | Observed |
| Signature | `codesign --verify --deep --strict` PASS; Apple Development, Team `DD2GCQJVB4` | Proven |
| Installed binary vs `dist` | byte-identical (`cmp`) | Proven |
| Architectures | arm64-only (main, agent-desktop, helper) | Observed |
| SwiftPM dependencies | **none** ("No external dependencies found") | Proven |
| Linked frameworks | Apple-only: AppKit/SwiftUI/Security/CFNetwork/WebKit/Speech/AVFAudio/Accessibility + Swift runtime; zero third-party dylibs | Observed |
| Processes at baseline | No GrokBuild/grok/agent-desktop processes; **no port-9222 listener**; no grok-owned TCP listeners | Observed |
| Grok CLI | `grok 0.2.117 (f1c06093089f) [stable]` at `~/.grok/bin/grok` | Observed |
| `~/.grok/config.toml` | mode **0600**, 1,577 bytes; plugins enabled: chrome-devtools-mcp, base44, 42crunch; disabled: tinyfish, aws-amplify; MCP: chrome-devtools only; models `gpt-5.6-terra` (responses backend) + `kimi-k3`; no `grokbuild_*`/`disabled_mcp_servers` remnants | Observed |
| Preferences plist | 56 keys, 10.3 KB, key names/types only inspected — **no credential-shaped keys**; secrets absent by construction (custom `Provider.encode` omits `apiKey`) | Observed/Proven |
| Dock | GrokBuild pinned in `persistent-apps`, tile bound to `file:///Applications/GrokBuild.app/`, bundle id `com.grokbuild.app` | Observed |

Framework linkage is explained by reachable product features, not bloat: WebKit ← `PreviewPane` (HTML preview), Speech/AVFAudio ← `VoiceInputService` (lazy, permission-gated), Accessibility ← Computer Use.

## 2. Capability ledger

Every material capability, its single owner, persistence, process impact, and outcome path.
"✅" = ownership clear; "⚠" = finding attached (see §9).

| Capability | UI entry | Owner | Persistence | Process impact | Status |
|---|---|---|---|---|---|
| Session create/select/close | Sidebar, toolbar | `ContentView` liveSessions + `ChatStore` (1 per tab) | `SessionLayoutStore`, `SessionMessageStore` (prompt-boundary writes) | 1 `grok … agent stdio` per live tab, LRU cap 4 | ⚠ F3 (closed-tab stores never freed) |
| Send / stop / queue | Composer | `ChatStore.deliverPrompt` / `PromptQueue` | transcript store | `session/prompt` / `session/cancel` | ⚠ F17 (no prompt timeout) |
| Transcript replay/repair | automatic | `GrokSessionTranscriptImporter` | `~/.grok/sessions/**/chat_history.jsonl` (read-only) | none | ✅ |
| Model default + per-model edits | Settings ▸ Models | `CustomModelStore` via `GrokConfigRepository` | TOML `[model.*]` + metadata sidecar | `ConfigurationChange`: default-only = none; affected models = targeted restart w/ resume, queued while streaming | ✅ (proven in source; live streaming case untested — T2) |
| Provider credentials | Settings ▸ Models | `ProviderStore` + Keychain `com.grokbuild.provider-credential` | Keychain (authoritative) + per-model TOML projection (0600) | none | ✅ |
| Test connection / fetch models | Settings ▸ Models | `ProviderModelFetcher` (+ `ProviderEndpointPolicy` as of this run) | none | none | ✅ after this run (was ⚠ F1/F2) |
| Compat toggles | Settings ▸ Compatibility | `CompatConfigStore` (13 cells) | TOML `[compat.*]` | none | ✅ |
| Workflows enable | Settings ▸ Workflows | `WorkflowsConfigStore` | TOML | reload note | ✅ |
| Agents/Skills/Plugins/Marketplace/MCP/Hooks panes | Settings | per-pane `GrokCLIService` instances | none (CLI owns) | one-shot `grok` subprocesses | ⚠ F9 (no timeout), F15 (double-tap, stale-on-workspace-switch) |
| Browser tools | Settings ▸ Browser, chat pill | `AgentBrowserService` (stateless) + applied-settings keys | UserDefaults draft/`applied.*` split | grok spawns `grokbuild-browser` bridge; external CDP Chromium launched unowned | ⚠ F4 (apply restarts w/o resume), F11 (no teardown/timeout) |
| Computer Use | Settings ▸ Computer Use | `ComputerUseService` + `GrokBuildComputerUseMCP` helper (spawns agent-desktop per call, SIGTERM→SIGKILL escalation) | UserDefaults draft/applied | grok child; per-call actuator | ✅ core; ⚠ F4 applies here too |
| Cursor integration | Settings ▸ Computer Use | `ComputerUseCursorInstaller` | `~/.grokbuild/computer-use/`, `~/.cursor/mcp.json` (merge-preserving) | none | ✅ user-initiated |
| Voice input | Composer mic | `VoiceInputService` (lazy) | none | none until used | ✅ |
| Git/PR | Status row, PreviewPane | `GitService` | none | `git`/`gh` subprocesses | ⚠ F10 (pipe deadlock) |
| App updates | Menu, panel | `UpdateScheduler`/`UpdateChecker`/`AppUpdater` + bundled install helper | `…/GrokBuild/Updates/`, defaults | GitHub API poll (30 s after launch, then 24 h); bash helper survives quit by design | ⚠ F6/F7/F13 |
| Grok CLI update | Update panel | `GrokCLIUpdater` (`grok update`) | none | posts prepare-for-shutdown first | ✅ |
| Memory | Settings ▸ Memory, pill | `MemoryStore` + launch flag | `~/.grok/memory` | flag per session | ✅ |
| Scheduler/workflow/background pills | Chat | tracker stores parsing ACP payloads | none | none | ✅ (wire-shape drift risk noted by tests) |
| Single instance / Dock | — | `flock` on `instance.pid` + Distributed notification | — | — | ✅ |

**ACP consumption (Phase 8 evidence):** `GrokProcess` speaks standard ACP JSON-RPC
(initialize → session/new|load → session/prompt|cancel|set_mode|set_model; handles
session/update, request_permission, fs/read|write). It **ignores** the initialize
response's capabilities/authMethods/protocol version, and infers auth failure by
string-sniffing ("login"/"auth") — `GrokProcess.swift:224-230`, `736-755`. xAI-specific
surface is enumerable: `x.ai/exit_plan_mode`, `x.ai/ask_user_question`, `_meta.isReplay`,
`_meta.totalTokens`, `set_model` `_meta.model.Ok`, FS_NOT_FOUND fallback, scheduler/workflow
tool-name sniffing, slash commands. A narrow backend protocol is feasible; nothing else in
the app assumes Grok internals.

## 3. Package and bundle manifest (byte-accounted)

`/Applications/GrokBuild.app` = 16 MB. `dist/` 21 MB, `.build/` 815 MB (rebuildable, not shipped).

| Payload | Bytes | Origin | Runtime owner | Decision |
|---|---|---|---|---|
| `MacOS/GrokBuild` | 13,704,160 | `swift build -c release` (`build-macos-app.sh:71`) | — | Keep |
| `MacOS/agent-desktop` | 2,251,376 | prebuilt external binary, bundled by `bundle-agent-desktop.sh` (hard-required, smoke-tested `agent-desktop version`) | `ComputerUseService` (prefers bundled copy) + helper per tool call | Keep |
| `Resources/AppIcon.icns` | 305,895 | generated at build | — | Keep |
| `MacOS/GrokBuildComputerUseMCP` | 195,872 | SPM executable target | grok-spawned stdio MCP | Keep |
| `Resources/grokbuild-browser-mcp` | 5,547 | `scripts/grokbuild-browser-mcp` (Python bridge, 7 tools) | registered in `session/new` when browser enabled | Keep |
| `Resources/Skills/grokbuild-grok-web` | 3,355 | `GrokBuild/Resources/Skills` | `BrowserSkillInstaller` → `~/.grok/skills` when browser enabled | Keep |
| `Resources/Skills/grokbuild-computer-use` | 2,974 | same | `ComputerUseSkillInstaller` when CU enabled | Keep |
| `Resources/Skills/grokbuild-browser-control` | 2,749 | same | `BrowserSkillInstaller` | Keep |
| `Resources/grokbuild-install-update` | 1,775 | `scripts/grokbuild-install-update.sh` | `AppUpdater` post-download | Keep + Fix (F7) |
| `Resources/Skills/grokbuild-desktop` | 1,034 | same | **none — zero references in Swift source** (`rg` matches only `Package.swift:34`) | Delete-candidate (F18) |
| MenuBar PNGs + Info.plist | ~2.9 KB | build script | AppDelegate | Keep |

Pipeline notes (Observed): release config always used for dist; no stripping/dSYM step
(dSYMs stay in `.build`, never ship); SPM `.copy` resources land only in the unused
`GrokBuild_GrokBuild.bundle` — packaged apps use the scripts' copies, and installers
check `Bundle.main` first, so **no payload ships twice**. arm64-only is intentional-by-default
(macOS 26 minimum). Signing order: helpers first (`--timestamp=none`, no hardened runtime),
then bundle (`--options runtime`, one entitlement: `allow-unsigned-executable-memory`),
deliberately **without `--deep`** to preserve the shared Accessibility grant — which
contradicts `BUILDING.md:133` and creates a notarization hazard (F8).

## 4. Process and lifecycle map

```
launch: main.swift → AppDelegate: flock single-instance → legacy migrations →
        UpdateScheduler.start (30 s, then 24 h loop) → ContentView
session: ChatStore → restartProcess: 30 s watchdog → skill installs (if enabled) →
        ensureExternalBrowserStarted (≤ 20×250 ms probe of /json/version, then throw) →
        mcpServers [grokbuild-browser, grokbuild-computer-use] →
        GrokProcess.start: spawn `grok … agent stdio` → initialize → session/new|load → ready
stream: deliverPrompt → session/prompt → session/update chunks → finishPrompt →
        apply queued ConfigurationChange → drain prompt queue
model config change: SettingsView persist(change:) → ContentView fans to ALL stores →
        ChatStore.applyConfigurationChange: only .modelRuntime ∩ currentModel restarts,
        WITH resume id, queued while streaming            ← surgical, correct
browser/CU/MCP apply: pane → active store reloadConfiguration() → restartProcess
        with NO resume id and NO streaming guard          ← F4
quit: applicationWillTerminate → post .grokBuildPrepareForShutdown →
        fire-and-forget Task { stores.shutdown() } racing process exit; grok children
        die via stdin EOF; external CDP Chromium survives; updater helper survives by design
```

Verified invariants (Observed/Proven): one session ↔ one grok process (LRU cap 4);
default-only model change restarts nothing; affected-model restarts resume the grok
session and queue while streaming; **no unbounded 9222 retry loop exists** (bounded
20×250 ms probe; the historical failure mode is structurally gone); helper kills
agent-desktop with SIGTERM→2 s→SIGKILL so no actuator orphan survives a timeout; no
`Timer`s anywhere; NotificationCenter observers are torn down symmetrically (18 names
inventoried — no leaked-observer finding).

Violations: F3, F4, F11, F12, F17 below.

## 5. Persistence and security map

**TOML boundary (Proven):** all five writers (`CustomModelStore`, `SubagentRoleStore`,
`CompatConfigStore`, `WorkflowsConfigStore`, `GrokConfigLegacyMigration`) go through
`GrokConfigRepository.update` — serialized, reread-latest, atomic temp+`rename(2)`,
0600 created and re-enforced, original intact on failure. `rg` found **no bypass**.
As of this run a present-but-unreadable file fails the update instead of silently
rewriting from empty (was F5).

**Credential boundary (Proven):** Keychain service `com.grokbuild.provider-credential`,
account = provider ID; migration is idempotent, prefers provider key over model keys,
reports multi-key conflicts without guessing, verifies by read-back, rolls back created
entries on partial failure. UserDefaults blobs structurally cannot contain the key
(custom `encode` omits it). The single plaintext copy is the CLI-required per-model
TOML projection under 0600. Zero `print/NSLog/os_log/Logger` in the credential path;
diagnostics show presence booleans and (as of this run) query-stripped endpoints.

**Endpoint trust (fixed this run):** locality by parsed exact host
(`localhost`/`*.localhost`/`127.0.0.0/8`/`::1` + `0.0.0.0`/`host.docker.internal` aliases);
remote `http://` rejected at validation and refused a credential at request time
(`insecureEndpoint`); redirects bounded to 3 same-origin hops, cross-origin/downgrade
refused (`redirectBlocked`); explicit `.none` auth preserved through `canFetch`.

**Remaining seams:** `GrokConfigRepository.read()` still collapses read failure to `""`
(load-side only, no write amplification — F21); `contextTokens` is dual-homed with
documented precedence (TOML wins, sidecar fills nil); cross-process TOML locking stays
deferred (no reproduced collision; CLI writes were not observed during the audit window).

## 6. Interaction matrix gaps

`docs/UI_ACCEPTANCE_MATRIX.md` (2026-07-31, installed app) already covers 21 rows live.
Audit additions needing a live pass (not yet in the matrix):

1. New provider badges/states from this run: **Insecure URL** and **Redirect blocked**.
   → *Partially closed 2026-07-31 PM*: draft-editor message surfaces live-verified
   (insecure refusal + https validation); saved-row badges and live redirects remain
   fixture-only. See the matrix's "Fable 5 endpoint-trust slice" section.
2. Keyless `.none` remote provider: Test connection enabled and succeeding (fixture exists; live stub pass pending).
   → *Closed 2026-07-31 PM*: live-verified on the installed slice build — button enabled,
   request issued, typed DNS transport error returned.
3. Plugins/Marketplace/MCP rapid double-tap (F15) — no current row covers repeated mutation taps.
4. Workspace switch → revisit Skills/Hooks/Agents panes: stale-data behavior (F15b).
5. Browser/CU Apply while a session is streaming (F4) — matrix verified idle apply only.
6. Composer sub-32 pt controls and missing pill a11y labels (F22).

Code-level a11y/interaction receipts (Observed): 32×32 hit targets on the four chrome
buttons; provider actions disable only themselves; model-missing vs unauthorized are
distinct typed statuses; Esc/⌘. routes work; slash menu fully keyboard-navigable;
reduce-motion respected; VoiceOver stream-end announcement present.

## 7. Storage and Dock report (read-only; nothing deleted)

| Path | Size | Class | Action |
|---|---|---|---|
| `~/Library/Application Support/GrokBuild/BrowserProfiles` | **138 MB** | Durable user data (browser profile: cookies/logins) | Keep; only candidate if user explicitly resets browser identity |
| `~/Library/Application Support/GrokBuild/instance.pid` | trivial | runtime lock | Keep |
| `~/Library/Caches/com.grokbuild.app` | 2.6 MB | Rebuildable URL/WebKit cache | Safe to purge anytime; too small to bother |
| `~/.grokbuild/computer-use` | 2.3 MB | Durable tool snapshot (helper + agent-desktop for Cursor) | Keep while Cursor integration in use |
| `~/Library/Saved Application State/com.grokbuild.app.savedState` | absent | OS-managed | — |
| `~/Library/Preferences/com.grokbuild.app.plist` | 10.3 KB | Durable settings/metadata | Keep |
| Repo `.build/` | **815 MB** | Rebuildable dev output | Largest reclaimable item; `make clean` when explicitly desired (destructive, not audit-default) |
| Repo `dist/` | 21 MB | Rebuildable, but the currently-installed build's source | Keep until next release |
| `~/.grok` | 453 MB | **Grok CLI-owned**, not GrokBuild's | Out of GrokBuild scope; largest slices: `downloads` 371 MB, `installed-plugins` 28 MB, `sessions` 22 MB — a `grok`-side cleanup question for xAI tooling, not an app feature |

**Dock (Observed, solved):** the tile is already pinned in `persistent-apps` bound to
`/Applications/GrokBuild.app` + `com.grokbuild.app`; the in-app updater preserves both
path and identity (`ditto` into the existing directory, Info.plist hardcodes the bundle
id). No daemon or helper is needed or justified. Two footnotes: `make install` is
`rm -rf`+`cp -R` (delete+recreate — fine for path-based Dock tiles, noted for
completeness), and LaunchServices also registers `dist/GrokBuild.app` — launch the
`/Applications` copy for daily use.

## 8. Test suite map

28 files, 324 methods (307 pre-run + 17 added), 0 skips. Strong: TOML concurrency +
preservation, Keychain migration logic, provider catalog matrix (200/empty/missing/401/
403/404/429/5xx/malformed/timeout), CU helper env-parity + pipe-drain + kill-escalation,
session persistence, wire-shape regression fixtures, and (new) endpoint policy/redirects/
keyless/read-failure. Weak/absent: streaming-reload integration, app-termination child
cleanup, browser runtime lifecycle, real-Keychain adapter, redaction sweep of log lines,
release-config `#if DEBUG` suites silently absent, several suites mutate
`UserDefaults.standard` (crash leaks state into the real app).

## 9. Findings by severity

Statuses: Observed / Proven / Inferred / Historical. "FIXED THIS RUN" = implemented and
covered by tests in this session (see implementation plan §Slice 1–2 for exact diffs).

> **Second implementation pass (2026-07-31 evening), authorized:** F3, F4, F9, F10,
> F11 (timeout/drain part), F12, F14, F15a, and F20 are now **fixed** — see
> `FABLE_5_IMPLEMENTATION_PLAN.md` §"Slices 3, 4, 5, and 7-partial" for the exact diffs,
> the 334-test receipt, and the 0.32 s zero-orphan quit receipt. F16 was re-examined and
> reclassified: the Models-tab write is drift-gated credential-projection repair, not an
> unconditional write-on-open. The finding bodies below preserve the audit-time record.
>
> **Third implementation pass (2026-07-31, slice 6), authorized:** F6, F7 (plus the
> helper self-overwrite), F8, and the updater half of F13 are now **fixed** — fail-closed
> TeamID policy, stage-then-swap install with staged-bytes verification and rollback,
> hardened-runtime + timestamped helper signatures (agent-desktop proven to run signed),
> and off-main updater verification. 340 tests green; see the plan's §"Slice 6 — DONE".
>
> **Fourth + fifth passes (2026-07-31, quick wins + final polish), authorized:** F18,
> F19, F13 (core), F15b, F17, F22 (⌘,-tab, pill labels, sidebar keyboard; composer
> sizing deferred to Jimmy's design pass), and **F23 (fixed on the third attempt — see
> the matrix for the two falsified hypotheses)** are closed; the upstream app-release
> feed is gated off for personal use, and the trusted-LAN http opt-in shipped
> (provider-level, live-verified). 344 tests green. Remaining open by design: F21
> documented non-changes, chat auth string-sniffing (ACP-spike scope), composer control
> sizing (design domain), and the feature road (OpenRouter slices 8–9, Goose spike).

### [P1] F1 — Explicit `.none` auth rebuilt as `.bearer`, bricking keyless remote providers — **FIXED THIS RUN**
- Status: Proven (was Observed defect; now regression-tested)
- Source: `SettingsView.swift` `canFetch` reconstructed `Provider` without `authScheme`;
  init default `.bearer` made the `.none` branch dead code. Effect: Test connection /
  Fetch models permanently disabled for keyless remote endpoints (e.g. LAN vLLM).
- Fix: `canFetch(baseURL:apiKey:authScheme:providerID:)` + all three call sites pass the
  real scheme; latent twin `ProviderModelFetcher.fetch(baseURL:apiKey:)` (zero callers,
  same reconstruction bug) deleted.
- Tests: `ProviderEndpointPolicyTests.testKeylessSchemeBuildsRequestWithoutAuthHeadersForRemoteEndpoint`, `testStoreRoundTripPreservesExplicitKeylessSchemeForRemoteProvider`, `testKeylessRemoteHTTPRequestProceedsWithoutCredential`.

### [P1] F2 — Endpoint trust by substring; no HTTPS rule; no redirect policy — **FIXED THIS RUN**
- Status: Proven (was Observed)
- Source: `isLocalEndpoint` was `baseURL.contains("localhost")`-style on both
  `CustomModel` and `Provider` (`localhost.evil.example` classified local); validation
  accepted remote `http://` with a bearer key (cleartext credential); fetches used
  `URLSession.shared` defaults — auth headers followed any 30x cross-host.
- Fix: `ProviderEndpointPolicy` (parsed-host locality, transport rule, redaction) +
  `ProviderRedirectPolicyDelegate` (≤3 same-origin hops, downgrade refused) wired into
  both fetch paths; `insecureEndpoint`/`redirectBlocked` typed statuses + badges;
  diagnostics endpoint now query-stripped.
- Failure scenario closed: provider answering 302 → attacker host no longer receives
  `Authorization` header (proven by `testValidationBlocksCrossOriginRedirectWithoutFollowingIt` —
  the second origin is never contacted).

### [P1] F3 — Closed sessions never freed: ACP event stream never finishes
- Status: Observed structure; leak Inferred (unmeasured)
- Source: `ChatStore.swift:164` `Task { [weak self] … consumeOutput() }` holds `self`
  strongly across `for await` on `process.acpEventStream` (`:1281-1285`);
  `GrokProcess.cleanupProcess` never calls `acpEventContinuation.finish()`
  (`GrokProcess.swift:512` only yields a note). Every closed tab's ChatStore+GrokProcess
  (plus `.unbounded` stream buffer) stays resident for the app's lifetime.
- Consequence: memory growth per closed session; "lightweight" violation, not data loss.
- Smallest fix: `finish()` the continuation in `cleanupProcess`; assert deallocation in a
  test via weak reference. Rollback: one-line revert.

### [P1] F4 — Browser/Computer-Use/MCP applies restart the active session without resume and without a streaming guard
- Status: Observed
- Source: panes wire `store.reloadConfiguration()` (`SettingsView.swift:219-256`) →
  `restartProcess()` with default `resumeSessionID: nil` (`ChatStore.swift:350-355, 443`)
  → `session/new`. The surgical path (`applyConfigurationChange`) exists but only covers
  model changes (`ConfigurationChange` has no browser case — `Models/ConfigurationChange.swift`).
- Consequence: toggling browser tools mid-conversation silently drops the grok-side
  session context; applying during streaming kills the in-flight response. Other live
  sessions keep stale MCP wiring until their own restart (partially intentional).
- Smallest fix: pass `resumeID = grokSessionId ?? savedGrokSessionID` and reuse the
  `pendingConfigurationChange` queue for this path.

### [P2] F5 — `GrokConfigRepository.update` rewrote config from empty on transient read failure — **FIXED THIS RUN**
- Status: Proven
- Fix: present-but-unreadable file now throws; missing file still starts empty. Test:
  `testUpdatePropagatesReadFailureInsteadOfRewritingFromEmpty` (chmod 000 fixture).

### [P2] F6 — Updater TeamID pinning silently skipped for unsigned installs
- Status: Observed
- Source: `AppUpdater.swift:250-255` — team equality checked only when **both** apps
  report a TeamID; a dev/ad-hoc installed copy accepts any validly notarized app from any
  developer if the feed serves it. Release-feed "notarized" gate is a text heuristic
  (`UpdateChecker.swift:129-138`); real gates are codesign/spctl/team (`AppUpdater.swift:239-257`).
- Consequence: bounded supply-chain risk (attacker still needs Apple notarization +
  feed/TLS compromise); identity continuity not guaranteed from unsigned installs.

### [P2] F7 — Install is merge-copy, strips quarantine after verifying the wrong artifact
- Status: Observed; consequences Inferred
- Source: `grokbuild-install-update.sh:78-79` — `ditto` merges (files deleted upstream
  linger inside the installed bundle and can break the seal), no rollback on mid-copy
  failure, `xattr -cr` strips quarantine so Gatekeeper never re-assesses what actually
  landed; verification ran on the pristine extracted copy. Helper also overwrites itself
  while executing (safe only via inode semantics). Identity/path preserved (Dock-safe).

### [P2] F8 — Nested helpers signed without hardened runtime or timestamps; BUILDING.md misdocuments `--deep`
- Status: Observed (dist inspection: helpers `flags=0x0`, `--timestamp=none`); notarization-rejection risk Inferred
- Source: `codesign-app-bundle.sh:14-24` vs Apple notary requirements; `BUILDING.md:133`
  claims `--deep` while the script deliberately avoids it (comment at `:43-49`).

### [P2] F9 — `GrokCLIService.run` has no timeout or cancellation
- Status: Observed
- Source: `GrokCLIService.swift:424-440` (continuation resumed only by terminationHandler).
  A hung `grok` wedges: the 24 h `UpdateScheduler` loop permanently, any Settings pane
  refresh, and launch session-title restore (`ContentView.swift:781`). Output drain is
  correct (no pipe deadlock here).

### [P2] F10 — `GitService` reads pipes only after termination → deadlock over ~64 KB
- Status: Observed
- Source: `GitService.swift:60-67`; `git diff HEAD -- <file>` (`:273-274`) on a large diff
  blocks the child on write, the handler never fires, PreviewPane hangs silently. Also
  `gh` via `/usr/bin/env` inherits GUI PATH — PR creation likely fails when launched from
  Finder (Inferred).

### [P2] F11 — Browser runtime: no teardown, no status timeout, stale-config launch
- Status: Observed
- Source: `AgentBrowserService.swift:229-236` drops the external Chromium `Process`
  handle (survives disable and app quit; pipes discarded); `runResult` (`:368-402`) has
  no timeout (hung `agent-browser doctor` suspends the Settings task forever);
  `ChatStore.swift:465-469` still registers the browser MCP after a failed auto-start
  (tools then fail against a dead endpoint — an error-surface choice, not a spin loop).
  Historical 9222 retry-loop failure mode: **structurally absent** (bounded 20×250 ms probe).

### [P2] F12 — Quit-time shutdown is fire-and-forget
- Status: Observed; orphan window Inferred (mitigated by stdin EOF)
- Source: `ContentView.swift:1403-1410` Task races `applicationWillTerminate`;
  `GrokProcess.cleanupProcess` sleeps 100 ms before `terminate()` (`GrokProcess.swift:496-499`),
  frequently losing the race. Practical cleanup relies on grok exiting on stdin EOF.

### [P2] F13 — Main-thread blocking work in hot paths
- Status: Observed
- Sites: `AppUpdater` verification runs `ditto`/`codesign`/`spctl` with `waitUntilExit()`
  on the MainActor (`AppUpdater.swift:198-204, 325-337` — the "Verifying…" spinner cannot
  animate); Models pane `reload()`/`persist()` do synchronous disk+Keychain on MainActor
  (`SettingsView.swift` pane logic); ChatView status pills stat the filesystem and read
  `.git/HEAD` **per render** (`ChatView.swift:1296-1302, 1371-1372, 832/1737-1739`);
  `PermissionCard` launches `Process`/`NSAppleScript` inline (`ChatView.swift:2023-2052, 1936-1955`);
  `DiffUtils.applyUnifiedDiff` waits on `/usr/bin/patch` (`ChatStore.swift:1715-1731`).

### [P2] F14 — Provider validation task hygiene
- Status: Observed
- Source: `SettingsView.swift` `validateProvider` — single-scalar `fetchingProviderID`
  (provider B's spinner cleared by A's completion), out-of-order catalog overwrite on
  rapid refetch, removed provider resurrected in `fetchedModels` by an in-flight task
  (`removeProvider` clears state but the Task lands after).

### [P2] F15 — CLI-pane action safety and staleness
- Status: Observed
- (a) Plugins/Marketplace/MCP Install/Uninstall/Enable buttons are not disabled while
  `isLoading` — rapid taps stack concurrent CLI mutations (`SettingsView.swift:1127-1131,
  1215-1229, 1292-1301, 1579-1582, 4555-4559, 4693-4702`). (b) Keep-alive panes run
  one-shot `.task`s — after a workspace switch, Skills/Hooks/Agents show the old
  workspace's data until a manual Refresh. No timers/polling in hidden panes (good).

### [P2] F16 — Opening the Models tab can write `~/.grok/config.toml`
- Status: Observed
- Source: Models pane `.task { reload() }` → credential-projection/migration side effects
  (`SettingsView.swift` reload path). Write goes through the repository (safe), but a
  read-only visit performing writes violates least surprise; should be
  migration-needed-only.

### [P2] F17 — `session/prompt` has no timeout
- Status: Observed
- Source: `GrokProcess.swift:527-531`; a wedged grok leaves `isStreaming` forever (30 s
  watchdog covers connection only; manual Stop is the recovery).

### [P3] F18 — `grokbuild-desktop` skill ships dead
- Status: Observed — bundled (`Package.swift:34`, present in dist/installed Resources),
  zero runtime lookups/installs anywhere in Swift source. 1 KB of weight, nonzero
  ownership confusion. `ARCHITECTURE.md:625` ("copied at build, not auto-installed")
  documents the limbo without a consumer.

### [P3] F19 — Documentation drift (7 instances)
- `ARCHITECTURE.md:64` repo root named `grok-deck2/`; `ARCHITECTURE.md:868` "three skill
  folders" (there are four); `BUILDING.md:317-322` SPM table omits
  `GrokBuildComputerUseCore`; `BUILDING.md:133` `--deep` claim (see F8);
  `scripts/README.md:28` dmg filename; `Makefile` `dmg` "auto-notarizes if set" comment —
  `NOTARY_PROFILE ?= AC_PASSWORD` makes the unsigned branch unreachable (`Makefile:8,115`);
  `AGENTS.md:37` references environment-specific Orca tooling.

### [P3] F20 — Updater small leaks/races
- Per-download `URLSession(.ephemeral)` never invalidated (`AppUpdater.swift:143`);
  `reset()` during download can be overwritten to `.failed`; `cleanupOldDownloads`
  matches by name-contains; overlap prevention is UI-gating only.

### [P3] F21 — Minor seams
- `GrokConfigRepository.read()` still maps read failure to `""` (load-side);
  `AcpEventStream` `.unbounded` buffering; `GrokSessionTranscriptImporter.grokHomeDirectory`
  mutable static; `SubagentRoleStore` prompt `.md` files written with default umask
  (non-secret); `AppVersion` `#filePath` dev fallback; `addMCPServer` splits target on
  spaces (space-containing paths inexpressible).

### [P3] F23 — Provider-editor text fields need an unstick click (live observation, 2026-07-31 PM)
- Status: Observed (installed app, Computer Use pass)
- While a text field in the Add New Provider editor holds keyboard focus, a single
  pointer click on a different text field does not move focus — typed text keeps landing
  in the old field. Reproduced three times across id/Name/Base URL/API key fields on the
  installed slice build; keyboard Tab traversal works correctly (id → name → URL → auth
  picker → API key). Conflicts with the matrix's "single click" standard for editor
  fields; likely interacts with the in-progress warm-glass focus styling. Candidate for
  slice 7 (Settings interaction fixes).

### [P3] F22 — Interaction polish
- ⌘, handler overwrites the remembered Settings tab (`ContentView.swift:1352-1355`);
  any programmatic workspace change kicks the user out of Settings (`:1018-1025`);
  composer controls ~22 pt (below the 32 pt standard applied to chrome buttons); mode/
  agent/tasks/memory pills lack `accessibilityLabel` (help-text only); sidebar "Show more"
  is tap-gesture-only (no key activation); chat-level auth banner string-sniffs failure
  text while typed statuses exist at the provider layer.

## 10. What this audit did *not* do

No cache/data deletion, no billable provider calls, no `~/.grok/config.toml` mutation,
no app install, no commits/staging, no Keychain reads. Live-app interaction acceptance
for this run's UI-adjacent changes (new badges, keyless enablement) is pending the
install authorization gate — tracked in `FABLE_5_IMPLEMENTATION_PLAN.md`.
