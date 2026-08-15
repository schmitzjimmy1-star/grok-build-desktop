# GrokBuild Visual Quiet Campaign — 2026-08-15

Status: **Phases 1–3, P3C, and P3D verified** (cool tokens, Path A chips,
Codex-style overlay/quiet chrome, composer/task-strip density, and live activity
composition). **Phase 4 accent sweep is authorized and in progress, with billable
acceptance capped at 2.5 million reported tokens.** Phases 5–6 wait.
Leftover `ChatView` split stays deferred.

This is a **product visual** campaign. It is **not** leftover Phase 3
(`ChatView` file-split). That stays deferred. Optional Phase 6 is a
welcome-only extract after the look settles, still not the full C9 / leftover
Phase 3 split.

Leftover closeout Phases 1–2 are already merged on `main` as `7a3006d`
(PR #102). Installed app at plan time: `/Applications/GrokBuild.app`,
`Personal • main @ 7a3006d7`, `dirty=false`, appearance **Dark**.

Auditors: [chrome density](fbe0e783-a42d-4b75-8c1a-3d07b9c93647),
[theme and size](9bb53ca5-7233-4905-ba9a-f5826a19e9a1),
[frontend ownership](023fb47d-156d-4133-a067-192d3a5fce63).
Planner: [phase map](f029b373-be43-4dc2-a8f2-f2bb80950abe).

---

## What Jimmy asked for

Quieter chrome. Fewer header toggles. Less welcome-card treatment. Tighter
composer. Colors that feel natural instead of brown / muddy. A visual and
code review of the front end. Live prompts to judge presentation. A phased
plan with billable tests. Cheap ways to lighten the installed app.

---

## Live review (2026-08-15, installed `7a3006d`)

Computer Use against `/Applications/GrokBuild.app` only. Appearance was
Dark, flipped to Light for one screenshot, then restored to Dark and Applied.
Two new-chat prompts ran on a throwaway tab (not OK-F). Close Session
removed that tab. `grok sessions search GB_VQ_VIBE` is Total: 0. Protected
OK-F is selected again. Aug 14 `(no summary)`
`019ffdad-0d4f-7f42-a429-7ac12ad8198d` still searchable (Total: 1).

### Empty New chat

The loudest surface. Center stack is a 34×34 brand mark, 24 pt
“What do you want to work on?”, project name, “Grok agent runs in this
folder.”, then three bordered Ask / Build / Review cards with detail
paragraphs. Vertical padding is 48 pt. The composer sits below as a wide
glass card with “Describe a task”, +, Grok 4.6 · Default, mic, and Send.

Header on that empty tab: sidebar toggle, folder + “New chat”, More
actions, labeled **Tasks**, labeled **Run inspector**, Settings. Review is
hidden (correct: no dirty files).

### Light vs Dark color truth

There is no literal brown token. Pixel samples from screenshots:

| Surface | Dark | Light |
|---|---|---|
| Canvas / header | `(16, 16, 16)` | `(250, 250, 249)` |
| Sidebar | near-black | `(239, 239, 237)` |
| Composer field | `(31, 31, 31)` | `(255, 255, 255)` |

Dark is numerically neutral charcoal. It still *reads* muddy / warm on this
display because it is a soft black with lots of gray chrome, not a cool
ink. Light is the real cream: blue sits 1–2 points below red/green, matching
`AppTheme` (`canvas` `0.985, 0.985, 0.98`, sidebar `0.95, 0.95, 0.945`).
The “brown and ehh” is that Light warmth plus Dark mud plus
`Color.accentColor` / `.orange` / `.borderedProminent` leaks (system accent
and warning orange), not a brown swatch in `AppTheme`.

### After P1–P2 (installed dirty candidate)

Light canvas `(243, 242, 245)`, Dark canvas `(15, 15, 16)`. Both have a
cool blue bias. Welcome is a 24 pt mark, heading token, project name only,
and three capsule chips. Light chips stay visible on stone; no extra border
was added. Composer glass and labeled header toggles stay for Phase 3.
Accent leaks stay for Phase 4.

### After a real turn

A no-tool markdown greeting (`Hey` / one sentence / one bullet) and a
`printf 'GB_VQ_VIBE'` tool turn showed:

- Answers themselves are fine. Heading / body / list read cleanly.
- **Thought** defaults expanded (`Thought for 1s` / `2s`). That is extra
  chrome on a short reply.
- Tool cards are already quiet: `Tool use` + `Execute printf… Succeeded`.
- The **task context strip** appears after first Send: prompt excerpt,
  Checkpoint saved, project, branch, Live · Grok 4.6. That is a second
  header. It is the biggest post-welcome density hit.
- **Run inspector** stays labeled and can show a status dot after
  settlement.
- Composer stays a tall glass island even when empty.

### Code review (what owns the look)

Presentation lives in `AppTheme.swift` plus Views. Behavior stays in
`ChatStore` / `GrokProcess` / ACP. Do not open those for this campaign.

`ChatView.swift` is still ~3,482 lines, but TopBar / Composer / Review
toggle are already extracted. Leftover Phase 3 would only move more files.
It does not make the app quieter. Do it last or never.

The brown leak is `Color.accentColor` and `.borderedProminent` ignoring
`ContentView`’s `.tint(AppTheme.Palette.accent)` (neutral black/white).
Orange is used for warnings, schedules, and inspector dots.

Dead chrome already in the tree: `workflowsStatusPill` is defined and never
mounted.

### App size

Installed `/Applications/GrokBuild.app` is **26 MB**.

| Piece | Size | Keep? |
|---|---|---|
| `GrokBuild` binary | 24 MB | Yes |
| `agent-desktop` | 2.1 MB | **Yes. Do not unbundle.** |
| `GrokBuildComputerUseMCP` | 216 KB | Yes |
| `AppIcon.icns` | 300 KB | Replace the upscaled 909 B mark |
| Skills + helpers | ~20 KB | Yes |
| `docs/images/` | ~21 MB in repo | Does not ship |

Meaningful size cuts are icon housekeeping and dead view deletion, not
dropping Computer Use.

---

## Campaign map

| Phase | Title | User-visible job | Size | Marker → exact reply |
|---|---|---|---|---|
| **P1** | Cool tokens + semantic colors | Light loses the cream cast. Dark gets a cooler ink. Add `warning` / `link` tokens. No control restyle yet. | S | `GB-VQ-P1-<UTC>` → `GB_VQ_P1_OK` |
| **P2** | Quiet welcome | Smaller mark, quieter headline, less padding. Pills become compact chips **or** go away (Jimmy chooses). | M | `GB-VQ-P2-<UTC>` → `GB_VQ_P2_OK` |
| **P3** | Overlay sidebar + quiet chrome | Compact selected-project sessions. Codex slide-over sidebar. Account row opens Settings. Header sits with the traffic lights. Inspector is a dropdown; live subagents open a right tracker. No header hairline. | M | `GB-VQ-P3-<UTC>` → `GB_VQ_P3_OK` |
| **P3C** | Composer + task-strip density | Composer loses padding/shadow weight. Collapsed task strip becomes one objective/phase line plus disclosure. | S | `GB-VQ-P3C-<UTC>` → `GB_VQ_P3C_OK` |
| **P3D** | Live activity composition | Redundant transcript Run card goes. Active workers become a first-class right-side activity canvas with honest narrow fallback. | M | `GB-VQ-P3D-<UTC>` → `GB_VQ_P3D_OK` |
| **P4** | Accent-leak sweep | Send, chips, CTAs, inspector dots use `AppTheme`, not system brown/orange. | M | `GB-VQ-P4-<UTC>` → `GB_VQ_P4_OK` |
| **P5** | Cheap bundle lightening | Real AppIcon. Drop duplicate PNGs. Delete unused `workflowsStatusPill`. Keep `agent-desktop`. | S | `GB-VQ-P5-<UTC>` → `GB_VQ_P5_OK` |
| **P6** | Optional welcome extract | Move the quiet welcome into its own file. Not the full ChatView split. | M | none (structural) |

```text
P1 ──► P2 ──► P3 ──► P3C ──► P3D ──► P4 ──► P5 ──► (optional) P6
```

No parallel product phases on the same chrome files.

---

## Jimmy decisions before Phase 1

1. **Start P1?** This file is the plan. Code starts only after an explicit yes.
2. **Welcome pills (P2):**
   - **Path A (recommended):** keep Ask / Build / Review as compact chips,
     drop the detail paragraphs and card chrome.
   - **Path B:** remove the pills. Update `WorkbenchIntentTests` and
     `CodexShellParityTests.testEmptyStateIntentPillsStillExist`.
3. **Thinking blocks:** leave default-expanded for now. Optional later if
   short answers still feel noisy after P2–P3.
4. **ChatView split:** stays deferred. P6 is welcome-only if we even do it.

---

## Hard stops (every phase)

- Canonical worktree only:
  `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- `personal` = `schmitzjimmy1-star/grok-build-desktop`. `origin` =
  `rimusz/grok-build-desktop` (read-only). No force push, no origin writes,
  no notarize, no GitHub `(Notarized)` release.
- Do **not** start leftover Phase 3 / C9 Phase 2 full `ChatView` split.
- Do **not** touch `ChatStore`, ACP, `GrokProcess`, provider routing, or
  unbundle `agent-desktop`.
- Gates A–H every code phase. Candidate `make ship` may be `dirty=true`
  until commit. Post-merge Gate E/H needs stamp == HEAD, `dirty=false`.
- Computer Use on **`/Applications/GrokBuild.app` only**.
- Billable packets: **new chat only**. Marker `GB-VQ-P<n>-<UTC>`. Ceiling
  **200k**. Exact reply token only. Gate F deletes **only that session**.
  Leave protected **OK-F** and Aug 14 `(no summary)`
  `019ffdad-0d4f-7f42-a429-7ac12ad8198d` alone. Never Clear Empty.
- Pause after each packet unless Jimmy already authorized the next phase
  or commit in the same request.

### Standard billable packet (P1–P5)

```text
Acceptance packet. This is a no-tool check. Do not use tools, workers, or
update_plan. Reply with exactly GB_VQ_P<n>_OK and stop.
```

Marker in the user message: `GB-VQ-P<n>-<UTC>`
(example: `GB-VQ-P1-20260815T180000Z`). Fresh UTC per run. Do not reuse
leftover / C8 / C9 markers.

Branch pattern: `codex/grokbuild-vq-p<n>-<short-purpose>`

---

## What must stay (contracts)

AX homes and behavior this campaign may restyle but must not delete:

| Id / rule | Why |
|---|---|
| `grok-message-composer` + empty value includes **Describe a task** | Composer contract |
| `grok-composer-add-menu`, `grok-mode-selector`, `grok-model-effort-selector` | Slice 4 |
| `grok-send` / `grok-stop` / `grok-cancel-pending-submit` | Send gate |
| `grok-header-review-toggle` | Contextual Review. No third Review under the composer. |
| `grok-run-inspector-toggle` | Header owns the inspector |
| `grok-tasks-status` | Header owns Tasks |
| Settings on the sidebar account row | `grok-sidebar-account-settings`; Command-comma still works |
| `grok-launch-session-choices` + Resume / New / Browse ids | Resume honesty |
| `grok-task-context-strip` | May slim, must remain |
| Spawn-on-Send | Welcome pills only seed the draft |
| No Details shelf, no sidebar Activity/Agents lane | Codex parity |

---

## Phase 1 — Cool tokens + semantic colors

**Goal:** Light stops looking like cream paper. Dark looks like cool ink
instead of muddy charcoal. Later phases inherit the tokens.

**Size:** S

**Files**
- `GrokBuild/AppTheme.swift` (primary)
- `GrokBuild/AppDelegate.swift` only if `canvasNSColor` must stay matched
- Docs: `ARCHITECTURE.md` theme note, `docs/OUTSTANDING.md` receipt
- Tests: small `AppTheme` source/contract test (Light canvas/sidebar not
  systematically warmer than cool neutral; `warning` and `link` exist)

**Direction (not locked hex until implementation)**
- Light canvas: stone, equal RGB or a hair of blue (`#F5F5F7` family)
- Light sidebar: same family, slightly darker
- Light hover: cool gray, not `(0.92, 0.92, 0.91)`
- Dark canvas: keep near-black but allow a cool bias
  (`0.07, 0.07, 0.075`) so it stops reading brown on warm monitors
- Add `Palette.warning` and `Palette.link`. Do not consume them in P1
  except as defined tokens.

**Must not touch**
- Welcome / header / composer layout
- `Color.accentColor` call sites (P4)
- `ChatStore` / ACP
- ChatView split

**Billable packet**
- New chat. Marker `GB-VQ-P1-<UTC>`. Exact `GB_VQ_P1_OK`.
- Prove Settings → App → Light and Dark. New-chat canvas is cool-neutral
  in both. No control change expected.

**Exit:** `make test`, candidate `make ship`, Computer Use Light + Dark,
Gate F, Jimmy OK.

---

## Phase 2 — Quiet welcome

**Goal:** New chat looks like a place to type, not a marketing card stack.

**Size:** M

**Default path A**
- Brand mark ~24 pt, not 34
- Headline uses `AppTheme.Typography.heading` (17 pt), not raw 24 pt
- Drop “Grok agent runs in this folder.”
- Vertical padding 48 → ~20–24
- Ask / Build / Review become compact chips (icon + title, no detail
  paragraph, no 200 pt bordered cards)

**Path B** (only if Jimmy picks it)
- Remove the pills. Update inventory tests. Composer remains the launch
  gate.

**Files**
- `GrokBuild/Views/ChatView.swift` (`welcomeState`, `CodexPromptPill`,
  `noProjectState` padding only)
- `WorkbenchIntent` / `ComposerModels.swift` only if detail copy changes
- Tests: `WorkbenchIntentTests.swift`, `CodexShellParityTests.swift`
- `README.md` if the landing screenshot story changes

**Must not touch**
- `showsEmptyTranscriptWelcome` / spawn-on-Send
- Composer and header AX ids
- ACP

**Billable packet**
- New chat. Marker `GB-VQ-P2-<UTC>`. Exact `GB_VQ_P2_OK`.
- Prove empty landing is quieter. Composer still says Describe a task.
- Restored / resume tabs must not grow Ask / Build / Review.

**Exit:** chosen path written into the receipt; `make test` + `make ship` +
Computer Use New chat Light and Dark; Gate F; Jimmy OK.

Path A shipped. Receipt is in `docs/OUTSTANDING.md` under Visual Quiet
Phases 1–2.

---

## Phase 3 — Overlay sidebar + quiet chrome

**Goal:** The canvas is fullscreen. Projects stop eating the rail.
Settings lives on the account row. The top line sits with the traffic
lights. Header chrome stays tiny. Subagents are trackable on the right.

Jimmy redirected this phase twice on 2026-08-15: first the overlay
sidebar, then inspector / banner / ellipsis quieting. Composer
tightness still waits.

**Keep:** sidebar toggle, folder + title, More actions,
`grok-tasks-status` (hidden when idle), contextual
`grok-header-review-toggle`, `grok-run-inspector-toggle`,
Command-comma Settings.

**This slice**
- Expand session lists only for the selected project. Tighter project
  and session rows.
- Project sidebar is a Codex-style slide-over (`TitlebarMetrics` overlay
  width). Chat stays full width. Backdrop tap dismisses.
- Account row opens Settings (`grok-sidebar-account-settings`). Remove
  the header gear.
- Main window uses `.fullSizeContentView`. Header / Settings back row
  sit just under the traffic lights (`TitlebarMetrics.contentTopInset`)
  with consistent white Dark icons (`TitlebarGlyph`).
- More actions is one ellipsis (`.menuIndicator(.hidden)`). No header
  hairline. Titlebar icons use `TitlebarGlyph` so Dark vibrancy cannot
  paint them at canvas black.
- Review and inspector are icon-only. Inspector is a quick-look
  dropdown; live workers open the right-side tracker.
- Launch choices stay as three quiet text actions, not a tinted banner.
- Task strip stays off on idle `.ready`.

**Files**
- `GrokBuild/MainWindowLayout.swift` (`TitlebarMetrics`)
- `GrokBuild/AppDelegate.swift` (`.fullSizeContentView`)
- `GrokBuild/ContentView.swift` (overlay + reduce-motion toggle)
- `GrokBuild/Views/SidebarView.swift`
- `GrokBuild/AppTheme.swift` (`TitlebarGlyph`, `titlebarControl`)
- `GrokBuild/Views/ChatTopBar.swift`
- `GrokBuild/Views/SettingsView.swift` (titlebar inset)
- `GrokBuild/Views/ChatHeaderReviewToggle.swift`
- `GrokBuild/Views/ChatView.swift` (inspector menu, launch choices, Tasks)
- `GrokBuild/Views/ActivitySidebar.swift` (tracker rail)
- `GrokBuild/Models/ContextInspectorProjection.swift` (`RunInspectorQuickLook`)
- Tests: `CodexShellParityTests`, `MainWindowLayoutTests`,
  `ContextInspectorProjectionTests`, `ActivitySidebarTests`,
  `ResponsiveAndAccessibilityTests`

**Must not touch**
- Removing Review / inspector / Settings (Settings moves, it is not
  deleted)
- Welcome content (P2 owns that)
- Composer glass
- `ChatStore` / ACP
- Leftover Phase 3 `ChatView` split

**Billable packet**
- New chat. Marker `GB-VQ-P3-<UTC>`. Exact `GB_VQ_P3_OK`.
- Hide sidebar: canvas is full width. Show: panel slides over.
- Only the selected project's sessions are listed.
- Name row opens Settings. No header gear.
- Header lines up with the traffic lights. Dark stays Jimmy's
  appearance after any Light probe.
- More actions is one click. No hairline under the title.
- Inspector menu shows a quick look. Live subagents appear on the right.

**Exit:** meaningful AX names; `make test` + `make ship` + Computer Use;
Gate F; Jimmy OK.

Phase 3 shipped as `bb01c58` (PR #104) and was accepted from clean merged
`main` on 2026-08-15. `make ship` passed 894 tests, installed `dirty=false`,
and produced matching dist/installed SHA-256 `9109250b74ef…`; the exact
`GB-VQ-P3-20260815T154813Z` packet returned `GB_VQ_P3_OK`, was ledgered, and
only its exact local/backend session was deleted. Two post-quit process-zero
samples passed; protected OK-F and `019ffdad-0d4f-7f42-a429-7ac12ad8198d`
remain.

### P3C — Composer and post-send density closeout

Tighten only `ChatComposer` inner/outer vertical padding and floating-card
weight, preserving every 36×36 target and all existing editor, add, mode,
model, mic, Send/Stop/Cancel, focus, hover, growth, and AX contracts. Slim
`grok-task-context-strip` to one calm summary line plus disclosure while
retaining identity, recovery, branch, model, and receipt truth. Do not redesign
Settings, welcome chips, transcript content, runtime behavior, or begin the
accent sweep.

Acceptance adds the normal exact `GB-VQ-P3C-<UTC>` reply packet plus bounded
tool-use and two-child agentic layout probes authorized by Jimmy on 2026-08-15.
Each probe gets a fresh chat, a frozen marker and ceiling, typed receipt capture,
and exact-session cleanup; no probe is allowed to mutate source or configuration.

P3C accepted commit `6697530`: focused 52/0, full 896/0, clean signed
`make ship`, and installed/dist SHA-256 `2bb91f51c1c2d8d10e433b10adff2775ee058a07f654dcddb1524a44dd8ae74f`.
Light, Dark, and 1100-point narrow layouts passed with the sidebar dismissed.
The standard packet settled exactly at 16,066 tokens; the two ordered read-only
terminal calls settled at 48,877; the two-worker packet showed useful concurrency
2 and 144,349 combined parent/child tokens under the 200k ceiling. Its worker
coordination passed, but progress prose preceded the requested final token, so
exact final-only prose is retained as partial rather than upgraded.

Exact Close Session removed the three ledgered tabs and parent backends. The
CLI could not enumerate/delete the two exact child IDs; only their validated
directories were moved recoverably to Trash. Marker/session-file checks are zero,
protected OK-F remains, and two post-quit process-zero samples passed.

---

### P3D — Live activity composition (accepted 2026-08-15)

Jimmy's installed agentic packet exposed two presentation truths. The full-width
`ThreadRunSpineView` **Run / Working / Run inspector** card repeats the task strip,
live trace, Stop control, and inspector rather than adding useful evidence. At the
same time, the two workers correctly auto-opened but appeared as tiny name/status
rows in a 260-point receipt rail, visually tucked away from the work they owned.

**User-visible job**

- Remove the live transcript Run card after proving phase, current action, plan,
  Stop, recovery, and receipt truth remain reachable from the task summary, trace,
  and inspector.
- Promote current-turn active workers into a deliberate right-side live activity
  canvas with assignment, status, current action, and honest terminal state.
- Keep private reasoning and raw child output out. Preserve exact parent/child
  identity in the disclosure/settled receipt.
- At wide width, dock without crushing the transcript. At mid width, use a bounded
  overlay; at narrow width, collapse to a named/count control that never clips the
  transcript or fights the left overlay sidebar.
- Keep backend/runtime owners untouched. Phase 4 accent cleanup remains separate.

**Acceptance**

- Focused transcript-layout, inspector-projection, coordination, responsive, and
  accessibility contracts; then full `make test` and clean candidate/merged ship.
- Fresh two-worker `GB-VQ-P3D-<UTC>` packet under 200k. Capture workers running and
  settled in Light and Dark, plus wide/mid/narrow behavior and exact cleanup.

**Receipt**

- PR #107 merged as `1e11be228dba6321ba12bdd2933b9a240011a133` and carries code/test commit
  `2e1deb7e2d135a007334096e5deace53a409dc6f`. `ChatStore`, `GrokProcess`, ACP,
  routing, credentials, Settings layout, accent tokens, and structural extraction
  stayed untouched.
- The live `ThreadRunSpineView` is no longer mounted. The 340-point worker canvas
  docks at 1,180 points and above, overlays from 900..<1,180, and collapses to a
  named/count strip below 900. Worker faces show one assignment, one status, and
  only a genuinely distinct current action; the raw parent request and exact
  parent/spawn/child/model/usage/tool receipts stay behind disclosures.
- A completed child with a failed or unreconciled typed child-tool receipt renders
  **Needs Review**, never green completion. Tool titles, statuses, and settled
  output were lifted out of low-contrast Light-mode gray.
- Focused tests passed 61/61; full candidate `make ship` passed 897/897 and
  installed exact `2e1deb7`, `dirty=false`, with dist/install parity, Team
  `DD2GCQJVB4`, deep/strict signing, and no quarantine.
- Installed Computer Use proved compact four-worker settled Light, two-worker live
  and settled Dark, a full-width left sidebar beside the right worker canvas,
  responsive dock/overlay/collapse, readable tool receipts, and no duplicate live
  Run card. The successful Dark packet returned exactly `GB_VQ_P3D_DARK_OK`.
- The stop packet settled as **Stopped by you**: OMEGA was **Cancelled**, SIGMA
  was **No final report (orphaned)**, and both remained visible as needing review.
- Five paid parents consumed 16,055 + 65,740 + 146,210 + 33,288 incomplete-stop +
  97,344 = **358,637** reported tokens. The ordered-tool and four-worker packets
  obeyed their tool/coordination contracts but emitted one progress sentence before
  their exact token, so final-only prose is honestly partial.
- Exact Close Session removed five local tabs and parent backends; eight validated
  child directories moved recoverably to Trash. Active marker files are zero,
  `prompt_history.jsonl` was not edited, and protected OK-F/backend
  `019ffdad-0d4f-7f42-a429-7ac12ad8198d` remain.
- Required **Test and Build App** passed on exact PR head `34e9520`. Merged-main
  `make ship` then passed 897/897 and installed exact `1e11be2`, `dirty=false`,
  with signed/hash parity. Fresh installed UI proof kept the full screen-filling
  Dark workbench, usable left sidebar, and App receipt `Personal • main @ 1e11be22`.

---

## Phase 4 — Accent-leak sweep

**Goal:** Interactive chrome stops picking up macOS orange / brown.

**Size:** M

**Sweep, do not redesign layout**
- Replace `Color.accentColor` with `AppTheme.Palette.accent` or `.link`
- Replace raw `.orange` status with `Palette.warning` except true
  destructive/stall cases
- Prefer a `GrokProminentButtonStyle` / `.bordered` + theme tint over
  `.borderedProminent` for Add Project, auth, and Send-adjacent CTAs
- High-traffic files: `ChatView`, `ComposerViews`, `GrokChatChrome`,
  `ActivitySidebar`, `RichMessageView`, `LivePlanSpine`,
  `SlashAutocompleteView`, `PreviewPane`, `SessionDashboardPanel`,
  `SidebarView`

**Must not touch**
- Layout / AX ids from P2–P3
- `ChatStore` / ACP / routing

**Tests**
- Source grep: Views must not grow new `Color.accentColor` /
  unscoped `.borderedProminent` outside a documented allowlist
- Existing chrome/parity tests stay green

**Billable packet**
- New chat. Marker `GB-VQ-P4-<UTC>`. Exact `GB_VQ_P4_OK`.
- Prove Light + Dark: Send, add-menu, welcome/CTA chrome are not
  system-brown. Inspector dots use theme tokens.

**Exit:** grep-clean or listed allowlist; `make test` + `make ship` +
Computer Use; Gate F; Jimmy OK.

---

## Phase 5 — Cheap bundle lightening

**Goal:** Same product, slightly smaller install. Maybe a sharper Dock icon.

**Size:** S

**In**
- Proper multi-size `AppIcon.icns` instead of upscaling the 909 B
  MenuBarIcon
- One icon load path (`Assets.xcassets`). Drop duplicate loose
  `MenuBarIcon*.png` copies if the catalog already owns them
- Delete unused `workflowsStatusPill` / `showWorkflowsPill`
- Empty `Resources/Plugins/` scaffold only if it is confirmed dead and
  not the live Settings → Plugins path

**Out**
- Unbundling `agent-desktop`
- Gutting the Plugins rail without Jimmy OK
- Notarize / updater work

**Tests**
- Assert `workflowsStatusPill` is gone from `ChatView.swift`
- App still embeds AppIcon / MenuBarIcon
- Receipt records `du -sh /Applications/GrokBuild.app` before/after

**Billable packet**
- New chat. Marker `GB-VQ-P5-<UTC>`. Exact `GB_VQ_P5_OK`.
- Prove Dock/app icon still correct. Settings → App identity.
- Computer Use helper still present.

**Exit:** documented MB delta; `agent-desktop` still in the bundle;
`make ship` + Computer Use; Gate F; Jimmy OK.

---

## Phase 6 — Optional welcome extract (last / never)

Move the already-quiet welcome into
`GrokBuild/Views/WelcomeStateView.swift` (name flexible). Do **not**
extract TopBar or Composer again. No visual redesign. Update source-path
asserts only. Computer Use parity vs post-P2. No billable packet.

---

## Explicitly out of scope

- Leftover Phase 3 / C9 Phase 2 full `ChatView` decomposition
- `ChatStore` / `GrokProcess` / `ContentView` architecture splits
- Searchable model picker, generic OAuth backends, persistent `/loop`
- Updater retarget, notarize, origin publishes
- Unbundling `agent-desktop`
- Deleting protected OK-F or `019ffdad-0d4f-7f42-a429-7ac12ad8198d`
- Bundling Mermaid/KaTeX (would grow the app)

---

## Tests that will move if we change welcome or AX

| File | Pins |
|---|---|
| `WorkbenchIntentTests.swift` | Ask/Build/Review, headline, no welcome model picker |
| `CodexShellParityTests.swift` | `welcomeState`, header order, deleted chrome stays deleted |
| `ComposerPresentationContractTests.swift` | Composer AX ids, no Details shelf |
| `ResponsiveAndAccessibilityTests.swift` | Composer menus, inspector regimes |
| `ACPClientContractTests.swift` / `UsageAndRoutingTests.swift` | Welcome hides when draft is non-empty |
| `ProductCloseoutTests.swift` | LaunchSessionChoices ids |
| `SettingsTabTests.swift` | `grok-appearance-*` |

---

## Definition of done (campaign)

- [ ] P1–P5 merged (P6 optional) with Gates A–H each
- [ ] Welcome quieter; header denser; composer tighter; colors cool / `AppTheme`
- [ ] Bundle lighter without dropping `agent-desktop`
- [ ] Full ChatView split still deferred unless P6 welcome-only is done
- [ ] Protected sessions untouched; all `GB-VQ-*` test threads Gate-F cleaned
