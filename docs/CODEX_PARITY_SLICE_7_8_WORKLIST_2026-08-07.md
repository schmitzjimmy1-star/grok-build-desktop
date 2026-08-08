# Codex parity — Slice 7/8 worklist (2026-08-07)

> **The live open-items list moved to `docs/OUTSTANDING.md` (2026-08-08).**
> This file remains the historical ledger of receipts; do not add new open
> items here.

Baseline: clean merged `main` at `ef7570c0` (PR #8), installed and ship-verified.
Every item below is evidence-backed from the Slice 0–6 acceptance passes; nothing
here is speculative. Slice 7 owns visual metrics, responsive behavior, and
accessibility; Slice 8 owns the full installed acceptance matrix and decision.

## Slice 7 items 1–9 — ALL CLOSED (2026-08-07/08)

The original accessibility, responsive, and visual-metrics sections (items
1–9) are retired from this list: every item is closed with receipts in the
progress logs and close-out sections below. Summary: dashboard AX exposure
(1), menubutton AXPress (2), and sidebar session-row identifiers (3) were
repaired in the first Slice 7 pass; the keyboard/Escape/⌘, pass (4), the
wired sidebar responsive threshold (5), the inspector-overlay decision (6),
light mode (7), the quiet-row/pills judgment (8, below), and the icon-only
audit (9) closed in the Slice 7 close-out passes.

**Item 8 closure — quiet-row metrics and pills judgment (2026-08-07 night).**
The two supplied target photographs are now preserved in the baseline
directory (`00a-supplied-target-photo-1.jpg`, `00b-supplied-target-photo-2.jpg`
— Slice 0's copy step had silently never happened; /tmp still held them).
Measured against them (installed AX bounds):
- Rail rows (New chat/Sessions/Plugins/Security): single-line, 32-pt height /
  34-pt pitch — matches the photographs' compact rail. ✓
- Section label ("Projects"): 19-pt caption-weight muted header — matches. ✓
- Selected fill: subtle lighter rounded rectangle on both project and nested
  session rows — matches. ✓
- Nested session rows: indented single-line under their project — matches. ✓
- **Accepted deviation:** GrokBuild project rows are two-line (name + path
  subtitle, 46 pt) where the photographs show single-line (~30 pt) project
  rows. The path subtitle is deliberate disambiguation for same-named folders
  and does not disturb the hierarchy; recorded as kept.
- **Pills judgment: KEEP.** The photographs' own target bullet list names
  "Ask, Build, and Review launch cards" as part of the target design; the
  intent cards live only in the empty transcript canvas (fixture 24) and
  never in the sidebar, so the hierarchy is undisturbed.

## Product gaps 10–15 — final dispositions (2026-08-07/08)

10. **Review pane scope model — DEFERRED by decision.** The single implicit
    unstaged-project scope is the accepted contract for this parity effort;
    Unstaged/Staged/Commit/Branch/Last-turn scopes remain a separately
    authorized future feature (pane work plus turn attribution).
11. **Safe Undo — DEFERRED by decision.** The changed-files card stays
    Undo-free deliberately until a gated per-file revert operation is built
    through `GitService`. No Undo control may appear before that exists.
12. **Bell destination — CLOSED by decision.** The Session activity dashboard
    IS the bell's activity surface (consistent with the Slice 1 contract:
    "Activity is not a rail row; the bell owns it"). No dedicated view owed.
13. **Live-worker photograph — CARRIED (bounded).** Workers settle too fast in
    bounded fixture turns to photograph reliably; the recovery-required
    inspector state HAS now been exercised live (the stopped session's
    refused send + "can't be resumed — Send starts a fresh thread" banner +
    Continue-as-New ledger, fixture 34 flow). Only the running-subagent-row
    photograph itself remains, to be grabbed opportunistically during any
    future long worker turn.
14. **Count freshness — CLOSED.** The header review toggle now discloses the
    refresh boundary (tooltip + accessibility hint: counts refresh at
    selection and turn boundaries, not on external edits), alongside the
    card's existing "Repository-wide changes" footer.
15. **Cross-provider history replay — CLOSED as documented limitation.** The
    backend cannot replay provider-specific tool history across providers;
    the continuity system already refuses dishonest resumes and the contract
    doc + matrix carry the new-session-per-provider rule. Re-confirmed by the
    Slice 8 matrix running each OpenRouter route in a fresh session.

## Backlog burn-down (2026-08-08 early morning)

- **Multiprompt subagent thread verified installed** (three back-and-forth
  turns, one session, Grok 4.5): turn 1 spawned two parallel workers (exact
  `WORKER-A-DONE` output + correct PNG count 37); turn 2 spawned a 60-second
  worker and the **live running-subagent state is finally photographed** —
  Activity LIVE "Happening now — not final", "Subagents › 1 running", live
  status line "Using tools · 1 active worker · Get task output …" (fixture
  38, closing item 13's carried photograph); turn 3's no-tool recall listed
  all three prior results exactly, in order (fixture 39). Bottom-follow
  honesty rode along: a settled turn while scrolled away produced the
  "Jump to latest (2 new)" pill instead of yanking the viewport.
- **Add Model filter-leak P2 FIXED**: `modelFilterText` now resets on editor
  mount (`.onAppear`), not only on provider change (which never fires at
  mount). Verified installed by poisoning one editor's filter, cancelling,
  and opening the Moonshot editor: the picker shows all 12 models (was the
  stuck "0/12" with the filter field hidden below its 12-model visibility
  threshold).
- **"system" display-name P3 FIXED**: generic catalog `owned_by` values
  (`system`, `openai`, `openai-internal`, `organization-owner`) no longer
  auto-fill Display name; pinned by
  `testGenericCatalogOwnerLabelsExcludeRealLabNames` (637 tests / 0 failures).
- **VoiceOver spot-check removed from the list by owner decision.**
- Remaining open: per-New-chat helper spawn weight P2, frontmost-loss P2,
  manual reduced-motion sweep, and the deferred product features (Review
  scopes, safe Undo).

## Slice 8 acceptance flows — ALL COMPLETE

All eleven flows in the plan's Slice 8 section are verified with receipts in
the progress logs and the "Slice 8 close-out and decision" section below.
The decision is **ACCEPT WITH FOLLOW-UP (final)**; the only open work is the
bounded follow-up list recorded there plus the defect backlog below (Add
Model filter-leak P2, "system" display-name P3, per-New-chat helper weight
P2, frontmost-loss P2, manual reduced-motion sweep, and the opportunistic
live-worker photograph from item 13). The VoiceOver spot-check was removed
from the list by owner decision on 2026-08-07 night.

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

## Slice 7 close-out (2026-08-07 late night, 636 tests / 0 failures)

- **Light mode proven (item 7).** The adaptive `AppTheme` ladder (dynamic
  NSColor providers with real light values) was exercised installed:
  fixtures `30-slice7-light-wide.png` and `31-slice7-light-narrow-1100x720.png`
  show correct canvas/sidebar/surface separation, border strength, and text
  contrast with no dark-on-white artifacts; `32-slice7-dark-narrow-1100x720.png`
  is the dark pair. Appearance honors the Settings → App System/Light/Dark
  control (`GrokBuildAppearance`); nothing force-locks dark.
- **Sidebar responsive step wired (item 5).**
  `SidebarVisibility.shouldShow(availableContentWidth:)` now consults
  `ResponsiveLayoutPolicy.sidebarFits` with the 220-pt sidebar minimum, fed by
  root geometry observation. At the 1100-pt window minimum the collapse stays
  unreachable by construction (1100 − 220 ≥ 812); the wiring exists so any
  smaller future minimum sacrifices the sidebar before the transcript. Pinned
  by `testSidebarVisibilityWiresTheResponsiveThreshold`.
- **Icon-only audit swept (item 9).** Source-wide sweep found 13 genuinely
  icon-only controls missing explicit labels (sidebar filter/bell/new-project/
  help, review-pane close, banner dismissals, session delete, memory reveal,
  subagent edit/remove, MCP argument up/down/remove and env-entry remove,
  marketplace remove-source and plugin-actions menus, plugins refresh, both
  reveal-key toggles). All now carry explicit `accessibilityLabel` (+hints/
  values where state matters) and inset content shapes for ≥36-pt effective
  targets on the small chrome buttons. SF Symbol fallback names are no longer
  load-bearing; pinned by `testAuditedIconOnlyControlsCarryExplicitLabels`.
  The bell's spoken label is "Session activity" (the Slice 1 contract forbids
  the literal `Label("Activity"` substring in SidebarView).
- **Keyboard pass (item 4).** With full keyboard access, the Tab ring was
  walked installed: composer → composer controls (add/mode/model/mic) →
  sidebar (filter, bell, rail, project outline, help) → header (sidebar
  toggle, More actions, review, activity, settings) → transcript → composer —
  matching the declared sidebar → header → transcript → composer order as a
  cycle. Escape with the inspector open closed only the inspector (session,
  transcript, and selection intact — verified with before/after captures);
  ⌘, opened Settings and returned to the same task (verified live earlier in
  this session's Settings → Models work).
- **Inspector overlay (item 6).** Compact 290-pt width confirmed against the
  900-pt `inspectorMinimumChatWidth` gate (fixtures 21–23 + tonight's
  captures). No reading-column-aware offset added: at wide sizes the centered
  760-pt column leaves the trailing gutter to the overlay by geometry, and the
  Slice 2 overlay contract already accepts medium-width overlap. Decision
  recorded here so the "consider" item is closed, not silently dropped.
- Carried (not Slice 7 scope): items 10–15. (A VoiceOver spot-check of the
  System Events AXDescription quirk was carried here originally; the owner
  removed it from the list on 2026-08-07 night.)

## Slice 8 close-out and decision (2026-08-07 late night)

**Remaining flows, all verified installed (build off `29300bb8`):**

- **Stop with local stopped outcome (flow 9):** a `sleep 60` terminal turn was
  stopped mid-tool; the transcript kept the trace ("26s thought · 1 tool"),
  the inspector settled FINISHED with the local **Stopped** outcome, no
  completion was fabricated, and the receipt dropped honestly to
  "Grok 4.5 · Last live" (fixture 33).
- **Attach file + MCP requested-vs-used (flow 8):** one turn carried an
  attached file plus a requested `chrome-devtools` MCP connection. The
  scaffold's honesty rule is explicit in the sent prompt ("If no attached MCP
  tool is actually called, do not claim that an MCP was used"); the reply
  returned the exact marker from the file via one read tool, the MCP stayed
  requested-but-unused in Sources, and the inline card refused repository-wide
  attribution (fixture 34). Bonus receipts from the same flow: the stopped
  session's next send was correctly refused ("Grok is not ready yet"), the
  draft and both attachment chips survived, and the recovery ledger recorded
  "Continue as New" before the fresh thread ran.
- **OpenRouter tool-use matrix (item 16, owner-authorized):** all three
  restored routes passed a bounded terminal-tool probe first-try with exact
  marker output and matching live receipts (fixtures 35–37; matrix table
  updated in TOOL_USE_AND_MULTI_TURN_CONTRACT.md). Item 16 is closed;
  cross-provider history replay remains the standing documented limitation.
- **Sweeps (flow 11):** light/dark and narrow/wide stand on Slice 7's fixtures
  30–32; keyboard-only stands on the Slice 7 Tab-ring/Escape/⌘, pass; reduced
  motion is honored in code (`accessibilityReduceMotion` gates chrome,
  Settings transitions, and rich-message rendering) — the OS-toggle sweep
  would require changing a system accessibility setting and stays owed as a
  manual pass.
- **Final gates:** 636 tests / 0 failures; `make ship` PASS (clean stamp);
  loaded-case quit gate passed with 8 live grok/helper children → 0.86 s full
  exit → **zero orphans** → 1.18 s relaunch to interactive with transcript,
  selection, model intent, and layout restored.

**Decision: ACCEPT WITH FOLLOW-UP (final).** The target hierarchy is met, and
no identity, transcript, review, approval, receipt, or recovery regression
appeared in any Slice 7/8 pass. Exact bounded follow-ups: (1) manual
OS-level reduced-motion sweep; (2) Kimi K3 re-add once the Add Model
filter-leak P2 is fixed (done by owner 2026-08-07 night); (3) product gaps
items 10–15 (Review scopes, safe Undo, bell destination, live-worker
photograph, count freshness, provider history replay — all dispositioned
above); (4) P2s: per-New-chat helper spawn weight and frontmost loss during
long launches (both softened by the restore/quit repairs, neither closed).
The VoiceOver spot-check was removed from this list by owner decision.

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

## Model-table restoration receipt (2026-08-07 night)

**The lost-model-tables P1 is repaired.** All restoration was done through the
installed app's own Settings → Models flows (Test connection → Add model
catalog picks), never by hand-editing config.toml:

- Provider state on open: all three providers survived with Keychain-backed
  credentials (ChatGPT/OpenAI API key, Kimi/Moonshot API key, OpenRouter
  OAuth), each "Not tested" with Add model disabled; Models section read
  "0/28 custom models."
- Test connection receipts: OpenAI Connected — 124 models; Moonshot
  Connected — 12 models; OpenRouter OAuth Connected — 400 models. Keychain
  credentials all valid; no secret was displayed or touched.
- Re-added via catalog picks: `gpt-5.6-terra` (OpenAI Responses, 128K,
  display name corrected from auto-filled "system"), `gpt-5.6-luna` (OpenAI
  Responses, 200K, same correction), `deepseek/deepseek-v4-flash-0731`,
  `google/gemini-2.5-flash`, and `openai/gpt-4.1-mini` (all three OpenRouter,
  Standard chat, ids auto-derived to the exact pre-loss table keys).
- Verified: `~/.grok/config.toml` (mode 0600, 2,430 bytes) now carries all
  five `[model.*]` tables byte-equivalent to the 2026-08-05 backup where they
  existed there; the composer model menu lists all five under "Your models"
  alongside Grok 4.5. Item 16's OpenRouter tool-use matrix is unblocked
  (still needs its separate billable authorization).
- **Kimi K3 was intentionally skipped** (owner said move on): blocked by the
  new editor defect below. Moonshot provider itself is Connected, so the
  re-add is a one-minute job once the defect is fixed or a fresh editor
  cooperates. **Update 2026-08-07 night: Jimmy re-added kimi-k3 himself**
  (`[model.kimi-k3]` verified in config.toml — chat_completions, 128K,
  display name "moonshot"). All six models are restored; only the underlying
  filter-leak P2 remains open as a defect.

**New defects found during restoration:**

- **P2 — Add Model editor leaks catalog filter text across provider
  editors.** The filter field kept "gpt-5.6-luna" when opening Kimi's and
  OpenRouter's editors. With Moonshot's 12-model catalog the filter row is
  hidden below the visibility threshold, so the stale filter left the picker
  at "0/12" with no way to clear it in the UI — this is what blocked the
  kimi-k3 re-add. Fix: reset filter state per editor open (or always show the
  filter row).
- **P3 — Display name auto-fills the OpenAI catalog's "system" label** when
  picking gpt-5.6-terra/luna ("system — <id>" entries), which would render
  the composer entry as "system" unless manually corrected.
- **Automation/AX notes:** Settings-surface buttons expose no
  title/description/identifier through System Events (position-matched
  AXPress was required; the automator MCP's own AX snapshot sees the names) —
  same family as the Slice 7 AXDescription finding. Full-window capture also
  times out while a composer NSMenu is open.

## Restore-latency and quit P1 repair receipt (2026-08-07 late night)

Both remaining P1s are repaired on `agent/restore-quit-latency` (634 tests /
0 failures, `make ship` PASS, installed-verified):

- **Launch restore: 60–80 s → 2.32 s to interactive** (window at 0.72 s),
  measured installed with 111 restored tabs. Root cause was not data volume:
  the serial main-actor loop re-read and re-parsed `~/.grok/config.toml` 3–4×
  per tab and re-decoded the workspace-layout blob ~5× per tab. Fixes:
  mtime+size-stamped contents cache in `GrokConfigRepository.read()` (external
  TUI/CLI writes still invalidate), a decoded workspace-layout cache in
  `SessionLayoutStore`, and an in-memory `SessionNameStore` mirror.
- **Progress counter honest:** the rebuild loop now yields once per tab so the
  "X of N" counter and per-workspace status actually paint; at the new speed
  the overlay is visible only briefly.
- **Stale-empty pruning (owner-approved deletion):**
  `SessionRestorePolicy.pruneDecision` drops records with no restorable local
  transcript, not selected anywhere, no pending recovery intent, and untouched
  for 24 h — a warm-start backend binding alone no longer immortalizes an
  empty New chat. First launch pruned 19 husks (130 → 111 records); most
  remaining acceptance sessions hold real transcripts and are protected.
  Deleting those contentful old threads stays a manual/dashboard action.
- **Draft capture during restore:** only sidebar/settings/review disable
  during restore; the composer stays typeable with sends gated, and
  `selectSession` carries a placeholder-store draft across the `.id()`
  remount that previously swallowed it.
- **Quit: scripted AppleEvent quit 0.31 s full exit, zero orphaned helpers**
  (was two -1712 timeouts and a ~20 s ⌘Q). `applicationShouldTerminate` no
  longer downgrades a re-entrant quit to `.terminateNow` (and resets its
  pending flag); teardown runs in a `TaskGroup` with the completion posted
  from the main actor (the background-thread post raced the 3 s poll);
  `GrokProcess.shutdown()` skips the unbounded-blocking courtesy
  `session/cancel` and escalates SIGTERM → 300 ms → SIGKILL so grok's MCP
  children (which exit only on stdin EOF) can never outlive the app.
- `purgeEmptySessions` now batches one layout save per purge instead of one
  full encode/HMAC/verify cycle per closed session.
