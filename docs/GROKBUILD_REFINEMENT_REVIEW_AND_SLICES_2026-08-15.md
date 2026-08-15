# GrokBuild refinement review and remaining slices — 2026-08-15

Status: **Slice 0 complete; Slice 1 authorized**. Phase 3 is accepted from clean
merged source, its exact billable receipt is ledgered, and only its disposable
acceptance session was removed. No Swift or configuration changed in Slice 0.

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
| Local source | `main == personal/main == bb01c58b4ab54528af6d44a4628defad8763a5cd` | Canonical and current |
| GitHub | PR #104 merged as `bb01c58`; 26 files, `+919/-455` | Phase 3 code is merged |
| Installed app | `Personal • main @ bb01c58b` (`dirty=false`) | Clean merged-main acceptance |
| Installed bytes | `dist` and installed executable SHA-256 both `9109250b74efee7ae88a9f002a291f9e34c661b2f1901355680e2c899aabff5a` | Package/install parity passes |
| Signing | Deep/strict valid, Team `DD2GCQJVB4`, no quarantine | Packaging integrity passes |
| Automated tests | `make test`: 894 passed, 0 failed | Strong regression baseline |
| Worktree | Existing untracked `docs/GROKBUILD_CODEX_HANDOFF_2026-08-15.md` preserved | Ownership must be resolved before a clean ship |
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
2. **The empty composer is still a visual island.** Its inner padding is 11×10,
   outer padding is 20×8, radius is 14, and a shadow remains; on an empty chat it
   reads heavier than every other piece of chrome.
3. **Accent behavior is still fragmented.** High-traffic views retain raw
   `Color.accentColor`, `.orange`, and `.borderedProminent` call sites, so macOS
   appearance/accent choices can still punch warm color into an otherwise cool
   workbench. Real warnings may stay warm, but they need the semantic
   `AppTheme.Palette.warning` owner instead of ad hoc color.
4. **Settings has not caught up visually.** The navigation is clear, but the pane
   content is a stack of large cards with substantial dead space. Keep this out
   of the current campaign unless the composer/accent work leaves the app feeling
   inconsistent; it is a separate visual slice, not an excuse to balloon Phase 4.
5. **The icon issue is quality, not missing resolution.** A tracked 1024×1024
   `AppIcon.png` already feeds the 300 KB installed ICNS, so the build is not
   currently falling back to the 909-byte 66 px menu mark. The source artwork is
   visibly jagged, however, so a genuinely redrawn high-quality icon still fits
   the vibe.
6. **The “cheap size” claim is overstated.** Deleting three tiny loose brand PNGs
   and the dead `workflowsStatusPill` improves hygiene, not the 26 MB bundle in a
   meaningful way. Keep `agent-desktop`; it is a required first-class capability.
7. **Campaign ledgers are reconciled by Slice 0.** They now name P3 complete and
   P3C composer/task-strip density as the authorized next slice.

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

**Three-sentence handoff after completion**

Slice 1 is complete: the composer and post-send strip are quieter without losing any authoring, accessibility, or receipt control. Jimmy has preauthorized Slice 2, limited to the semantic accent-leak sweep and its acceptance packet. Do not start icon cleanup, bundle experiments, Settings redesign, or any file decomposition.

## Slice 2 — semantic accent-leak sweep

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

Slice 2 is complete: ordinary interaction chrome now follows GrokBuild's cool semantic palette while warnings and failures remain distinct. Jimmy has preauthorized Slice 3, limited to icon quality, dead workflow chrome, bundle measurement, and helper-presence proof. Do not start the optional welcome extraction, Settings redesign, or full ChatView split.

## Slice 3 — icon polish and bundle honesty

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

Slice 3 is complete: the icon is visibly sharper, dead workflow chrome is gone, the measured bundle delta is recorded honestly, and Computer Use remains bundled. Jimmy has preauthorized Slice 4 only if the optional structural cleanup still has a concrete payoff after the visual campaign settles. Do not begin a full ChatView or ContentView decomposition under that authority.

## Slice 4 — optional welcome-only extraction

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

Slice 4 is complete: the welcome presentation moved without visual, lifecycle, or accessibility change, and the test build is warning-clean. The Visual Quiet campaign is closed unless Jimmy explicitly names a new product problem. Do not reopen the full ChatView split, Settings redesign, provider work, or backend architecture from this handoff.

## Backlog, not current scope

- Settings density and card hierarchy deserve a separate visual review after the
  high-frequency chat surface settles.
- A future decomposition should start from measured ownership seams, not a line
  count target; `ChatStore`, ACP, and continuity boundaries stay untouched.
- Binary-size work requires its own measurement campaign. The screenshot's P5
  cleanup is not evidence that the 24 MB Swift executable can safely shrink.
