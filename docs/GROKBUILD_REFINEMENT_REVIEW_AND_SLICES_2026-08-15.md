# GrokBuild refinement review and remaining slices — 2026-08-15

Status: **Slices 0–4 complete on the accepted P5 candidate; Slice 4 publication
is the campaign's final required pull request**. The semantic accent sweep
merged as `d62a396` in PR #109. Icon/bundle candidate `ade5794` passed 905 tests,
signed installed acceptance, real Computer Use, and 2,190,295-token presentation
stress; optional Slice 5 remains unauthorized.

## Verdict

The screenshot's direction fits GrokBuild. Cool tokens, the quiet welcome, the
overlay sidebar, and the tiny header all push the app toward a native agent
workbench instead of a dashboard wearing a chat costume. The useful screenshot
work is complete: semantic accents are cool, the icon is sharp, dead workflow
chrome is gone, and the bundle delta is measured honestly. The only visible
residual named during acceptance is the transient running task strip below the
composer; changing it is a separate visual decision.

The backend does not present an immediate correctness fire. The current suite
passes **905 tests with 0 failures**, the ACP/process/session boundaries are
explicit and fail closed, and the live UI exposed truthful idle/model/run state.
The maintenance smell is concentration rather than obvious breakage:
`ChatView.swift` is 3,485 lines, `ContentView.swift` is 2,125 lines, and the test
build emits three unused-local warnings in `SettingsTabTests.swift`.

## Evidence snapshot

| Surface | Current evidence | Judgment |
|---|---|---|
| Local source | P5 code-bearing candidate `ade57946eb3b365810c2e39ece21049b10e7a81d` from merged P4 `6f35526` | Canonical Visual Quiet Slice 4 branch |
| GitHub | One final P5 PR only; exact-head CI and merge are the remaining publication gate | No direct-main or upstream write |
| Installed app | `Personal • codex/grokbuild-vq-p5-icon-bundle-honesty @ ade5794` (`dirty=false`) | Clean signed code-bearing acceptance |
| Installed bytes | `dist` and installed executable match byte-for-byte | Package/install parity passes |
| Signing | Deep/strict valid, Team `DD2GCQJVB4`, no quarantine | Packaging integrity passes |
| Automated tests | focused P5 4/0; full suite and candidate `make ship`: 905/0 | Regression gates pass |
| Worktree | Clean at code-bearing P5 `ade5794` before documentation; paid probes made no source/configuration changes | Scope stayed exact |
| Bundle | 26,616 KiB, down 96 KiB; helpers unchanged; ICNS down 53,727 bytes | Honest housekeeping, not major shrinkage |

## Live UI review

### What already works

- The sidebar is genuinely a slide-over; hiding it returns a full-width canvas.
- The welcome is quiet and useful: one small mark, one heading, project name, and
  compact Ask, Build, and Review chips.
- Starter chips seed an editable draft without spawning a process or sending.
- The header is materially cleaner: filter, dashboard, More, contextual Review,
  and Run inspector remain reachable without a labeled-toggle parade.
- Settings moved to the account row and the idle Run inspector says exactly what
  it knows: no active process and no run evidence.
- The Review pane correctly reported the one existing untracked file and kept
  commit, push, and PR actions explicit.

### What still feels “ehhh”

1. **Release truth is now current.** Slice 0 installed and accepted clean merged
   Phase 3 at `bb01c58`; the next real problem is composer/task-strip density.
2. **P3C fixed the empty-composer island.** It now uses 11×7 inner and 20×5
   outer padding with no decorative shadow while retaining every 36×36 target.
3. **P3D removed duplicate live run chrome.** The task summary, trace, Stop, and
   inspector remain; `ThreadRunSpineView` no longer mounts in the transcript.
4. **Workers now own a real canvas.** Compact cards show one assignment and one
   truthful status, raw parent/identity/usage detail stays disclosed, and a failed
   typed child tool forces **Needs Review** instead of false green completion.
5. **P4 fixed accent fragmentation.** Ordinary high-traffic controls now use
   semantic `AppTheme` owners; genuine warning/failure states remain distinct.
6. **Settings has not caught up visually.** The navigation is clear, but the pane
   content is a stack of large cards with substantial dead space. Keep this out
   of the current campaign unless the composer/accent work leaves the app feeling
   inconsistent; it is a separate visual slice, not an excuse to balloon Phase 4.
7. **P5 fixed icon quality and packaging.** A deterministic SVG master feeds one
   shared fail-closed dev/release ICNS packager with ten verified slots.
8. **The “cheap size” claim remains overstated, honestly.** The installed bundle
   fell only 96 KiB. `agent-desktop`, Computer Use MCP, updater, and skills remain
   first-class package contents.
