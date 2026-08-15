# GrokBuild refinement review and remaining slices — 2026-08-15

Status: **Slices 0–1 complete; Slice 2 proposed and not started**. P3C is accepted
from the clean installed candidate, its three bounded billable receipts are
ledgered, and only their exact parent/child sessions were removed. Jimmy's live
feedback adds a focused activity-composition slice before the accent sweep.

## Verdict

The screenshot's direction fits GrokBuild. Cool tokens, the quiet welcome, the
overlay sidebar, and the tiny header all push the app toward a native agent
workbench instead of a dashboard wearing a chat costume. The remaining useful
work is narrower than the screenshot implies: close Phase 3 truthfully, tighten
the composer and post-send strip, sweep semantic accent leaks, then do icon and
dead-code housekeeping.

The backend does not present an immediate correctness fire. The current suite
passes **894 tests with 0 failures**, the ACP/process/session boundaries are
explicit and fail closed, and the live UI exposed truthful idle/model/run state.
The maintenance smell is concentration rather than obvious breakage:
`ChatView.swift` is 3,485 lines, `ContentView.swift` is 2,125 lines, and the test
build emits three unused-local warnings in `SettingsTabTests.swift`.

## Evidence snapshot

| Surface | Current evidence | Judgment |
|---|---|---|
| Local source | `codex/grokbuild-vq-p3c-composer-density`; code/test commit `6697530531e6e3f65f80f848fcb86d4bcb7055c1`, based on `main == personal/main == aff384c` | Canonical Slice 1 candidate |
| GitHub | PR #104 merged Phase 3 as `bb01c58`; PR #105 merged its closeout as `aff384c`; P3C publication is PR #106 | Phase 3 is closed; P3C has its focused publication lane |
| Installed app | `Personal • codex/grokbuild-vq-p3c-composer-density @ 66975305` (`dirty=false`) | Clean P3C candidate acceptance |
| Installed bytes | `dist` and installed executable SHA-256 both `2bb91f51c1c2d8d10e433b10adff2775ee058a07f654dcddb1524a44dd8ae74f` | Package/install parity passes |
| Signing | Deep/strict valid, Team `DD2GCQJVB4`, no quarantine | Packaging integrity passes |
| Automated tests | focused 52/0; `make test` and candidate `make ship`: 896/0 | Regression gates pass |
| Worktree | Clean after commit `6697530`; paid probes made no source/configuration changes | Scope stayed exact |
| Bundle | 26 MB total: 24 MB app binary, 2.1 MB `agent-desktop`, 216 KB Computer Use MCP, 300 KB icon | No large cheap deletion exists |

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
3. **The live transcript still repeats run state.** The top task summary, trace,
   Stop control, and inspector already own live truth, yet `ThreadRunSpineView`
   adds a full-width **Run / Working / Run inspector** card under the trace.
4. **Subagents still look tucked away.** They auto-open correctly, but the
   260-point `ActivitySidebar` presents only tiny name/status rows. The live
   workers deserve a first-class right-side activity canvas when space permits,
   with narrow-width fallback that never covers the transcript.
5. **Accent behavior is still fragmented.** High-traffic views retain raw
   `Color.accentColor`, `.orange`, and `.borderedProminent` call sites, so macOS
   appearance/accent choices can still punch warm color into an otherwise cool
   workbench. Real warnings may stay warm, but they need the semantic
   `AppTheme.Palette.warning` owner instead of ad hoc color.
6. **Settings has not caught up visually.** The navigation is clear, but the pane
   content is a stack of large cards with substantial dead space. Keep this out
   of the current campaign unless the composer/accent work leaves the app feeling
   inconsistent; it is a separate visual slice, not an excuse to balloon Phase 4.
7. **The icon issue is quality, not missing resolution.** A tracked 1024×1024
   `AppIcon.png` already feeds the 300 KB installed ICNS, so the build is not
   currently falling back to the 909-byte 66 px menu mark. The source artwork is
   visibly jagged, however, so a genuinely redrawn high-quality icon still fits
   the vibe.
8. **The “cheap size” claim is overstated.** Deleting three tiny loose brand PNGs
   and the dead `workflowsStatusPill` improves hygiene, not the 26 MB bundle in a
   meaningful way. Keep `agent-desktop`; it is a required first-class capability.
9. **Campaign ledgers are reconciled through Slice 1.** They now name P3C
   complete and P3D live activity composition as the proposed next slice.

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

## Slice 2 — live activity composition (P3D, proposed next)

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

**Three-sentence handoff after completion**

Slice 3 is complete: ordinary interaction chrome now follows GrokBuild's cool semantic palette while warnings and failures remain distinct. The next proposed slice is limited to icon quality, dead workflow chrome, bundle measurement, and helper-presence proof. Do not start icon work, the optional welcome extraction, Settings redesign, or the full ChatView split without Jimmy's explicit authorization.

## Slice 4 — icon polish and bundle honesty

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
