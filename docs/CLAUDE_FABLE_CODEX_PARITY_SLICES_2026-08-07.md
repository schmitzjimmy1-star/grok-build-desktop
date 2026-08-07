# Claude Fable handoff — Codex desktop parity, slice by slice

> Research and planning packet prepared 2026-08-07. This document authorizes no
> publication by itself. Work only in the canonical GrokBuild repository and stop after
> each accepted slice. The objective is not a themed reskin: it is a structural frontend
> replacement that preserves GrokBuild's proven runtime contracts.

## One-line objective

Replace the remaining GrokBuild workbench chrome with a faithful native SwiftUI
translation of the current Codex experience in the ChatGPT desktop app: projects and
chats on the left, one conversation in the center, review and contextual evidence where
Codex puts them, and a clean composer with no telemetry shelf bolted underneath it.

## Canonical identity — hard stop

Work only here:

`/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`

Current research baseline:

- branch: `main`
- HEAD: `8b8801689f540f1715615d51cbccb1494cd736b3`
- maintained remote: `personal` → `schmitzjimmy1-star/grok-build-desktop`
- upstream reference: `origin` → `rimusz/grok-build-desktop`
- installed bundle: `/Applications/GrokBuild.app`
- bundle identifier: `com.grokbuild.app`
- installed source stamp: Jimmy's maintained repository at the HEAD above, dirty=true
- installed executable SHA-256 at research time:
  `351e375132517fbe5a1eadd3ad0673225a01ed6c56009964ec1f7693a3f2e6ce`

The worktree already contains intentional, uncommitted frontend and model-route work.
Before each slice, record and preserve every dirty path. Do not checkout, reset, stash,
clean, or reconstruct the work from another repository. Never revive the retired
`/Users/jimmyschmitz/Documents/Grok Builf` line.

## Research authority and what it actually proves

### 1. Jimmy's supplied photographs — visual authority

These two photographs are the primary visual acceptance fixture:

- `/tmp/codex-remote-attachments/019fde3b-ae3c-7a83-ade1-9cc6fc26ac34/D43438DA-24F2-4A2E-B2CB-227465289479/1-Photo-1.jpg`
- `/tmp/codex-remote-attachments/019fde3b-ae3c-7a83-ade1-9cc6fc26ac34/D43438DA-24F2-4A2E-B2CB-227465289479/2-Photo-2.jpg`

They establish the visible target better than prose:

- one restrained left sidebar, not a second operational dashboard;
- project and task hierarchy in that sidebar;
- compact task title bar;
- a conversation-first center canvas;
- file-change/review summary inline with the conversation;
- one wide bottom composer with its settings inside the composer;
- no project telemetry row below the composer;
- a compact, top-right contextual inspector made of short sections;
- subagents summarized inside that inspector, not permanently listed in the left rail.

### 2. First-party OpenAI product and documentation — behavioral authority

OpenAI describes Codex as a command center where agent threads are organized by
projects, and where changes are reviewed in the thread. That hierarchy—not dashboard
cards—is the product model.