9. **Campaign ledgers are reconciled through Slice 4.** Optional welcome-only
   extraction and any task-strip change require a new explicit product decision.

## Slice rules

- One slice, one bounded branch, one PR, normal merge, then the next slice.
- Preserve `origin` as read-only and publish only through `personal`.
- Do not touch `ChatStore`, `GrokProcess`, ACP, provider routing, credentials, or
  the required `agent-desktop` bundle for this campaign.
- Every code slice gets focused tests, `make test`, candidate `make ship`, installed
  Computer Use acceptance, exact review, merge, and merged-main acceptance.
- A billable packet requires explicit current authority, a new chat, one exact
  marker/reply, a 200k ceiling, and deletion of only that ledgered session.
- Protect OK-F and backend `019ffdad-0d4f-7f42-a429-7ac12ad8198d`; never use
  Clear Empty or broad session/process cleanup.
- Preserve the existing untracked handoff until its ownership is resolved.

## Slice 0 — close Phase 3 truthfully

Status: **complete 2026-08-15**. Clean `bb01c58` ship passed 894/0, installed
identity/signing/hash checks and focused Computer Use; the exact P3 packet and
session cleanup are recorded in `docs/OUTSTANDING.md`, followed by two
process-zero samples.

**Goal:** turn merged Phase 3 code into an honest installed and ledgered release
receipt before adding more visual work.

**Scope**

- Resolve the existing untracked handoff without discarding it; use an explicitly
  authorized reversible preservation step if a clean `bb01c58` ship requires it.
- Install clean merged source through `make ship`; require stamp `bb01c58`,
  `dirty=false`, signed dist/install byte parity, and no quarantine.
- Use Computer Use on `/Applications/GrokBuild.app` to prove sidebar overlay,
  titlebar contrast, account-row Settings, inspector dropdown, Review, no header
  hairline, and idle task-strip suppression.
- If explicitly authorized, run one new-chat packet:
  `GB-VQ-P3-<UTC>` → exactly `GB_VQ_P3_OK`, then delete only that session.
- Reconcile `AGENTS.md`, `docs/OUTSTANDING.md`, and the Visual Quiet status after
  the code-bearing install is accepted. Do not `make ship` a later docs-only
  successor merely to chase the documentation commit.

**Tests and exit**

- `git diff --check`
- `make test` (baseline: 894/0)
- Installed identity, signing, parity, focused AX/pixel proof, exact session
  cleanup, and two process-zero samples after quit
- Ledger may call the billable packet complete only if its exact receipt exists

**Three-sentence handoff after completion**

Slice 0 is complete: Phase 3 is installed from clean merged source, its live receipt is recorded, and only the exact acceptance session was removed. Jimmy has preauthorized Slice 1, limited to composer and task-strip density plus its tests and documentation. Do not start the accent sweep, icon work, or optional structural extraction.

## Slice 1 — finish the composer and post-send density

Status: **complete 2026-08-15**. Commit `6697530` passed the focused 52-test
gate and two full 896-test gates, clean `make ship`, signed/hash parity, Light,
Dark, narrow-width, plain, ordered-tool, and two-worker installed acceptance.

**Goal:** finish the part of the screenshot's Phase 3 that PR #104 intentionally
deferred.

**Scope**

- Tighten `ChatComposer` inner/outer vertical padding and reduce its floating-card
  weight while preserving every 36×36 hit target.
- Keep `Describe a task`, one-to-eight-line growth, add menu, mode, model/effort,
  mic, Send/Stop/Cancel, focus, hover, and keyboard contracts.
- Slim the post-send task context strip to one calm summary line plus disclosure;
  do not delete its identity, recovery, branch, or model truth.
- Do not redesign Settings, welcome chips, transcript content, or runtime behavior.

**Tests and billable acceptance**

- Focused `ComposerPresentationContractTests`, `CodexShellParityTests`,
  `ResponsiveAndAccessibilityTests`, and task-strip projection tests
- `make test`, candidate/merged-main `make ship`, Light and Dark empty-chat proof,
  narrow-width proof, and one real settled turn showing the slim strip
- New-chat marker `GB-VQ-P3C-<UTC>` → exactly `GB_VQ_P3C_OK`; delete only that
  session after the receipt is captured

**Acceptance receipt:** the standard packet returned exactly `GB_VQ_P3C_OK`
with 16,066 tokens and no tools. The ordered-tool packet ran `pwd` then
`sed -n '1p' VERSION` as two successful receipts and returned
`GB_VQ_P3C_TOOLS_OK` with 48,877 tokens. The agentic packet spawned exactly two
parallel workers, waited for both, reported useful concurrency 2 and 28,807
child tokens against a 115,542-token parent receipt (144,349 combined), but it
also emitted one progress sentence before `GB_VQ_P3C_AGENTIC_OK`; coordination
passed while exact final-only prose is recorded as partial.

