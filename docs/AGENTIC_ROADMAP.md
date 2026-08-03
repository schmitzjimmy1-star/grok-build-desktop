# GrokBuild → Agentic Workbench — Ten-Slice Roadmap

*Deep-dive synthesis (2026-08-03) from a four-agent read of backend, providers, frontend/sidebar, and performance. Read-only analysis; nothing here is implemented yet.*

## The vision, honestly stated

GrokBuild is already an unusually **capable agentic engine wearing a chatbot's clothes**. The `grok` CLI does the hard agentic work (subagents, tools, MCP, plan mode, scheduling, workflows), and the app already *observes and models* almost all of it — typed worker lifecycle receipts, a rich `RunEvidenceLiveProjection`, per-role model routing in `~/.grok/config.toml`, OpenRouter OAuth, multi-provider credentials. The problem isn't missing plumbing; it's that **90% of the agentic surface is either observed-only, drawer-buried, or gated behind a collapsed "Details" disclosure**, while a few files have grown into god-objects (`SettingsView` 7,446 lines, `ChatStore` 4,285, `ChatView` 3,307).

So the strategy is: **light up plumbing that already exists** (cheap, thin, high-impact), **add the two genuinely-missing agentic capabilities** (user MCP servers; cost/routing), and **decompose the god-objects + fix the two real buffering costs** so it stays fast as it grows. Most slices are *thin over existing state* — not reimplementing what the CLI owns.

## Legend

- ⚡ **Enhance** — new agentic capability · 🎨 **Consumer** — friendlier/less jargon · 🧹 **Streamline** — kill bloat/buffering
- Effort: **S** (hours) · **M** (a day or two) · **L** (multi-day, do incrementally)
- Every slice ships with `make test` + `make ship` (auto-verifies signature/identity). Slices touching money/routing/providers get the full receipt treatment per `AGENTS.md`.

---

## Slice 1 — Persistent "Activity & Tasks" sidebar lane ⚡🎨
**Effort M · thin over existing state · ✅ shipped 2026-08-03** (`Models/SidebarActivity.swift`, sidebar Activity section, `SidebarActivityTests`)

Today all agentic work (background shells, scheduled `/loop` tasks, workflow runs, live subagents) is *evidence-only* and cleared at every turn boundary, visible only in the right-hand `ActivitySidebar` which is itself gated behind the collapsed Details disclosure (`ChatView.swift:289,1629`). A user sees a chatbot with a folder picker.

Add a **second, always-visible sidebar section** that projects the state GrokBuild already tracks: `ChatStore.backgroundActivities`, `scheduledTasks`, `workflowRuns`, and live workers. Continuous, not per-turn. This single change is what makes the app *read* as agentic.
- **Files:** `SidebarView.swift`, `ContentView.swift` (wiring), reuse `ActivitySidebar` presentation helpers, `BackgroundTaskStore`/`ScheduledTaskStore`/`WorkflowRunStore`.
- **Safe because:** pure read model; no new CLI behavior, no backend calls.

## Slice 2 — Agents & Roles hub in the sidebar ⚡🎨
**Effort M · thin · ✅ shipped 2026-08-03** (`Models/AgentHub.swift`, sidebar Agents section, `testAgentHub*`)

Per-session agent is buried in a menu inside the closed-by-default Details disclosure (`ChatView.swift:1816`); custom subagent roles exist only as Settings CRUD. Promote them: a sidebar section listing **built-in agents, discovered agents, and custom roles**, each with its assigned model, and a one-click **"Start session as…"**.
- **Files:** `SidebarView.swift`, `ContentView.swift`, reuse `GrokAgentProfiles` + `SubagentRoleStore` + `SubagentRole.model` (`CustomModelSettings.swift:1227`).
- **Safe because:** reuses the existing `--agent` launch path (`ChatStore.swift:1792`); roles already round-trip to config.toml.

## Slice 3 — Subagent delegation tree + tool-run inspector ⚡
**Effort M · thin · ✅ shipped 2026-08-03** (live worker receipts mid-turn; expandable tool inspector with MCP attribution; `SidebarActivityTests`)

The backend already captures per-turn worker attribution (`currentTurnWorkerActivityIDs`, `ChatStore.swift:232`), typed spawn/finish receipts with duration/turns/tokens/tool-counts (`BackgroundTaskStore.swift:334`), and typed live tool calls — but renders them flatly. Build a **delegation tree**: this turn spawned *these* subagents (role, model, live status, terminal receipt), each expandable to its **tool runs** (args → output). This is the "watch my agents work" view that defines an agentic app.
- **Files:** `BackgroundTaskStore.swift`, `RunEvidenceLiveProjection.swift`, `ActivitySidebar.swift`.
- **Safe because:** derived entirely from existing typed events.