- [Introducing the Codex app](https://openai.com/index/introducing-the-codex-app/)
  says agents run in separate threads organized by projects and that users review an
  agent's changes in the thread.
- [ChatGPT/Codex quickstart](https://learn.chatgpt.com/docs/quickstart) defines the
  desktop entry flow as start a chat, create a project, or open a folder; Codex is the
  developer view.
- [Code review](https://learn.chatgpt.com/docs/code-review) makes Review a real Git
  pane with Unstaged, Staged, Commit, Branch, and Last turn scopes. It is not a generic
  activity card.
- [What's new](https://learn.chatgpt.com/docs/whats-new) confirms the current desktop
  model: Codex is inside the ChatGPT desktop app, Activity is opened from the sidebar
  bell, subagent status is contextual, and multi-repository Review is a dedicated pane.

### 3. GitHub clones — architecture references, not visual scripture

The following repositories were inspected through the GitHub app and shallow-cloned
for source comparison on 2026-08-07:

| Repository | Inspected commit | Valid use in this project |
|---|---|---|
| [`openai/codex`](https://github.com/openai/codex) | `4ca25a2c4e6db7db0a5a5c907055786b85ca2321` | Authoritative app-server protocol and thread/turn/review/approval boundaries. The public repo does **not** contain the proprietary desktop UI, so it cannot supply pixel values or a shell implementation. |
| [`wieslawsoltes/CodexGui`](https://github.com/wieslawsoltes/CodexGui) | `9ee551775a8e72c9543e2bad49fc64c88e34fadb` | Useful community example of separating navigation, thread list, conversation, and protocol-backed details. It is Avalonia and visibly not the current OpenAI interface; borrow separation of concerns, not styling. |
| [`lidge-jun/opencodex`](https://github.com/lidge-jun/opencodex) | local audited tag commit `246850263cd3beab99df952a9f83e5dbcd3a640f` | Provider-proxy/dashboard reference only. Its React management dashboard is the wrong visual target and must not influence this facelift. |

The official `openai/codex` app-server exposes explicit thread, turn, review, diff, and
approval operations (`thread/start`, `thread/resume`, `thread/list`, `thread/read`,
`turn/start`, `turn/interrupt`, `review/start`, diff notifications, and approval
requests). That supports a clean frontend projection. It does **not** justify rebuilding
GrokBuild on Codex app-server or replacing `grok agent stdio`.

## Current-state verdict

The August 7 pass changed colors and top-level silhouette, but it did not finish the
structural migration. Three old GrokBuild concepts still dominate the screen:

1. **Composer telemetry shelf.** `ChatView.swift` still owns
   `showComposerDetails`, `composerDetailsToggle`, `composerDetailsDisclosure`,
   `composerCenterHint`, `projectStatusRow`, context usage, receipt menus, mode, Review,
   and Activity below or inside the composer. This is the visible "Details" residue.
2. **Permanent operational sidebar lanes.** `SidebarView.swift` still receives and
   renders `activityLane`, `agentEntries`, and `connections`. The left side is therefore
   trying to be navigation, a live operations console, an agent launcher, and an MCP
   attachment manager at once.
3. **Wrong right-side information architecture.** `ActivitySidebar.swift` is a tall
   run-evidence dashboard with summary cards, recovery actions, plans, artifacts,
   workers, tools, usage, and technical details. The photograph shows a compact
   contextual inspector with short grouped sections; Git review belongs in the Review
   pane and file-change summary belongs inline in the transcript.

Additional drift to correct:

- The left command list currently invents Activity and Workflows as large primary rows;
  current Codex opens Activity from the bell and does not use a permanent Workflows row
  in the photographed hierarchy.
- The empty state's Ask / Build / Review pills are a GrokBuild invention. Keep them only
  if a side-by-side installed comparison proves they do not disturb the Codex hierarchy;
  otherwise remove them.
- A selected run can expose the same evidence in the transcript, under Details, in the
  Activity panel, and in the sidebar Activity lane. One fact should have one primary
  visible home.
- Several tests are static source assertions that enforce the leftovers. They must be
  replaced with behavior/presentation contracts, not deleted without replacement.

## Target information architecture

```text
Window
├── Left sidebar
│   ├── Product/project header + search + Activity bell
│   ├── New chat
│   ├── Review / pull-request entry when actually available
│   ├── Scheduled/background work when actually available
│   ├── Plugins
│   ├── Security
│   ├── Pinned projects/chats
│   ├── Projects with nested recent chats
│   ├── Recents
│   └── Account/settings footer
├── Conversation workspace
│   ├── Compact task header
│   ├── Transcript
│   │   ├── user and assistant turns
│   │   ├── quiet inline tool/progress disclosures
│   │   └── inline changed-files summary + Review action
│   └── Composer
│       ├── text entry
│       ├── add/context control
│       ├── permission/run-location control
│       ├── model + effort control
│       ├── voice
│       └── send/stop
├── Contextual inspector (optional overlay)
│   ├── Subagents summary
│   ├── Computer Use state/control
│   ├── Sources/context actually attached or used
│   └── compact links to deeper receipts when evidence exists
└── Review pane (optional split)
    └── real Git diff/review scopes and actions
```

Do not create dead navigation to imitate labels that GrokBuild cannot support. A missing
capability is omitted; it is never represented by a decorative row.

## Content placement contract

| Fact or action | Primary visible home | Explicitly not here |
|---|---|---|
| Projects and chats | Left sidebar | Composer telemetry shelf |
| New chat | Left sidebar | Empty-state dashboard card |
| Activity requiring attention | Bell/activity view | Permanent Activity section mixed into projects |
| Agent/subagent lifecycle | Context inspector and inline live progress | Permanent left-side Agents directory |
| Changed files | Inline completion card and Review pane | Generic Activity dashboard summary |
| Git diff/stage/revert | Review pane | Composer Details disclosure |
| Model and effort | Composer | Separate footer status row |
| Permission/full-access mode | Composer | Project status strip |
| MCP/file/context attachments | Composer add/context flow; Sources after use | Permanent Connections directory in sidebar |
| Computer Use | Context inspector when relevant; Settings for configuration | Project status strip |
| Deep model/process/continuity receipts | Contextual "Run details" sheet/disclosure | Always-visible chrome |
| Usage/context budget | Run details or model popover, only when truthful | Centered composer hint competing with input |

## Backend preservation boundary

This is a frontend replacement with selective projection cleanup. Preserve these proven
subsystems unless a slice names a narrowly scoped change:

- `GrokProcess` and the `grok agent stdio` ACP transport;
- `ChatStore` as session/runtime authority;
- session persistence, continuity ledger, lazy resume, and generation binding;
- `RunEvidenceLiveProjection` and `RunEvidenceSnapshot` factual semantics;
- worker lifecycle normalization and stale-generation rejection;
- Git diff acquisition and Preview/Review operations;
- Keychain-backed credentials and endpoint/provider policies;
- `ModelRouteContract` and generation-bound provider/model receipts;
- MCP prompt attachment semantics;
- Browser and Computer Use readiness and permission gates;
- Settings panes and configuration persistence;
- rich Markdown, Mermaid, math, tables, attachments, voice, and approvals.

Moving a fact is allowed. Weakening or deleting its evidence contract is not.

## Global gates for every slice

Every slice must:

1. Re-run the canonical identity preflight and record the dirty baseline.
2. Change only the files named for that slice unless a compile dependency is documented.
3. Add or update focused tests before changing broad static-source tests.
4. Run the focused tests, `make test`, `git diff --check`, and `make ship`.
5. Kill the stale installed process, relaunch `/Applications/GrokBuild.app`, and perform
   Computer Use acceptance against the installed app.
6. Verify the installed and `dist` executable hashes match, deep/strict signing passes
   under Team `DD2GCQJVB4`, and quarantine is absent.
7. Update `ARCHITECTURE.md`, `README.md`, and this receipt if the slice changes visible
   behavior or projection ownership.
8. Send no provider prompt unless the slice explicitly requires a bounded live runtime
   probe. UI-only acceptance must not spend tokens.
9. Do not commit, push, open a PR, merge, or publish without separate authorization.
10. Stop after the slice, leave the exact next-slice handoff, and wait for authorization.

## Slice 0 — freeze the visual and source baseline

### Objective

Turn the photographs and current installed app into deterministic acceptance criteria
before more SwiftUI is moved.

### Work

- Preserve the current dirty worktree and installed identity receipts.
- Copy the two supplied photographs into a durable, clearly attributed documentation
  fixture only if Jimmy authorizes retaining them in the repository. Otherwise reference
  their current absolute paths and create no copy.
- Capture installed screenshots for:
  - active transcript, no inspector;
  - active transcript, inspector open;
  - new chat;
  - Review pane open;
  - narrow window behavior.
- Write a compact parity matrix with rows for sidebar, task header, transcript, inline
  file summary, composer, inspector, Review pane, empty state, and resizing.
- Add source-structure tests that prove the known residue still exists. These tests are
  red-baseline inventory, not desired-state assertions.

### Files

- `docs/UI_ACCEPTANCE_MATRIX.md`
- `docs/CLAUDE_FABLE_CODEX_PARITY_SLICES_2026-08-07.md`
- new focused `Tests/GrokBuildTests/CodexShellParityTests.swift`

### Gate

The matrix names every visible mismatch and every backend owner. No production code
changes in Slice 0.

### Stop/handoff

Stop after baseline tests and screenshots. Handoff: "Slice 0 froze the exact installed
residue and target photographs. Begin Slice 1 by changing the left sidebar only; do not
touch the composer, transcript, inspector, or runtime."

## Slice 1 — rebuild the left sidebar as navigation, not operations

### Objective

Make the left side match Codex's project/chat hierarchy and remove the permanent Agents,
Connections, and inline Activity lanes.

### Frontend work

- In `SidebarView.swift`, remove rendering of:
  - `SidebarActivityRow` and overflow Activity rows;
  - the `Agents` section and `AgentHubRow`;
  - the `Connections` section and `ConnectionSidebarRow`.
- Keep the Activity bell in the product header. The bell opens the dedicated activity
  route/view; do not add a large Activity navigation row.
- Remove the primary Workflows row. Workflows remain available in Plugins/Settings and
  from the composer command flow.
- Retain only supported primary actions. Prefer:
  - New chat;
  - Review/Pull requests when Git context exists;
  - Scheduled/background work when implemented;
  - Plugins;
  - Security.
- Preserve pinned projects, project disclosure, nested sessions, recents, search, add
  project, and account/settings footer.
- Match the photographs' quiet row height, indentation, selected fill, section labels,
  and separator restraint.

### Backend/projection work

- Stop passing `activityLane`, `agentEntries`, and `connections` into `SidebarView`.
- Remove only the ContentView computations whose sole consumer was the deleted sidebar
  presentation. Keep `AgentHubProjection`, discovered agents, subagent roles, MCP
  inventory, and background activity models if other real features use them.
- Starting a session with a custom agent remains available through New chat/session
  configuration or Settings; removing a sidebar launcher must not erase explicit agent
  intent persistence.

### Tests to replace

- `SidebarActivityTests.testDelegationInspectorAndConnectionsWiring`
- `AgentsAndCapabilitiesTests.testAgentHubSidebarAndLaunchWiring`
- static assertions for `Label("Agents"...)` and `Label("Connections"...)`

Replace them with assertions that the sidebar excludes those operational sections while
agent launch intent and MCP attachment behavior remain independently tested.

### Gate

Installed app shows one clean navigation hierarchy. Worker, agent-role, and MCP backend
tests remain green. No composer or right-panel changes yet.

### Stop/handoff

"Slice 1 made the left sidebar navigation-only without deleting agent or MCP capability.
Begin Slice 2 by correcting the task header and route ownership only."

## Slice 2 — task header and workspace routing

### Objective

Make the header a compact task identity/control strip and ensure each major surface has
one route owner.

### Work

- Keep the sidebar toggle, project/folder affordance, task title, and ellipsis menu on the
  leading side.
- Keep only contextual trailing controls: Review state, inspector toggle, and Settings
  when appropriate. Avoid a second toolbar of developer telemetry.
- Define one route enum/state for session, settings, review, activity, and any session
  browser. Remove overlapping booleans where two surfaces can be open inconsistently.
- Opening Review must target the real Git `PreviewPane`/review surface.
- Opening the contextual inspector must not resize the conversation into a cramped
  permanent third column; it overlays or uses the exact intended split behavior.
- Preserve keyboard shortcuts, session identity, branch switching, and multi-project
  selection.

### Files

- `GrokBuild/ContentView.swift`
- `GrokBuild/Views/ChatView.swift`
- focused navigation tests

### Gate

Every header control opens exactly one truthful destination, survives task switching,
and returns to the same task without resetting the transcript.

### Stop/handoff

"Slice 2 established one header and one route owner per surface. Begin Slice 3 by moving
work evidence into the transcript and Review pane; do not touch the composer yet."

## Slice 3 — transcript hierarchy and inline changed-files card

### Objective

Make the conversation carry the work, including the compact edit/review summary shown in
the photographs.

### Frontend work

- Keep user and assistant prose visually dominant.
- Keep reasoning and tool activity as quiet, expandable disclosures above the answer
  they explain. Do not recreate a dashboard card for every event.
- Add one inline `ChangedFilesSummaryCard` after a settled assistant turn when the
  generation-bound Git refresh reports changes:
  - "Edited N files";
  - additions/deletions totals when known;
  - first few file names with per-file counts when known;
  - "Show N more files";
  - Review button;
  - Undo only when a safe, real undo operation exists. Never add a decorative Undo.
- Clicking Review opens the real Review pane with the appropriate default scope (prefer
  Last turn when that attribution is proven; otherwise Unstaged/current project).
- Tool failures remain visible and must not be converted into successful-looking progress.

### Backend/projection work

- Add a pure presentation projection over existing Git state and run evidence, for
  example `ChangedFilesSummaryProjection`.
- Keep repository-wide uncommitted changes distinct from files attributed to the last
  turn. Do not call every dirty file agent-edited.
- Preserve failure counts, artifacts, and settled outcome receipts for the contextual
  inspector and deep details.

### Files

- `GrokBuild/Views/ChatView.swift`
- `GrokBuild/Views/ComposerViews.swift` or a new focused view file
- `GrokBuild/Models/RunEvidenceSnapshot.swift` only if a presentation-safe accessor is
  required
- new focused changed-files presentation tests

### Gate

Installed acceptance proves a settled turn can show the compact file summary inline and
that Review opens the exact diff. Existing dirty work is not falsely attributed.

### Stop/handoff

"Slice 3 put changed-file truth in the conversation and real diffs in Review. Begin Slice
4 by replacing the composer and deleting the Details shelf."

## Slice 4 — replace the composer; delete the Details shelf

### Objective

Remove the most obvious remaining GrokBuild chrome and build the composer visible in the
Codex photographs.

### Required deletions/relocations

Delete these presentation concepts from `ChatView.swift`:

- `@State private var showComposerDetails`
- `composerDetailsToggle`
- `composerDetailsDisclosure`
- `composerDetailsAccessibilityValue`
- `composerCenterHint`
- the below-composer `projectStatusRow`
- the duplicate Activity control inside Details
- the duplicate Review control inside Details

Do not delete the underlying data or actions. Relocate them:

- model + effort → compact composer picker;
- permission/full-access or run mode → compact composer control;
- attachments, MCPs, skills, browser context → one add/context menu plus visible chips;
- voice → microphone;
- send/stop → trailing circular action;
- Review → header and inline changed-files card;
- Activity/inspector → header/bell/inspector toggle;
- context usage, branch, process generation, route receipt, usage, and continuity → Run
  details, model popover, Review header, or project menu as appropriate.

### Visual contract

- Placeholder: **Do anything**.
- One rounded surface, centered and wide, with restrained shadow and border.
- Text area occupies the top portion.
- Bottom row has only immediate authoring/run controls.
- No keyboard-hint prose in the middle.
- No second row under the composer.
- One-line idle height; grows smoothly to the existing eight-line cap.
- File/MCP/context chips appear inside the composer envelope, not as a detached toolbar.

### Tests to replace

- `ACPClientContractTests` assertions requiring `showComposerDetails` and its views
- `WorkbenchIntentTests` assertions requiring developer Details
- `ChatTranscriptLayoutTests.testComposerOrdersMCPHammerDetailsThenModel`
- `UsageAndRoutingTests` assertions that usage must live in Details

Replace these with a `ComposerPresentationContract` test suite proving authoring controls
are present, Details is absent, and telemetry remains reachable from its new truthful
homes.

### Gate

Installed app has no visible "Details" control or shelf under the composer at wide or
narrow widths. Model, permission mode, attachment, MCP, skill, voice, send, and stop all
still work.

### Stop/handoff

"Slice 4 removed the composer telemetry shelf and preserved every authoring/runtime
control in a Codex-shaped composer. Begin Slice 5 by replacing the right-side Activity
dashboard with a contextual inspector."

## Slice 5 — contextual right inspector, not an Activity dashboard

### Objective

Replace the current tall card stack with the compact grouped inspector shown in the
photographs.

### Presentation model

Introduce a pure `ContextInspectorProjection` with short optional sections:

1. **Subagents**
   - compact status icons/count (`3 done`, `2 running`, `1 failed`);
   - selected disclosure may list names and outcomes;
   - no invented workers and no duplicate left-side Agents shelf.
2. **Computer Use**
   - show only when configured, active, or recently used;
   - current state and one truthful control (for example Picture in Picture/Hide only if
     GrokBuild genuinely implements it);
   - otherwise link to the existing Computer Use settings, not a fake toggle.
3. **Sources / Context**
   - prompt attachments;
   - attached MCPs that were requested;
   - MCP/web/file sources actually evidenced by tool receipts;
   - never claim a requested MCP was used without a tool receipt.
4. **Run details**
   - one compact entry when deep evidence exists;
   - opens the existing generation-bound receipts in a sheet/disclosure.

### Explicit removals from the default panel

- summary metric grid;
- idle "Ready to work" card;
- generic changed-files list;
- full plan card stack;
- artifact and tool dashboards by default;
- always-expanded model/process/continuity/usage telemetry.

Those facts remain available in the transcript, Review pane, or Run details. Recovery
actions for continuity mismatch must remain prominently available when required; safety
beats visual parity.

### Layout contract

- top-right anchored overlay;
- approximately the compact width shown in the fixture, content-height rather than
  forced 620-point height;
- rounded opaque graphite surface, subtle border/shadow;
- short section dividers;
- opening it must not permanently crush the transcript;
- close by x, header toggle, or Escape without losing state.

### Files

- replace or refactor `GrokBuild/Views/ActivitySidebar.swift`
- new `GrokBuild/Models/ContextInspectorProjection.swift`
- `GrokBuild/Views/ChatView.swift`
- `GrokBuild/ContentView.swift` only for route/presentation ownership
- replace relevant `ActivitySidebarTests` and static source assertions

### Gate

Computer Use verifies all four states: no evidence, live subagents, settled subagents,
and continuity-recovery required. Compact parity must never hide a blocking recovery
action or turn a failed tool into success.

### Stop/handoff

"Slice 5 replaced the dashboard with a compact contextual inspector while keeping deep
receipts and recovery actions truthful. Begin Slice 6 by removing duplicate presentation
projections and dead code only."

## Slice 6 — backend projection cleanup and single ownership

### Objective

Remove the backend/view-model debris created by years of placing the same fact in several
surfaces.

### Work

- Trace every consumer of:
  - `SidebarActivityProjection`;
  - `AgentHubProjection`;
  - `RunEvidenceLiveProjection`;
  - `RunEvidenceSnapshot`;
  - `ToolPillStatus`;
  - prompt MCP inventories;
  - session usage and route receipts.
- Delete a projection only when it has zero remaining truthful consumers.
- Split giant view-owned calculations into small pure presentation models:
  - sidebar hierarchy;
  - composer state;
  - changed-files summary;
  - contextual inspector.
- Keep raw runtime/evidence models independent of SwiftUI.
- Remove stale state booleans and duplicate refresh triggers.
- Ensure project/session switching cannot leak prior task workers, sources, Git status,
  or route receipts into the selected task.
- Do not add polling to compensate for weak ownership; use the existing event-driven
  updates and bounded Git refreshes.

### Gate

Tests prove cross-session isolation, stale-generation rejection, correct sidebar
hierarchy, and one presentation owner for each visible fact. Idle CPU and memory remain
within the prior accepted envelope.

### Stop/handoff

"Slice 6 removed duplicate presentation ownership without changing runtime authority.
Begin Slice 7 for visual metrics, resizing, and accessibility only."

## Slice 7 — visual metrics, responsive behavior, and accessibility

### Objective

Polish only after the information architecture is correct.

### Work

- Tune graphite surface ladder, opacity, border strength, selected-row fill, typography,
  line height, spacing, and radii against the supplied photographs in both dark and light
  mode.
- Preserve native macOS behavior, system fonts, reduced motion, increased contrast,
  reduced transparency, and large text.
- Define responsive thresholds from available conversation width:
  - hide inspector first;
  - collapse sidebar next;
  - never compress the transcript below its readable minimum;
  - composer controls use a deliberate compact arrangement, not accidental wrapping.
- Verify keyboard focus order: sidebar → header → transcript actions → composer →
  inspector/review.
- Give every icon-only control a label, hint, state value, and minimum hit target.
- Confirm Escape closes the topmost transient surface and Cmd+, opens Settings without
  resetting the task.

### Gate

Computer Use screenshots at wide, medium, and narrow sizes match the parity matrix.
VoiceOver labels and keyboard-only navigation pass focused tests.

### Stop/handoff

"Slice 7 completed visual and accessibility polish without adding features. Begin Slice
8 for the full installed acceptance matrix only."

## Slice 8 — full installed acceptance and decision

### Objective

Prove the facelift as a complete product surface, not a collection of green unit tests.

### Acceptance flows

1. Relaunch into an existing active task.
2. Switch projects and tasks; verify exact transcript identity.
3. Start New chat and inspect the empty state.
4. Send one explicitly authorized bounded local fixture turn.
5. Observe streaming, thinking, tools, subagents, failure, and settlement.
6. Verify the inline changed-files summary and open Review.
7. Open/close the contextual inspector in live and settled states.
8. Attach a file and one MCP request; distinguish requested from actually used.
9. Stop one turn and verify the local stopped outcome.
10. Quit/relaunch and verify transcript, selected task, model intent, and layout restore.
11. Exercise light/dark, narrow/wide, reduced motion, and keyboard-only paths.

### Final gates

- full `make ship` green;
- no stale static-source tests asserting deleted chrome;
- installed/dist hash parity;
- deep/strict signing, expected TeamID, no quarantine;
- no orphan Grok, browser, Computer Use, or helper processes after quit;
- no provider/model fallback claim without a receipt;
- no commit/push/PR/publication unless separately authorized.

### Decision labels

- **ACCEPT** — target hierarchy is visibly met and all runtime/review contracts survive.
- **ACCEPT WITH FOLLOW-UP** — only bounded polish remains; list exact pixels/states.
- **REJECT SLICE** — any identity, transcript, review, approval, receipt, or recovery
  regression. Revert only the rejected slice's scoped changes; preserve all prior dirty
  work.

## Claude Fable operating rules

- Execute exactly one authorized slice per task.
- Start by quoting the slice objective and named file scope.
- Do not improve adjacent code because it looks old.
- Do not rebuild GrokBuild around Codex app-server; the GitHub clone is protocol research,
  not a runtime migration mandate.
- Do not import OpenCodex dashboard CSS, React components, colors, or management concepts.
- Do not copy community-clone code without license review and explicit need. Prefer native
  SwiftUI built from the photographs and first-party behavior contracts.
- Do not hide a safety/recovery action to win screenshot parity.
- Do not claim a source, MCP, worker, model, provider, file attribution, completion, or
  usage fact without its existing deterministic evidence.
- When a slice exposes an architectural contradiction, stop with evidence and propose the
  smallest revised slice. Do not silently widen scope.

## First handoff to paste into Claude Fable

```markdown
Work only in `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` and read `AGENTS.md`, `CANONICAL_WORKTREE.md`, `ARCHITECTURE.md`, and `docs/CLAUDE_FABLE_CODEX_PARITY_SLICES_2026-08-07.md` completely. Execute Slice 0 only: preserve the existing dirty worktree, freeze the installed visual/source baseline, and produce the parity matrix and focused red-baseline inventory tests without changing production code. Run the Slice 0 gates, leave the exact Slice 1 handoff from the plan, and do not commit, push, publish, send a provider prompt, or begin Slice 1.
```
