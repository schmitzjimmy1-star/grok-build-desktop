# GrokBuild Agentic Cockpit Campaign — 2026-08-15

Status: **Phase 1 complete** (merged as `2b7f377`, PR #96; Gates A–H green, billable retention proof passed); Phases 2–4 planned.

Baseline: campaign spec merged as `b58b973` (PR #95) on top of `4613bdee0ad27c296482fd66cce816afef375357` (PR #94), installed app `b58b973` with `dirty=false` and notarized release `v0.1.21` active. Phase 1 implementation merged as `2b7f377` (PR #96); installed app re-shipped at `2b7f377` with `dirty=false`.

Following the 2026-08-14 Residual Closeout Campaign (which closed all open leftovers, updated the official CLI to 1.0.4, modernized ACP contract tests, and published the notarized release with zero leftovers), this campaign elevates GrokBuild into a resilient, transparent cockpit for long-horizon agentic workloads.

This follows Gates A–H in [`docs/OUTSTANDING.md`](OUTSTANDING.md) and the identity stop in [`CANONICAL_WORKTREE.md`](../CANONICAL_WORKTREE.md).

---

## Campaign Map

| Phase | Title | Job | Billable / Marker Packet | Exit Criteria |
|---|---|---|---|---|
| **Phase 1** | **Long-Horizon Task Retention & Scheduled Work Lifetime** | Implement `SessionRuntimeRetentionPolicy` to protect active `/loop` and background sessions from LRU eviction; surface schedule indicators in session chrome. | 1 multi-tab retention verification turn (frozen marker) | LRU eviction tests pass, `/loop` sessions pinned, installed Computer Use proves retention across tab switching, Gate F cleanup & process-zero. |
| **Phase 2** | **`ChatView` Component Decomposition** | Extract `TopBarView.swift`, `ComposerBarView.swift`, and `WelcomeStateView.swift` from monolithic `ChatView.swift` (~3,300 lines) with zero contract/visual regressions. | None (pure UI structural refactor) | `make test` green (867+ tests), all AX identifiers and layout metrics preserved, Computer Use verifies light/dark appearance, `make ship`. |
| **Phase 3** | **Hostile Subagent Permutation Hardening & Delegation Tree** | Harden `BackgroundTaskTracker` against hostile out-of-order events (early finishes, dropped updates); enhance Run Inspector subagent delegation tree with duration and token/turn metrics. | 1 native agentic smoke packet (3 echoes + 2 concurrent children) | Permutation test suite passing, live worker metrics displayed in Run Inspector, zero event loss, Gate F exact cleanup & process-zero. |
| **Phase 4** | **OpenRouter Catalog Pricing & Provider Routing Expansion** | Integrate OpenRouter model catalog pricing metadata into `SessionUsageLedger` for accurate live token→$ estimation; enhance subagent role-to-model presets with provider grouping. | 1 live OpenRouter/custom model probe | Live price correlation verified without app-side fallback chains, strict provider truth maintained, Gate F cleanup, notarized release `v0.1.22`. |

---

## Hard stops (every phase)

- Canonical worktree only: `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- `personal` = `schmitzjimmy1-star/grok-build-desktop`. `origin` = `rimusz/grok-build-desktop` (read-only upstream).
- No force push, no branch deletion, no unapproved tags, no writes to `origin`.
- No app-side ACP, MCP runtime, provider fallback chains, or background daemons.
- Never delete user conversations or unclassified sessions during cleanup.
- Only exact, ledgered test-thread IDs may be deleted (Gate F).
- Computer Use preference: Cursor `user-grokbuild-computer-use` MCP, then `agent-desktop`, then Orca. Installed proof is `/Applications/GrokBuild.app` only.

---

## Publication & PR Workflow

Each phase must be executed on a dedicated feature branch, verified locally via `make test` and `make ship` with installed Computer Use, pushed to `personal`, reviewed via PR on GitHub, verified CI-green, merged to `main`, and closed with a post-merge `make ship` so `installed stamp == HEAD` (`dirty=false`).

---

## Phase 1 — Long-Horizon Task Retention & Scheduled Work Lifetime

> **Execution status (2026-08-15): Complete — merged as `2b7f377` (PR #96).**
> `SessionRuntimeRetentionPolicy` now protects active background work
> (`SessionRuntimeProtectionReason.activeBackgroundTask` fed by
> `ChatStore.hasActiveBackgroundTasks`) in addition to the existing starting /
> busy / active-schedule reasons, and active schedule status is surfaced in the
> top-bar Tasks pill (`grok-tasks-status`) and the sidebar session row
> (`grok-sidebar-session-schedule`). `make test` is green at **880 tests, 0
> failures**; new coverage lives in
> `Tests/GrokBuildTests/SessionRetentionPolicyTests.swift` plus store tests in
> `RunEvidenceSnapshotTests.swift`. The implementation was committed as `2cef894`
> and merged via PR #96 as `2b7f377`. The authorized billable multi-tab retention
> turn (frozen marker `GB-C9-P1-RETENTION-20260815T083223Z`) proved a live
> scheduled Session A survives LRU eviction under five additional ordinary
> sessions past the connection cap, with the orange schedule pill and sidebar
> badge rendering and then reverting after the schedule was deleted. Post-merge
> `make ship` re-installed `/Applications/GrokBuild.app` at stamp `2b7f377`
> (`dirty=false`, Team `DD2GCQJVB4`, deep/strict valid, no quarantine, dist ↔
> installed SHA-256
> `f4b82c09012883b3621216291ffaedf0468ba3efc6e43f01c0540f209f8d9b4c`); marker
> sessions were cleaned up with zero leftovers and process-zero confirmed. Full
> receipt in [`docs/OUTSTANDING.md`](OUTSTANDING.md).

### Purpose
Ensure long-running agentic tasks (such as recurring `/loop` commands, background shells, and multi-turn workflows) are not silently terminated by the 4-tab LRU connection cap when a user opens other tabs.

### Scope
- Formalize `SessionRuntimeRetentionPolicy`:
  - Sessions with active background activities (`isWorking`, `hasActiveBackgroundTasks`, or `scheduledTasks.containsActive`) receive protected retention priority.
  - Connection cap eviction (`ContentView.enforceConnectionCap()`) evicts truly idle, unpinned sessions before touching active background or scheduled sessions.
- Surface active schedule status in the workbench top bar and sidebar activity indicators.
- Add unit tests in `Tests/GrokBuildTests/SessionRetentionPolicyTests.swift` verifying eviction ordering and priority rules.

### Frozen packet
Marker: `GB-C9-P1-RETENTION-<UTC_TIMESTAMP>`
Run background `/loop` or multi-turn task in Session A, switch to Sessions B, C, D, E, verify Session A process remains alive and does not disconnect.

### Exit
`make test` passing, installed Computer Use proof of retention across 5+ open tabs, Gate F cleanup, process-zero.

---

## Phase 2 — `ChatView` Component Decomposition

### Purpose
Decompose the last major god-object in the presentation layer (`ChatView.swift` at ~3,300 lines) into clean, focused, testable SwiftUI components, following the successful pattern from `SettingsView`.

### Scope
- Extract `Views/Chat/TopBarView.swift`:
  - Sidebar toggle, session title, header review toggle, run inspector toggle, settings button.
- Extract `Views/Chat/ComposerBarView.swift`:
  - `grok-message-composer` text field, `grok-composer-add-menu`, model & effort selector, voice button, send/stop button.
- Extract `Views/Chat/WelcomeStateView.swift`:
  - New chat welcome cards (Ask, Build, Review intents), project directory guidance.
- Preserve exact AX identifiers (`grok-message-composer`, `grok-send`, `grok-run-inspector-toggle`, etc.) and layout constraints.

### Exit
`make test` passing with zero test regressions, `make ship`, installed Computer Use snapshot confirming identical accessibility tree and visual appearance.

---

## Phase 3 — Hostile Subagent Permutation Hardening & Delegation Tree

### Purpose
Harden subagent tracking against hostile event ordering and enhance the Run Inspector delegation tree to make complex multi-agent execution transparent.

### Scope
- Extend `BackgroundTaskTracker`:
  - Add tests for out-of-order event arrivals (`subagent_finished` before `subagent_spawned`, late-binding descriptions, missing terminal receipts).
  - Ensure state reducer is deterministic and never leaks orphaned state.
- Enhance Run Inspector delegation tree:
  - Display per-subagent execution duration, token usage breakdown, and terminal exit status.
  - Correlate parent tool calls with child agent execution blocks.

### Frozen packet
Marker: `GB-C9-P3-SUBAGENT-<UTC_TIMESTAMP>`
Agentic smoke packet with 3 ordered tools and 2 concurrent subagents.

### Exit
Unit tests passing, Run Inspector delegation tree verified via Computer Use, Gate F cleanup, process-zero.

---

## Phase 4 — OpenRouter Catalog Pricing & Provider Routing Expansion

### Purpose
Enhance live cost and usage transparency by correlating OpenRouter's live catalog pricing into `SessionUsageLedger` and refining subagent role routing presets.

### Scope
- Ingest OpenRouter model pricing metadata into `ModelPricingStore` and `SessionUsageLedger` for accurate live token→$ estimates.
- Group custom models by provider in subagent role selectors.
- Maintain strict boundaries: no app-side provider fallback chains or fabricated status claims.
- Bump `VERSION` to `0.1.22` and publish personal notarized release `v0.1.22`.

### Frozen packet
Marker: `GB-C9-P4-ROUTING-<UTC_TIMESTAMP>`
Live model probe verifying pricing calculation and role attribution.

### Exit
Pricing tests passing, installed Computer Use verifying cost HUD and Settings, notarized release published, Gate F cleanup, process-zero.