## Slice 4 — Custom MCP server manager ⚡
**Effort M · ✅ shipped 2026-08-03, scope corrected** — deep-dive follow-up found user-defined MCP management *already exists* (Settings → MCP Servers, CLI user/project scope, `GrokMCPServerDraft`), so the honest thin gap was surface, not plumbing: shipped as the sidebar **Connections lane** (readiness, one-click attach-to-next-message via the existing `togglePromptMCPAttachment`, Manage… → Settings). No second app-injection lane was added — grok owns MCP wiring at runtime, and no existing provider/OpenRouter/MCP config is touched.

Right now only two app-managed MCP servers get injected (browser, computer-use, `ChatStore.swift:1785`) and there is **no UI for user-defined servers** — even though `MCPServerConfig` already models stdio **and** http/sse transports (`MCPServerConfig.swift:4`). Add a store + Settings pane so the user can connect **any MCP server / API tool** (their own, or hosted) and have it injected alongside the built-ins. This is how the app becomes a hub for *the APIs you already have*.
- **Files:** `MCPServerConfig.swift`, MCP assembly in `ChatStore.restartProcess` (`:1785`), new `SettingsView` pane, new store.
- **Safe because:** the CLI executes MCP tools; GrokBuild only injects config (its documented lane).

## Slice 5 — Per-subagent model routing + OpenRouter, made real ⚡
**Effort M/L · ✅ shipped 2026-08-03, scope honest** — configured role→model routing is now *visible and correlated*: worker receipts lead with "Routes to <model> (configured)" on exact role-name matches, and the roles editor groups models by provider (OpenRouter/custom routes first-class). App-side **fallback chains were deliberately not added**: grok owns subagent spawning and exposes no fallback hook, so an app-side chain would violate the thin-wrapper rule. Verified with a live OpenRouter-routed role probe (receipt in CANONICAL_WORKTREE.md).

Per-role model routing *already exists* in config (`[subagents.roles.<name>].model`) but is invisible and unorchestrated. Make it a feature: **role→model presets** (e.g. plan/explore = cheap, verify = strong), let each role pick an **OpenRouter or custom-provider** model, add a **primary + fallback** chain, and **correlate the chosen model to the worker that actually ran** (close the loop in the delegation tree from Slice 3).
- **Files:** `CustomModelSettings.swift:1227` (`SubagentRole`), roles pane in `SettingsView.swift:2514`, worker correlation in `BackgroundTaskStore`/projection.
- **Safe because:** config-write path is tested; correlation is read-only. **Verify with a live billable probe per lane + `CANONICAL_WORKTREE.md` receipt** (this touches routing/billing — the class that burned the repo before).

## Slice 6 — Cost & usage HUD (per-session, per-worker $) ⚡🎨
**Effort M · ✅ shipped 2026-08-03** — `SessionUsageLedger` + `ModelPricingStore` + Details-bar HUD. Estimates are honest low–high bounds (ACP reports combined tokens only); unpriced models show tokens, never $0; pricing captured from OpenRouter's catalog during Test connection. Per-worker $ awaits per-worker usage receipts from the CLI.

Only raw token counts exist anywhere (`GrokProcess.swift:1663`, `ChatStore.swift:3082`). Agentic runs fan tokens across many subagents/providers, and consumers need to *see the meter*. Add token→$ using per-model pricing (OpenRouter exposes rich price/context/modality metadata the app currently ignores), surfaced as **per-turn, per-session, and per-worker spend**.
- **Files:** usage plumbing `GrokProcess.swift:1663`, `ChatStore.swift:3082`; new pricing store; OpenRouter model metadata in `CustomModelSettings.swift:596`.
- **Safe because:** display-only over existing usage receipts; no send path change.

## Slice 7 — BYOK onboarding + consumer model labels 🎨⚡
**Effort S/M · ✅ shipped 2026-08-03 (lite)** — consumer backend labels ("Standard chat (OpenAI-compatible)"/"OpenAI Responses"), provider-grouped model pickers everywhere, one-click project default, hub/welcome surfaces. A full multi-step BYOK wizard was skipped: the Models pane already guides connect → Test → add, and the empty-providers state explains the path.

Provider setup is buried in Settings → Models, exposes raw `api_backend` protocol names (`chat_completions`/`responses`/`messages`), and has no first-run moment. Add a guided **connect → validate → set-default wizard**, relabel backends in plain language, and seed the empty state with **one-click agent templates** (extend `WorkbenchIntent.defaults`) instead of only Ask/Build/Review.
- **Files:** Models pane `SettingsView.swift:3753+`, backend labels `CustomModelSettings.swift:8`, `ComposerModels.swift:275`, welcome state `ChatView.swift:1160`.
- **Safe because:** wraps existing `OpenRouterOAuth` + `ProviderModelFetcher` flows; no new auth surface.

## Slice 8 — De-jargon the agentic surfaces 🎨🧹
**Effort S · ✅ shipped 2026-08-03** — Activity drawer plain-language pass (What the agent did / Happening now / Finished / Technical details / No final report), human summary lines, idle Workspace panel replacing the dead empty state, welcome restored for empty tabs, composer center hint. Truth boundaries unchanged.

