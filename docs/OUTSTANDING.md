# OUTSTANDING — the one canonical list

> Everything open or unresolved for GrokBuild lives here, and only here.
> Historical receipts stay in `docs/CODEX_PARITY_SLICE_7_8_WORKLIST_2026-08-07.md`
> and `docs/UI_ACCEPTANCE_MATRIX.md`; when an item below closes, move its receipt
> there and delete the row. Created 2026-08-08 at owner request.

## Status: all clear (2026-08-08)

Nothing is open. The agentic-workbench direction (findings F-1..F-5, slices
W-1..W-6 in `docs/AGENTIC_WORKBENCH_REVIEW_2026-08-08.md`) shipped in full,
and every defect, manual pass, and deferred feature this file tracked is
closed — O-1..O-7, M-1, D-1, D-2. Receipts live in the worklist ledger's
"OUTSTANDING close-out receipts (2026-08-08)" section.

New work lands here as new rows; an empty list is a statement, not a
retirement of the file.

## Open defects

None.

## Documented behaviors (not defects — kept so nobody re-diagnoses them)

| # | Item | Where documented |
|---|---|---|
| B-1 | **Second-launch activation is unconditional** (was O-2). The single-instance flock dance posts `showMainWindow` and the live instance activates with `ignoringOtherApps: true` — intended for real double-clicks, but any stray re-launch (updater race, `make run`) yanks focus. Acceptable by design. | This row |
| B-2 | **System Events cannot read AXDescription on SwiftUI elements** (was O-4). Identifier matching works; description matching does not. Affects scripted automation only; raw AX API surfaces names correctly. Known macOS/SwiftUI quirk — acceptance scripts must match identifiers. | This row |

## Standing behavioral caveats (documented contracts, not defects)

| # | Item | Where documented |
|---|---|---|
| C-1 | **Cross-provider web/tool history replay** cannot be replayed across providers; start a new session per provider after web/tool turns. | `TOOL_USE_AND_MULTI_TURN_CONTRACT.md` |
| C-2 | **Compound multi-MCP first-turn readiness** on fast OpenRouter routes (Gemini 2.5 Flash, GPT-4.1 Mini): one same-session retry may be needed while MCP servers connect. Single-tool turns passed first-try 2026-08-07. | `TOOL_USE_AND_MULTI_TURN_CONTRACT.md` |
| C-3 | **Changed-files counts refresh at selection/turn boundaries**, not on external edits — disclosed in the header Review chip's tooltip and accessibility hint. | ARCHITECTURE.md, worklist disposition 14 |
| C-4 | **Old transcripts show the neutral "Build agent" turn label.** The per-turn model stamp (2026-08-08) applies to turns settled after it shipped; earlier turns carry no receipt and never get a guessed name. | ARCHITECTURE.md |
