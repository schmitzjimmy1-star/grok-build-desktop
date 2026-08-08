# Codex parity — Slice 7/8 worklist (2026-08-07)

Baseline: clean merged `main` at `ef7570c0` (PR #8), installed and ship-verified.
Every item below is evidence-backed from the Slice 0–6 acceptance passes; nothing
here is speculative. Slice 7 owns visual metrics, responsive behavior, and
accessibility; Slice 8 owns the full installed acceptance matrix and decision.

## Accessibility defects observed during acceptance (Slice 7)

1. **Session Dashboard sheet is opaque to assistive tech.** Its rows never
   appeared in the AX walker, `entire contents` enumeration found no buttons,
   and synthesized clicks/keyboard Tab focus could not select a row (Slice 2
   acceptance note). Real pointer clicks work. The sheet needs real AX exposure
   (row buttons with identifiers/labels) and keyboard operability.
2. **`.menuStyle(.button)` menus don't open from AXPress or synthesized
   clicks.** The model and mode menus required the `AXShowMenu` action; the
   `.borderlessButton` add menu opened normally (Slice 4 note). Verify both
   AXPress and AXShowMenu work on all composer menubuttons.
3. **Sidebar session rows were absent from the captured AX tree** in every
   Slice 0–2 snapshot (projects, agents, connections rows appeared; nested
   session rows did not). The nested project→chat hierarchy must be first-class
   for VoiceOver and the keyboard.
4. **Focus order** (sidebar → header → transcript actions → composer →
   inspector/review) has never been verified end-to-end; the plan's Slice 7
   keyboard pass is still owed, including Escape closing only the topmost
   transient surface and ⌘, preserving the task.

## Responsive gaps (Slice 7)

5. **No responsive thresholds exist.** At the 1100×720 minimum the sidebar
   stays fixed-width and nothing collapses (fixture
   `06-narrow-window-1100x720.png`, `17-slice4-composer-narrow.png`). Required
   order: hide inspector first, collapse sidebar next, never compress the
   transcript below its readable minimum.
6. **Inspector overlap.** As a top-trailing overlay the inspector covers wide
   transcript content (fixture `10-slice2-inspector-overlay.png`). Acceptable
   per the overlay contract, but Slice 7 should confirm the compact width and
   consider a reading-column-aware offset at wide sizes.

## Visual metrics vs. photographs (Slice 7)

7. **Light mode is unproven.** `AppDelegate` forces dark appearance at launch
   and every fixture is dark; the Settings appearance controls exist but the
   parity ladder (surfaces, borders, selected fills) has not been tuned or
   captured in light mode.
8. **Quiet-row metrics.** Sidebar row height/indent/selected fill and section
   label weight have not been measured against the photographs; the empty-state
   Ask/Build/Review pills still await their side-by-side judgment (keep only if
   they don't disturb the hierarchy).
9. **Icon-only controls audit** — every icon-only control needs label, hint,
   value, and 36-pt hit target verification (most have them; the audit hasn't
   been run as a sweep).

## Product gaps recorded during Slices 0–6 (Slice 8 or later authorization)

10. **Review pane scope model.** Codex has Unstaged/Staged/Commit/Branch/Last
    turn scopes; `PreviewPane` has one implicit unstaged-project scope. The
    inline card's Review defaults to it; a proven last-turn scope needs pane
    work plus turn attribution.
11. **No safe Undo.** The changed-files card omits Undo deliberately; a real
    revert operation (per-file checkout via `GitService`) would have to be
    built and gated before any Undo control may appear.
12. **Bell routes to the Session Dashboard**, not a dedicated activity view
    (Slice 2 note). Codex's bell opens Activity; decide whether the dashboard
    is that surface or a dedicated view is owed.
13. **Live running-subagent row** was never photographed installed (worker
    settled too fast in the Slice 5 probe); Slice 8's bounded fixture turn
    should capture it, plus the recovery-required inspector state live.
14. **Changed-files count freshness.** The count refreshes only at
    select/turn boundaries (observed live in Slice 2/3); fine per contract,
    but the card/header could disclose staleness after external edits.
15. **Cross-provider web/tool history replay** remains a known backend
    limitation (documented 2026-08-02): start a new session before switching
    provider/model after a web or tool turn.

## Slice 8 acceptance flows still owed

The eleven flows in the plan's Slice 8 section, unchanged — notably: exact
transcript identity across project/task switching, one bounded local fixture
turn with streaming/thinking/tools/subagents/failure observation, attach file +
MCP with requested-vs-used distinction, Stop with local stopped outcome,
quit/relaunch restore, and light/dark + narrow/wide + reduced-motion +
keyboard-only sweeps — ending in an ACCEPT / ACCEPT WITH FOLLOW-UP / REJECT
decision.

## Slice 7 progress log (updated 2026-08-07 evening)

**Fixed and ship-verified this pass (630 tests / 0 failures each):**
- Responsive policy live: inspector hides first at narrow widths and returns
  with preserved state when the sidebar collapses (fixtures 21–23).
- Menubutton AXPress repaired: mode/model menus moved off `.menuStyle(.button)`;
  plain AXPress now opens them (installed-verified).
- Session Dashboard AX exposure repaired: the sheet's `LazyVStack` was deferring
  row materialization; a bounded `VStack` now exposes every
  `grok-session-dashboard-row-<uuid>` (129 elements found) and `AXPress`
  selects a row — previously impossible for assistive tech. Verified installed
  with a real row selection and session switch, then state restored.
- Sidebar session rows carry `grok-sidebar-session-row` identifiers.

**Still off / needs enhancement (carried forward):**
- Light mode remains unproven; every fixture is dark (item 7).
- Icon-only control audit sweep and the end-to-end keyboard/VoiceOver focus
  pass are still owed (items 4, 9).
- During acceptance, GrokBuild lost frontmost mid-automation once, and the
  dashboard row's accessibility *description* did not surface through System
  Events (identifier matching worked; AXDescription matching did not) — the
  spoken label path deserves a VoiceOver spot-check.
- Items 5 (sidebar auto-collapse unreachable at the 1100-pt minimum), 6
  (inspector overlay offset at wide sizes), and 10–15 (Review scopes, safe
  Undo, bell destination, live-worker photograph, count freshness, provider
  history replay) are unchanged.

16. **OpenRouter models and tool use (owner-flagged, 2026-08-07).** Jimmy has
    flagged OpenRouter-routed models' tool use as unresolved: the 2026-08-02
    receipts record that cross-provider web/tool history replay fails
    (`Invalid params` after switching providers mid-session), and OpenRouter
    routes have never had an installed tool-use acceptance (browser, terminal,
    write tools) equivalent to the native-Grok passes. Needed: a bounded
    per-route tool-use probe matrix (DeepSeek/Gemini/GPT-4.1-mini via
    OpenRouter), explicit handling or disclosure when a route cannot replay
    provider-specific tool history, and a documented recommendation per route.
    Requires separate billable authorization.

## Slice 8 progress log (2026-08-07 night, published build 957810ac)

**Flows verified installed:** relaunch into the existing active task with exact
transcript identity (flow 1/10 — full transcript, continuity banner, honest
`Grok 4.5 · Last live` receipt after quit/relaunch); project/task switching
(flow 2, re-driven); flows 4–9's streaming/thinking/subagent/settlement,
inline card, inspector states, and requested-vs-used MCP behavior stand on the
Slice 3/5 installed probes recorded in the matrix.

**New findings this pass (need addressing):**
- **Saved-layout scale: 129 sessions restore at launch**, with a visible
  progress overlay and correctly disabled UI — but launch-to-interactive is
  tens of seconds. Needs a pruning/archiving policy for stale tabs (most are
  old acceptance sessions) or a faster deferred restore.
- **Frontmost instability during automation:** GrokBuild repeatedly lost
  frontmost to other apps mid-flow, which also affects real long launches;
  full-screen captures grabbed the wrong app twice. Harmless to users but
  worth a launch-activation review alongside the restore-latency fix.

**Slice 8 flows still owed before a decision:** one bounded fixture turn with
a deliberate tool failure observed live; attach-file + MCP requested-vs-used
in the same turn; Stop with the local stopped outcome; light/dark,
reduced-motion, and keyboard-only sweeps; and the OpenRouter tool-use matrix
(item 16, separate billable authorization). Decision stands at
**ACCEPT WITH FOLLOW-UP (provisional)** — the target hierarchy is visibly met
and no identity/review/receipt regressions have appeared, with the listed
follow-ups bounded and tracked.

## Billable probe session findings (2026-08-07 late night, build 957810ac)

**Verified working (2 authorized Grok 4.5 turns):**
- Deliberate tool failure stays failed everywhere: transcript trace shows
  "Execute `/usr/bin/false` — Failed"; the inspector shows the orange
  "1 failed tool — Command exited with status 1" line; exact marker returned;
  the inline card correctly refused attribution (fixtures 27–28).
- Long-answer flow: a 400-line answer streamed, followed to the bottom, and
  settled cleanly with the card unattributed (fixture 29). Stop could not be
  exercised because the single-chunk reveal finished before the Stop press —
  Stop stands on its 2026-07-31 live receipt; a tool-backed long turn is the
  way to re-exercise it.

**Defects found (need addressing, roughly in priority order):**
- **P1 — Custom model tables are GONE from `~/.grok/config.toml`** (1,057
  bytes; only `[models]` default remains — no `[models.<id>]` entries). The
  composer's model menu therefore shows only "Grok 4.5": the OpenRouter
  routes (DeepSeek/Gemini/GPT-4.1-mini) and OpenAI/Kimi entries cannot be
  selected anywhere, in GrokBuild or the TUI. Keychain still holds provider
  credentials (openai metadata confirmed; no secret touched), so the repair is
  re-adding models via Settings → Models catalog flows. Until then, item 16's
  OpenRouter tool-use matrix is blocked. Root cause unknown — the config was
  2,308 bytes on 2026-08-02; something (CLI update/migration/TUI action)
  rewrote it outside GrokBuild's slices. Consider a GrokBuild startup check
  that detects Keychain-credentialed providers with zero config model tables
  and offers restoration.
- **P1 — Launch restore at 130 tabs takes 60–80s** with the progress counter
  stuck at "0 of N" the whole time (batch update only at the end), all input
  disabled, and typed text silently discarded (no draft preservation).
  Needs: pruning/archiving policy for stale tabs, honest incremental
  progress, and draft capture during restore.
- **P1 — Quit at scale is degraded**: scripted AppleEvent quit timed out twice
  (-1712) with app + two browser-mcp + two ComputerUseMCP children alive;
  ⌘Q then took ~20 s to full exit (accepted envelope was 0.32 s). Likely the
  130-tab flush plus multi-child teardown.
- **P2 — Two warm-started process pairs observed** (two browser-mcp + two
  ComputerUseMCP children) after two New chats — each empty New chat spawns
  and keeps a full helper set; combined with layout growth, every acceptance
  session adds a permanent empty tab and transient helper load.
- **P2 — Frontmost loss during long launches** (recorded earlier) compounds
  the restore-latency defect.

**Slice 8 decision remains ACCEPT WITH FOLLOW-UP (provisional)** for the
parity frontend itself; the P1 defects above are runtime/scale issues outside
the slice scope but block full Slice 8 closure and item 16.