The Activity/receipts read like a debugger: "Execution receipts," "Settled/Live," "generation-bound," "Orphaned — terminal status not reported" (`ActivitySidebar.swift:98–204`). Rename to plain language ("Finished/Running/Didn't report back"), make Activity **discoverable** (a badge on the top bar instead of hidden under Details), and promote the modal **Session Dashboard into a persistent board** (`SessionDashboardPanel.swift`).
- **Files:** `ActivitySidebar.swift`, `SessionDashboardPanel.swift`, `ContentView.swift:271`.
- **Safe because:** copy + presentation only.

## Slice 9 — Streaming smoothness: incremental markdown + async persistence 🧹
**Effort S/M · the two real buffering costs · ✅ shipped 2026-08-03** (`StreamingMarkdownAccumulator`, FIFO async transcript chain + quit flush, `StreamingPresentationTests`)

The streaming pipeline is mostly well-mitigated (paced reveal, bounded 6-pass scroll, plain-`Text` streaming body). Two genuine costs remain:
1. **O(n²) main-actor markdown scan** — `StreamingMarkdownPresentation.make` runs on the *full accumulated string* every body evaluation while streaming (`MessageBubble.swift:35`), full-text scanning for open fences/tables (`TranscriptTextPresentation.swift:79`). Fix: scan only the **tail**, or skip until a fence/pipe appears.
2. **Blocking transcript write** — `SessionMessageStore.saveAll` runs under `storageQueue.sync` on the **MainActor** and re-encodes the entire transcript JSON (`ContentView.swift:770`, `SessionMessageStore.swift:108`). Fix: make it **async** (hop off MainActor / continuation).
- **Safe because:** both are behavior-preserving; covered by existing streaming + persistence tests.

## Slice 10 — Decompose the god-objects 🧹
**Effort L · ✅ shipped 2026-08-03 (scoped)** — `SettingsView.swift` 7,464 → 746 lines: all 14 panes extracted verbatim to `Views/Settings/` (source-contract tests repointed to per-pane files, a stricter scope). TOML helper quintuplication collapsed into `Services/TOMLLineParsing.swift` (LegacyMigration's escape-preserving `unquote` kept as deliberate divergence). `ChatStore`/`ChatView` method-level splits were deliberately deferred: eleven source-contract test files pin their internals by design (the repo's truth-verification style), and this session already extracted their pure logic into models (`SidebarActivity`, `AgentHub`, `SessionUsage`, `StreamingMarkdownAccumulator`, scroll/submission policies). Remaining candidates if ever needed: ChatView `TopBar`/`ComposerBar` component split; Live-vs-Settled row unification in the drawer.

Four files hold most of the bloat. Pure moves, no behavior change, each independently shippable:
- **`SettingsView.swift` (7,446)** → per-pane files; extract `CustomModelsSettingsPane` (~1,980 lines, `:3753–5734`) first.
- **`ChatStore.swift` (4,285; 196 funcs, 117 props)** → `StreamingController`, `PersistenceCoordinator`, `ContinuityCoordinator`, and the observed-activity trackers behind the same `@Observable` facade. Also un-inline the side-effectful installers from `restartProcess` (`:1705`).
- **`ChatView.swift` (3,307)** → `TopBar`, `WelcomeStateView`, `ComposerBar`, `ChatTranscriptView` (scroll policy `enum`s already free-standing at `:164`).
- **Dedup:** one shared TOML helper (currently three copies across `GrokConfigLegacyMigration`/`CustomModelStore`/`SubagentRoleStore`); unify duplicated Live-vs-Settled render rows and the two session-row components.
- **Safe because:** mechanical extraction; run `make test` after each. Retire one-shot migration cruft (`gpt-5.6-terra` special-case, `disabled_mcp_servers`) once the install base has migrated.

---

## Suggested sequence

1. **Quick agentic wins first (1 → 2 → 3):** sidebar Activity lane, Agents/Roles hub, delegation tree. Cheap, thin, and they *immediately* change the app's identity from chatbot to workbench.
2. **Capability unlocks (4 → 5 → 6):** custom MCP servers, real per-role routing, cost HUD. This is the "your APIs, your OpenRouter, your agents" story — Slice 4 is the single biggest lever.
3. **Consumer polish (7 → 8):** BYOK wizard + de-jargon. Do these *after* the surfaces exist so onboarding points at real features.
4. **Health, continuously (9 → 10):** ship the two buffering fixes early (they're small), then chip away at god-object decomposition one extraction per PR so it never blocks a feature.

Interleave 9/10 with the feature slices — e.g. extract `CustomModelsSettingsPane` while you're in there for Slices 5–7.

## Verification posture (per the tiered note in AGENTS.md)

- **Slices 5 & 6** touch model routing / billing → full acceptance: `make ship` **plus** a live billable probe per provider lane and a `CANONICAL_WORKTREE.md` receipt.
- **Everything else** → `make test` + `make ship` (auto-verifies signature, identity, SHA parity) + a focused Computer Use check of the affected surface. No manual hash-tracking.