**Cleanup receipt:** exact Close Session removed tabs `3F209BD7…`, `844DC64D…`,
and `27F3B2E1…` plus their three parent backends. The CLI could not enumerate the
two exact children, so only those validated child directories were moved
recoverably to Trash. All three markers now have zero retained session files,
all five live backend directories are absent, protected OK-F remains, and two
normal-quit process-zero samples passed at `11:18:21` and `11:18:29 -0500`.

**Three-sentence handoff after completion**

Slice 1 is complete: the composer and post-send strip are quieter without losing any authoring, accessibility, or receipt control. The next proposed slice is P3D live activity composition: remove the redundant live Run card and make active subagents first-class in the right-side canvas. Do not start P3D, the accent sweep, icon work, Settings redesign, or file decomposition until Jimmy explicitly authorizes the next slice.

## Slice 2 — live activity composition (P3D, complete 2026-08-15)

**Goal:** let the transcript show the work and answer while live coordination
occupies a deliberate right-side surface instead of duplicating state in a card.

**Scope**

- Remove the live `ThreadRunSpineView` **Run / Working / Run inspector** card
  from the transcript after proving the task summary, trace/tool rows, Stop, and
  inspector retain phase, current action, plan, recovery, and receipt truth.
- Keep settled checkpoints and run-history evidence; do not remove backend state
  or manufacture completion from live projection.
- Promote active subagents from tiny `ActivitySidebar` rows into a first-class
  right-side live activity canvas with worker name, status, current assignment,
  and honest completion/error state. Do not expose private reasoning or raw child
  output.
- Auto-open only for current-turn live workers. At narrow width, collapse to a
  named/count control without covering or clipping transcript content; settlement
  may return to the compact receipt surface.
- Do not perform the accent sweep, Settings redesign, runtime changes, or broad
  `ChatView` decomposition in this slice.

**Tests and billable acceptance**

- Source/presentation contracts forbid `grok-run-spine-live` from mounting while
  preserving the task-contract, Stop, tool trace, worker identity, and settled
  evidence owners.
- Responsive tests cover docked, overlay, and collapsed worker-canvas behavior,
  including the 1100-point sidebar-overlay case observed during P3C.
- `make test`, candidate/merged-main `make ship`, and a two-worker fresh-chat
  packet under the 200k ceiling with live and settled Light/Dark screenshots.

**Receipt**

PR #107 carries code/test commit `2e1deb7` and merged as `1e11be2` after the
required exact-head check passed. Focused tests passed 61/61; candidate and
merged-main ships each passed 897/897 with exact clean signed installs. Installed
acceptance proved the compact four-worker Light canvas, readable tool text,
two-worker live/settled Dark canvas, full-width left/right coexistence, and the
900/1,180 responsive boundaries. BETA's failed typed child tool forced **Needs
Review**; the stop packet retained **Cancelled** plus **No final report
(orphaned)** instead of laundering interruption into success.

Five parent receipts reported 358,637 total tokens. Standard and Dark exact-token
packets passed; ordered-tool and four-worker behavior passed with final-only prose
partial because each added one progress sentence. Exact cleanup removed five tabs
and parents, moved eight validated children recoverably to Trash, left active
marker counts at zero, preserved `prompt_history.jsonl`, and protected OK-F.
Fresh merged-main UI proof kept the screen-filling Dark workbench and usable left
sidebar, while App settings reported `Personal • main @ 1e11be22`.

**Three-sentence handoff after completion**

Slice 2 is complete: the duplicate live Run card is gone and active subagents work visibly in a truthful right-side canvas. The next proposed slice is the semantic accent-leak sweep and its bounded acceptance packet. Do not start accent work, icon cleanup, Settings redesign, or structural extraction without Jimmy's explicit authorization.

## Slice 3 — semantic accent-leak sweep

**Goal:** stop the cool-neutral shell from inheriting arbitrary macOS accent and
orange styling.

**Scope**

- Replace high-traffic `Color.accentColor` use with
  `AppTheme.Palette.accent` or `.link` according to meaning.
- Route warning/attention state through `AppTheme.Palette.warning`; do not make
  destructive, failed, stalled, unknown, and ordinary selected states the same.
- Replace unscoped `.borderedProminent` where it injects system accent; maintain a
  documented allowlist for places where native prominence is intentional.
