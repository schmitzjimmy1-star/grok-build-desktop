# Agentic workbench review — 2026-08-08

Owner directive: "this is not supposed to be a chatbot, more like an agentic
platform like Codex." This review measures the app as it stands (owner
screenshot 2026-08-08 00:32, fixtures 38–40, the two supplied target
photographs `00a`/`00b`) against that bar, names what makes it read as a
chatbot, and proposes bounded slices. Nothing here is implemented yet except
where marked; the owner picks.

## What reads as "chatbot" today

**F-1 — The canvas is a conversation, not a workspace.** The screenshot's
window is ~70% empty dark canvas around one exchange. The window opens into
*a chat that happens to know about a project* rather than *a project with
work in flight*: nothing on the canvas says branch, changed files, running
work, or recent tasks — all of that hides in chips, sheets, and the
inspector. Codex lands you in a task-centric surface.

**F-2 — User prompts are speech bubbles.** Right-aligned rounded bubbles in
a centered 760-pt column are the chat metaphor. In the photographs, the
user's ask reads as the task statement — full-width, part of the work
record, not a message someone sent.

**F-3 — Chrome budget is generous for sparse content.**
- Left sidebar: 220–280 pt (ideal 244) carrying four rail rows + two
  projects. The Codex photograph's rail is ~200 pt and far denser (pinned,
  projects with nested tasks, recents).
- Right inspector: 290-pt overlay, now with the ledger always expanded
  (2026-08-08 change): the 2×2 stat-tile grid spends ~180 pt of height
  saying "0, 0/0, 0, 15.8K" for a trivial turn, and Files in review lists
  the same facts as the header Review chip in a third place.

**F-4 — "Do anything" + mic is assistant framing.** Codex's composer is
also bottom-anchored but framed as task input with explicit access/mode
controls; the copy matters.

**F-5 — The plan is not the spine.** During a run, plan/steps/tools live
behind the trace disclosure and inspector; the transcript stays a linear
chat. The photographs put subagents/tasks as first-class summaries.

## What is already workbench-grade (do not lose)

Honest receipts end to end (model stamps, continuity, requested-vs-used,
attributed-only inline cards); navigation-only sidebar; header Review chip +
real diff pane; Session dashboard; first-intent warm start; 2-second
restores; 0.3-second quits; per-turn dynamic identity labels (2026-08-08).

## Proposed slices (owner picks; each independently shippable)

**W-1 — Chrome budget trim (small, immediate).**
Left sidebar 200–240 pt (ideal 216); rail rows tightened to ~28 pt.
Inspector 290 → 260 pt; when workers/tools/artifacts are all zero, collapse
the stat grid to one line ("Turn completed · 15.8K tokens"); cap Files in
review at 5 rows + "Open Review". Ledger stays in view per the 2026-08-08
decision, just denser.

**W-2 — De-bubble the task statement.** User prompts render full-width with
a quiet leading rule and "You" caption — a task record, not a bubble.
Assistant turns keep their identity headers. Pure presentation; transcript
data unchanged.

**W-3 — Workspace landing instead of void.** The empty/new-tab canvas
becomes a compact workspace overview: current branch + changed-file count,
the three intent cards (already target-blessed), and the last few tasks for
this project with one-click resume. Kills the dead-void first impression
(F-1) using only data the app already holds.

**W-4 — Task context strip.** A one-line strip pinned above the transcript:
project · branch · changed files · model receipt. Always tells you where
you are; replaces nothing, duplicates no control.

**W-5 — Plan as spine during runs.** Elevate the existing live plan/steps
projection into the transcript flow while a run is active (the data already
exists for the inspector); settled turns keep today's compact trace.

**W-6 — Dock the inspector when wide.** At ≥1,500 pt content width, the
overlay becomes a docked third column (respects the existing responsive
order: it still hides first when narrow).

Suggested order: W-1 now (answers "reduce the sidebar"), then W-3 + W-4
(biggest chatbot-feel killers), then W-2, W-5, W-6.

## Status

- **W-1 and W-2 shipped 2026-08-08** by owner instruction: sidebar
  200–240 pt with 28-pt rail rows, inspector 240–300 pt (ideal 260), the
  all-zero stat grid collapsed to one line, Files in review capped at 5,
  and user prompts rendered as full-width task statements with a leading
  rule and "You" caption.
- **W-3 and W-4 shipped 2026-08-08**, then the empty-canvas chrome was walked
  back: New chat keeps heading, project name, Ask/Build/Review (with on-canvas
  detail), and the composer. The task-contract strip is hidden on empty drafts
  and idle restored transcripts; Resume / Start new / Browse is the one
  restored-task decision row. Branch, recents, and Browse stay in the sidebar
  and header More menu.
- **W-5 and W-6 shipped 2026-08-08**, closing the slice list. W-5: while a
  run is active, the live plan projection renders in the transcript flow as
  a `Plan · m of n done` spine on the streaming turn — independent of the
  trace disclosure, gone at settlement (the snapshot keeps the authoritative
  copy in the inspector); settled turns keep the compact trace. W-6: at
  ≥1,500-pt chat-area width the open inspector mounts as a docked 260-pt
  third column instead of the top-trailing overlay — same panel and state,
  no overlap — while the hide-first responsive order below 900 pt is
  unchanged.
- PR #16 merged 2026-08-08.
