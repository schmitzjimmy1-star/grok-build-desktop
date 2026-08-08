# OUTSTANDING — the one canonical list

> Everything open or unresolved for GrokBuild lives here, and only here.
> Historical receipts stay in `docs/CODEX_PARITY_SLICE_7_8_WORKLIST_2026-08-07.md`
> and `docs/UI_ACCEPTANCE_MATRIX.md`; when an item below closes, move its receipt
> there and delete the row. Created 2026-08-08 at owner request.

## Active direction — agentic workbench, not chatbot (2026-08-08)

Owner directive under review: the app must read as an agentic platform
(Codex-like), not a chatbot. Findings F-1..F-5 and proposed slices W-1..W-6
live in `docs/AGENTIC_WORKBENCH_REVIEW_2026-08-08.md`; W-1 (chrome budget
trim, incl. sidebar size) is the owner's tentative first pick pending
confirmation. No slice is implemented until the owner chooses.

## Open defects

| # | Item | Severity | State |
|---|---|---|---|
| O-1 | **External Chromium auto-start can still take frontmost at first-intent warm start.** The 2026-08-08 warm-start move eliminated launch-time and New-chat-time browser spawns (the original frontmost thief), but when browser tools are enabled with auto-start, the first keystroke in a fresh tab can still launch Chromium, which takes focus while the user is typing. Candidate fix: launch args that suppress the startup window, or defer browser start to first browser-tool use. | P3 (was P2, largely mitigated) | Open |
| O-2 | **Second-launch activation is unconditional.** The single-instance flock dance posts `showMainWindow` and the live instance activates with `ignoringOtherApps: true` — intended for real double-clicks, but it means any stray re-launch (updater race, `make run`) yanks focus. Acceptable by design; recorded so nobody re-diagnoses it. | By design | Documented |
| O-3 | **"Jump to latest" pill is not addressable by title through System Events** (pressed only by coordinates during acceptance). Raw AX may expose it; spot-check and, if truly unlabeled, give it an identifier + label like the other transcript controls. | P3, AX polish | Open |
| O-4 | **System Events cannot read AXDescription on SwiftUI elements** (identifier matching works; description matching does not). Affects scripted automation only; raw AX API surfaces names correctly. Known macOS/SwiftUI quirk, kept for awareness. | Environment quirk | Documented |

## Manual passes owed (need a human or a system-settings change)

| # | Item | State |
|---|---|---|
| M-1 | **Reduced-motion OS-level sweep.** Code honors `accessibilityReduceMotion` (chrome, Settings transitions, rich messages); flipping the system toggle for a live sweep needs Jimmy or explicit authorization to change system settings. | Owed |

## Deferred features (explicitly decided, separately authorized when wanted)

| # | Item | Decision record |
|---|---|---|
| D-1 | **Review pane scope model** (Unstaged/Staged/Commit/Branch/Last-turn). Single implicit unstaged-project scope is the accepted contract. | Worklist "gaps 10–15", disposition 10 |
| D-2 | **Safe Undo** on the changed-files card. No Undo control until a gated per-file revert exists in `GitService`. | Worklist disposition 11 |

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