- Cover `ChatView`, `ComposerViews`, `ActivitySidebar`, `LivePlanSpine`,
  `PreviewPane`, `SlashAutocompleteView`, `SessionDashboardPanel`, and sidebar
  high-traffic paths without touching layout or backend owners.

**Tests and billable acceptance**

- Source contract that forbids new raw accent/prominent call sites outside the
  reviewed allowlist
- Focused status-semantics and chrome tests, then `make test` and `make ship`
- New-chat marker `GB-VQ-P4-<UTC>` → exactly `GB_VQ_P4_OK`; prove Light and Dark,
  selected controls, warning controls, and inspector states before exact cleanup

**Completion receipt**

PR #109 merged the semantic sweep as `d62a396`; focused tests passed 4/4 and
merged-main `make ship` passed 901/901 with clean signed install identity. The
Light, Dark, ordered-tool, and four-worker packet used 330,658 reported parent
tokens, exposed and fixed one AppKit accent leak, and left failed/retry evidence
truthful. Only the two exact parents and four child backends were removed; the
recovery packet, durable prompt history, and protected OK-F task remain.

**Three-sentence handoff after completion**

Slice 3 is complete: ordinary interaction chrome now follows GrokBuild's cool semantic palette while warnings and failures remain distinct. The next proposed slice is limited to icon quality, dead workflow chrome, bundle measurement, and helper-presence proof. Do not start icon work, the optional welcome extraction, Settings redesign, or the full ChatView split without Jimmy's explicit authorization.

## Slice 4 — icon polish and bundle honesty

Status: **complete on code-bearing candidate `ade5794`**. Full details and the
2,190,295-token receipt are in the Phase 5 completion entry in the Visual Quiet
campaign and the canonical ledger.

**Goal:** improve what users can see and delete genuine dead weight without
pretending a few kilobytes transformed the app.

**Scope**

- Approve a genuinely clean master icon before replacement; produce correct
  macOS sizes from that source and visually inspect Dock, Finder, About, and
  app-switcher rendering.
- Remove `showWorkflowsPill` and `workflowsStatusPill` only after confirming zero
  mounted consumers.
- Consolidate duplicate loose brand resources only if every runtime lookup and
  packaging fallback remains covered.
- Keep `agent-desktop`, `GrokBuildComputerUseMCP`, bundled skills, and updater
  helpers.
- Record before/after bytes for the whole app and every changed resource; call the
  result housekeeping unless the measured delta proves otherwise.

**Tests and billable acceptance**

- Icon/resource packaging tests, dead-symbol source contract, Computer Use helper
  presence/self-test, `make test`, and `make ship`
- New-chat marker `GB-VQ-P5-<UTC>` → exactly `GB_VQ_P5_OK`; prove installed app
  identity and helper presence, then remove only that session

**Three-sentence handoff after completion**

Slice 4 is complete: the icon is visibly sharper, dead workflow chrome is gone, the measured bundle delta is recorded honestly, and Computer Use remains bundled. The optional welcome-only extraction remains a separate proposed slice only if it still has a concrete payoff after the visual campaign settles. Do not begin any structural cleanup without Jimmy's explicit authorization, and never turn it into a full ChatView or ContentView decomposition.

## Slice 5 — optional welcome-only extraction

**Recommendation:** skip unless the welcome is about to change again. Moving one
already-quiet block out of a 3,485-line file has modest value and no user-visible
payoff; a broad split would create large regression risk across transcript,
continuity, scrolling, and accessibility ownership.

**If authorized**

- Extract only the welcome/no-project presentation into a focused view file.
- Preserve `showsEmptyTranscriptWelcome`, restored-session suppression,
  starter-draft behavior, accessibility labels, and spawn-on-Send.
- Remove the three known unused-local test warnings in the same narrow maintenance
  PR only if doing so does not broaden product scope.
- Run focused welcome/parity tests, `make test`, `git diff --check`, and visual
  parity against the accepted Slice 3 state; no billable packet is justified.

**Three-sentence handoff after completion**

Slice 5 is complete: the welcome presentation moved without visual, lifecycle, or accessibility change, and the test build is warning-clean. The Visual Quiet campaign is closed unless Jimmy explicitly names a new product problem. Do not reopen the full ChatView split, Settings redesign, provider work, or backend architecture from this handoff.

## Backlog, not current scope

- Settings density and card hierarchy deserve a separate visual review after the
  high-frequency chat surface settles.
- A future decomposition should start from measured ownership seams, not a line
  count target; `ChatStore`, ACP, and continuity boundaries stay untouched.
- Binary-size work requires its own measurement campaign. The screenshot's P5
  cleanup is not evidence that the 24 MB Swift executable can safely shrink.
