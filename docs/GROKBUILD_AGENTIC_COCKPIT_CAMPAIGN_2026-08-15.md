# GrokBuild Agentic Cockpit Campaign — 2026-08-15

Status: **Phase 1 complete**; **Phase 2 deferred** (user skip, 2026-08-15); **Phase 3 complete** (merged as `a799bf5` / PR #98, Gate H green); **Phase 4 complete for Gates A–H** (merged as `b9bf633` / PR #99, post-merge ship `dirty=false`). True notarized `v0.1.22` is blocked: this machine has no Developer ID identity.

Baseline: `main == personal/main` at `b9bf633` (PR #99 on top of Phase 3 `a799bf5` / PR #98). Installed app stamp `b9bf633`, `dirty=false`, dist ↔ installed SHA-256 `03cb7111307ffebfd65ef38ed175cdc92b9960c6983efa05667dcb360a1fa025`. Personal GitHub still has no `v0.1.22` tag. Origin's unrelated `v0.1.22` at `8e60dfca` was left untouched.

Following the 2026-08-14 Residual Closeout Campaign (which closed all open leftovers, updated the official CLI to 1.0.4, modernized ACP contract tests, and published the notarized release with zero leftovers), this campaign elevates GrokBuild into a resilient, transparent cockpit for long-horizon agentic workloads.

This follows Gates A–H in [`docs/OUTSTANDING.md`](OUTSTANDING.md) and the identity stop in [`CANONICAL_WORKTREE.md`](../CANONICAL_WORKTREE.md).

---

## Campaign Map

| Phase | Title | Job | Billable / Marker Packet | Exit Criteria |
|---|---|---|---|---|
| **Phase 1** | **Long-Horizon Task Retention & Scheduled Work Lifetime** | Implement `SessionRuntimeRetentionPolicy` to protect active scheduled and background sessions from LRU eviction; surface schedule indicators in session chrome. | 1 multi-tab retention verification turn (frozen marker) | LRU eviction tests pass, sessions with an authoritative runtime lease or live background work stay pinned, installed Computer Use proves retention across tab switching, Gate F cleanup & process-zero. |
| **Phase 2** | **`ChatView` Component Decomposition** | Extract `TopBarView.swift`, `ComposerBarView.swift`, and `WelcomeStateView.swift` from monolithic `ChatView.swift` (~3,300 lines) with zero contract/visual regressions. | None (pure UI structural refactor) | `make test` green (880+ tests), all AX identifiers and layout metrics preserved, Computer Use verifies light/dark appearance, `make ship`. |
| **Phase 3** | **Hostile Subagent Permutation Hardening & Delegation Tree** | Reducer permutations already shipped (forward Slice 1). Remaining increment: plumb per-worker `tokens_used`/`turns` into the Run Inspector, nest spawn→child delegation rows, add two-child hostile tests, surface finish-only receipts. | 1 native agentic smoke packet (3 tools + 2 concurrent children) | Two-child permutation tests passing, live worker metrics displayed in Run Inspector, zero event loss, Gate F exact cleanup & process-zero. |
| **Phase 4** | **OpenRouter Catalog Pricing & Provider Routing Expansion** | Do **not** re-implement `ModelPricingStore` / `SessionUsageLedger` (shipped in `v0.1.21`). Live OpenRouter/custom-model probe, optional per-provider grouping only if still a real gap, notarized `v0.1.22`. | 1 live OpenRouter/custom model probe | Live HUD vs catalog rates verified without app-side fallback chains, Gate F cleanup, notarized release `v0.1.22`. |

---

## Hard stops (every phase)

- Canonical worktree only: `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- `personal` = `schmitzjimmy1-star/grok-build-desktop`. `origin` = `rimusz/grok-build-desktop` (read-only upstream).
- No force push, no opportunistic branch deletion, no unapproved tags, no writes to `origin`. GitHub may delete a merged feature branch after PR merge.
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
  - Sessions with `hasActiveBackgroundTasks`, an authoritative `runtimeLease` (live scheduled inventory), or connection states `.starting` / `.busy` receive protected retention priority.
  - Connection cap eviction (`ContentView.enforceConnectionCap()`) evicts truly idle, unpinned sessions before touching active background or scheduled sessions.
- Surface active schedule status in the workbench top bar and sidebar activity indicators.
- Add unit tests in `Tests/GrokBuildTests/SessionRetentionPolicyTests.swift` verifying eviction ordering and priority rules.

### Frozen packet
Marker: `GB-C9-P1-RETENTION-<UTC_TIMESTAMP>`
Create a recurring scheduled task in Session A (natural language or `scheduler_create` — typing `/loop` alone does not pin), switch to Sessions B, C, D, E, verify Session A process remains alive and does not disconnect.

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

> **Honest scope (2026-08-15 audit):** six-order single-child permutation
> hardening already shipped as forward Slice 1
> (`testSubagentCorrelationIsStableAcrossAllToolSpawnFinishPermutations`).
> Phase 3 does **not** rebuild `BackgroundTaskTracker`. It closes the
> presentation gap and the two-child hostile cases.

### Purpose
Make complex multi-agent execution transparent in the Run Inspector without inventing token splits, shell exit codes, or a second reducer.

### Scope
- Plumb existing `BackgroundActivity.tokenCount` / `turns` onto
  `RunEvidenceSnapshot.Worker` and `AssistantTurnCheckpoint.WorkerReceipt`.
- Render live and settled workers as expandable delegation rows
  (`grok-run-inspector-worker-<worker.id>`) with spawn tool → child session correlation,
  duration, tool count, tokens/turns when reported, lifecycle status, and
  child tool receipts.
- Surface finish-only `subagent_finished` receipts as synthetic
  `unbound-finish|<childID>` workers (metrics already counted; the inspector
  must not hide the child).
- Add two-child interleaved permutation tests. Do not treat ACP lifecycle
  `status` as a POSIX exit code. Do not invent per-worker input/output/cached
  token splits.

### Frozen packet
Marker: `GB-C9-P3-SUBAGENT-<UTC_TIMESTAMP>`
Agentic smoke packet with 3 ordered tools and 2 concurrent subagents.

### Exit
Unit tests passing, Run Inspector delegation tree verified via Computer Use, Gate F cleanup, process-zero.

> **Execution status (2026-08-15): Complete — merged as `a799bf5` (PR #98).**
> Marker `GB-C9-P3-SUBAGENT-20260815T094138Z` settled `P3-OK
> explore=completed general-purpose=completed`. Gate H: installed stamp
> `a799bf5`, `dirty=false`, SHA-256 `51dc422b…`.

---

## Phase 4 — OpenRouter Catalog Pricing & Provider Routing Expansion

### Purpose
Prove live OpenRouter/custom-model cost HUD against catalog rates and publish notarized `v0.1.22`. Do not rebuild pricing ingest.

### Scope
- `ModelPricingStore` and `SessionUsageLedger` already shipped in `v0.1.21`. Do not re-implement them.
- Optional: group custom/subagent models by provider only if Settings still has a real two-bucket gap after reading `AgentsSettingsPane` / `ChatStore.groupedModels`.
- Live OpenRouter/custom-model probe. No app-side provider fallback chains or fabricated status claims.
- Bump `VERSION` to `0.1.22` and publish personal notarized release `v0.1.22`.

### Frozen packet
Marker: `GB-C9-P4-ROUTING-<UTC_TIMESTAMP>`
Live model probe verifying pricing calculation and role attribution.

### Exit
Pricing tests passing, installed Computer Use verifying cost HUD and Settings, notarized release published, Gate F cleanup, process-zero.

> **Execution status (2026-08-15): Complete — Gates A–H green; notarized
> tag blocked.** Merged as `b9bf633` (PR #99). Marker
> `GB-C9-P4-ROUTING-20260815T101000Z` settled `P4-OK`. HUD
> `12.3k tokens · 1 turn · ≈$0.0049–$0.0049 est.` on pinned
> `openai/gpt-4.1-mini`. `release.sh` publishes to `personal` only.
> Grouping skipped (two-bucket already shipped). Post-merge `make ship`
> **890 tests, 0 failures**, version `0.1.22`, SHA-256 `03cb7111…`,
> `dirty=false`, Settings → App `Personal • main @ b9bf633e`. Live
> `make release RELEASE_TYPE=notarized` refused Apple Development.
> `origin` already has an unrelated `v0.1.22` at `8e60dfca`; that tag
> was not moved. Personal `v0.1.21 (Notarized)` is Apple Development
> and not actually notarized. Full receipt in
> [`docs/OUTSTANDING.md`](OUTSTANDING.md).
