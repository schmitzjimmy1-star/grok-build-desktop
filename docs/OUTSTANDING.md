# OUTSTANDING — the one canonical list

> Everything open or unresolved for GrokBuild lives here, and only here.
> Historical receipts stay in `docs/CODEX_PARITY_SLICE_7_8_WORKLIST_2026-08-07.md`
> and `docs/UI_ACCEPTANCE_MATRIX.md`; when an item below closes, move its receipt
> there and delete the row. Created 2026-08-08 at owner request.

## Active direction — agentic workbench, not chatbot (2026-08-08)

Owner directive: the app must read as an agentic platform (Codex-like),
not a chatbot. Findings F-1..F-5 and slices W-1..W-6 live in
`docs/AGENTIC_WORKBENCH_REVIEW_2026-08-08.md`. **W-1, W-2, W-3 (workspace
landing), and W-4 (task context strip) shipped 2026-08-08**, along with the
owner-requested live tool visibility (auto-expanded live trace; worker
counts only when nonzero) and a twelve-item straggler sweep (Preview→Review
naming, task-framed composer, dynamic a11y announcements, dead-code
removal, tools-count receipt, scope-aware empty states, Stop-turn naming,
send/stop/rail identifiers, card→Last-turn scope). Remaining: W-5 (plan as
spine) and W-6 (docked inspector), plus the deferred instrumentation items
below.

## Open defects

| # | Item | Severity | State |
|---|---|---|---|
| O-1 | **External Chromium auto-start frontmost steal — FIXED 2026-08-08.** `--no-startup-window` added to the CDP launch arguments: the auto-started browser opens no window (and steals no focus) until a page is actually driven. | Closed | Fixed |
| O-2 | **Second-launch activation is unconditional.** The single-instance flock dance posts `showMainWindow` and the live instance activates with `ignoringOtherApps: true` — intended for real double-clicks, but it means any stray re-launch (updater race, `make run`) yanks focus. Acceptable by design; recorded so nobody re-diagnoses it. | By design | Documented |
| O-3 | **"Jump to latest" pill — CLOSED 2026-08-08, already instrumented.** The pill carries `grok-jump-to-latest`, a label, value, and hint; the acceptance script had matched titles instead of identifiers (the O-4 quirk). Scripts must match the identifier. | Closed | No change needed |
| O-4 | **System Events cannot read AXDescription on SwiftUI elements** (identifier matching works; description matching does not). Affects scripted automation only; raw AX API surfaces names correctly. Known macOS/SwiftUI quirk, kept for awareness. | Environment quirk | Documented |
| O-5 | **Commit/PR popovers under-instrumented** (no focus on the title field, no identifiers/help on the six action rows, both primaries claim ⌘↩). From the 2026-08-08 straggler sweep. | P3 | Open |
| O-6 | **Session-migration banner is permanent** — no dismiss, no action, no receipt naming which sessions went read-only. From the straggler sweep. | P3 | Open |
| O-7 | **SessionsBrowserPanel and GitCheckoutSheet carry zero accessibility identifiers.** From the straggler sweep. | P3 | Open |

## Manual passes owed

| # | Item | State |
|---|---|---|
| M-1 | **Reduced motion — CLOSED 2026-08-08, code-enforced.** Every animating view file consults `accessibilityReduceMotion` (four ungated sites fixed: slash autocomplete scroll, sidebar filter toggle, models-pane scroll and templates toggle) and a repo-wide tripwire test fails the suite if a new `withAnimation` ships ungated. The optional OS-toggle glance remains available to the owner but is no longer tracked. | Closed |

## Deferred features

| # | Item | Decision record |
|---|---|---|
| D-1 | **Review scopes — SHIPPED 2026-08-08.** The Review pane carries a scope picker: Working tree (default, the pre-existing everything-vs-HEAD view), Staged, Last commit, Branch (merge-base vs default base; empty when no base resolves), and Last turn (working tree filtered to the run's attributed paths). The header chip and inline-card attribution always read the full working tree; only the default scope may auto-close the pane. | Closed; `GitReviewScopeTests` |
| D-2 | **Safe per-file revert — SHIPPED 2026-08-08.** `GitService.revertPath` (live status check → `restore --source=HEAD --staged --worktree` for tracked, `clean -f` for untracked) surfaces as a working-tree-scope-only control in the Review pane behind an explicit confirmation dialog. The inline card stays deliberately Undo-free per the quiet-thread direction. | Closed; `GitReviewScopeTests` |

## Standing behavioral caveats (documented contracts, not defects)

| # | Item | Where documented |
|---|---|---|
| C-1 | **Cross-provider web/tool history replay** cannot be replayed across providers; start a new session per provider after web/tool turns. | `TOOL_USE_AND_MULTI_TURN_CONTRACT.md` |
| C-2 | **Compound multi-MCP first-turn readiness** on fast OpenRouter routes (Gemini 2.5 Flash, GPT-4.1 Mini): one same-session retry may be needed while MCP servers connect. Single-tool turns passed first-try 2026-08-07. | `TOOL_USE_AND_MULTI_TURN_CONTRACT.md` |
| C-3 | **Changed-files counts refresh at selection/turn boundaries**, not on external edits — now disclosed in the header Review chip's tooltip and accessibility hint. | ARCHITECTURE.md, worklist disposition 14 |
| C-4 | **Old transcripts show the neutral "Build agent" turn label.** The per-turn model stamp (2026-08-08) applies to turns settled after it shipped; earlier turns carry no receipt and never get a guessed name. | ARCHITECTURE.md |

## Recently closed (pointer only — receipts live in the worklist ledger)

- Restore latency, quit latency/orphans, empty-tab pruning, draft capture (2026-08-07).
- Model-table restoration; OpenRouter route matrix; Slices 7/8 close-outs and
  ACCEPT WITH FOLLOW-UP decision (2026-08-07).
- Add Model filter-leak P2; "system" display-name P3; live-worker photograph;
  VoiceOver spot-check removed by owner (2026-08-08).
- Per-New-chat helper spawn weight P2 (warm start moved to first intent) and
  the launch-time frontmost loss it caused; dynamic per-turn model labels;
  run-details ledger open by default; Computer Use note removed from the
  inspector; unattributed review cards out of the thread (2026-08-08).
