# Thread-native product refinement slices — 2026-08-09

Status: **authorized campaign; Slices 7 through 9 are merged and accepted. Slice
10 passed candidate acceptance and is in publication. Slices 11 and 12 have not
started.**

The canonical campaign in `docs/OUTSTANDING.md` remains closed through Slice 6.
This document records a fresh installed-product audit and defines the next bounded
campaign. It does not reopen, rewrite, or weaken any prior completion receipt.
Each slice below requires separate authorization, its own branch and pull request,
and full Gates A–H from `docs/OUTSTANDING.md`. Do not begin a later slice until the
current slice has merged, installed acceptance has passed, scoped test artifacts
have been removed, and merged `main` is clean and process-zero.

## Product direction

GrokBuild should feel like a durable agentic workbench whose primary record is the
thread. Browser automation remains a supported tool family, but it must not be the
default mental model, default startup cost, or primary proof surface. A long task
should make its plan, workers, exact tool calls, checkpoints, artifacts, review
state, and next action understandable in the thread without requiring the Activity
inspector to be open.

The thin-wrapper boundary remains absolute: the Grok CLI owns ACP, provider
routing, model execution, tools, subagents, sessions, and MCP protocol behavior.
GrokBuild may present, schedule, and faithfully project that state. It must not add
a second agent runtime, proxy, daemon, shadow transcript, synthetic receipt, or
fallback provider path.

## Live audit baseline

The audit used the signed installed app, not a debug build or static preview.

| Receipt | Observed value |
|---|---|
| Repository | clean `main`, matching `personal/main` |
| Source / installed build SHA | `cfb58f5f0094237cf53303bf8e828728436da672` |
| Installed version | `0.1.20`, `dirty=false` |
| Signing team | `DD2GCQJVB4` |
| Installed / dist executable SHA-256 | `0ad59fcfa0a7f61e109fcbe803d64cf9cb01ca11b4fc04e4cec4007a8962f83e` |
| Current test baseline | 706 tests, 0 failures |
| Audit model lane | native Grok 4.5, Medium |
| Clean timing marker | `GB-PRODUCT-AUDIT-COLD-20260809T155000Z` |
| Local tab / backend | `DFA60E81-3B29-4A2C-8AF2-88DE1C6CF525` / `019fe813-2abb-79f0-9a4e-cb29ebd67c95` |
| Exact requested tool | terminal: `/usr/bin/git rev-parse --short HEAD` |
| Exact terminal result | `cfb58f5` |
| Provider usage | 30,924 tokens, 2 model calls; 30,729 input, 195 output, 5,888 cached, 114 reasoning |
| Provider API duration | 4,832 ms |
| Post-audit cleanup | exact tab closed, exact backend deleted, exact marker search `Total: 0`, normal quit, owned-process count 0 |

The first exploratory pass also reproduced the first-send defect. Its exact local
tab and backend were separately closed and deleted before the clean timing run.
Automation-targeting retries caused by the installed and dist bundles sharing one
bundle identifier were excluded from product timing.

## Cold start to first billable prompt

The timed path was: launch the signed installed app from process-zero, wait for an
accessible window, open a fresh chat, paste the exact prompt, press Return once,
wait for the backend to become ready, then activate Send because the first Return
did not dispatch.

| Segment | Duration |
|---|---:|
| Cold launch invocation → accessible window | 8,936 ms |
| Accessible window → fresh New chat visible | 1,446 ms |
| Prompt typing | 1,587 ms |
| First Return → backend ready | 15,777 ms |
| Cold launch → actual billable dispatch | **27,863 ms** |
| Billable dispatch → settled visible result | 5,684 ms |
| Cold launch → settled visible result | 33,547 ms |

The 27.9-second number is the honest current answer to “startup to first billable
prompt” for this cold run. It includes user-visible launch, fresh-thread creation,
prompt entry, backend preparation, and the required second activation. It is one
measurement, not a statistically stable benchmark; Slice 7 must add repeatable
measurement before establishing release budgets.

## Oddities found

### P0 — “Return sends” is false during first-intent startup

This reproduced twice. Entering the first prompt correctly begins warm start, but
pressing Return while `connectionState == .starting` calls the send path, receives
`false`, preserves the draft, and shows “Grok is still starting…”. The Send button
is disabled during the same state. Once the backend becomes ready, nothing
dispatches automatically: the user must click Send or press Return again.

The failure is cross-layer, not cosmetic:

- `ChatStore.composerDraft` starts warming on the first non-empty draft;
- `ChatView.submit()` attempts delivery and retains the draft when rejected;
- `ChatStore.deliverPrompt` refuses sends while the process is starting;
- `ChatView` disables Send during that state; and
- the README still describes an instant first send.

The correct contract is one explicit user submit intent, exactly one eventual
billable dispatch, and an honest cancellable preparation state in between.

### P1 — Cold readiness is too slow and insufficiently decomposed

The installed window took 8.9 seconds to become accessible, followed by 15.8
seconds from first Return to backend readiness. The code already has performance
signposts for launch, layout, restore, transcript load, process spawn, ACP readiness,
continuity, first send, and first chunk, but the release ledger does not preserve a
repeatable stage-by-stage cold/warm sample. The current single wall-clock number
cannot distinguish UI restore cost from CLI discovery, spawn, ACP initialization,
session creation, model confirmation, or MCP readiness.

### P1 — Terminal-only work eagerly pays for unused GUI tool families

The probe expressly prohibited Browser and Computer Use and invoked only one
terminal tool. Even so, the backend spawned both `grokbuild-browser-mcp` and
`GrokBuildComputerUseMCP`; the settled inspector advertised both as ready. With one
live turn, observed resident memory was approximately 54 MiB for GrokBuild, 62 MiB
for the Grok CLI, 4.5 MiB for Browser MCP, and 5 MiB for Computer Use MCP.

`MCPReadinessPolicy` also applies a fixed initial readiness barrier whenever the
configured server set is non-empty. This makes Browser and Computer Use part of the
critical path even when the thread asks only for terminal or repository work.

### P1 — The thread is not yet the durable agentic truth surface

The inline trace did show the exact terminal command, success state, and result.
That is the right direction. The settled Activity inspector, however, summarized
“Tools 1 succeeded” while foregrounding two unused ready connections. For a long
run, exact tool names, durations, worker ownership, checkpoints, artifacts, and
recoverable next actions are too easy to lose in a linear transcript or a separate
diagnostics panel.

Activity should remain the deep diagnostic projection. The thread should own the
human-readable task record.

### P1 — A trivial fresh turn still costs about 31K tokens

The one-command audit used 30,924 total tokens, essentially the same order as the
prior Slice 6 fresh-turn baseline. The visible project instruction reduction did
not materially reduce total request cost. The next campaign must measure the
CLI-owned request composition rather than assuming repository instruction length
is the dominant cost.

### P2 — Resume and connection truth create avoidable launch noise

Cold launch restores an old session and can show “No active process / Resuming
saved session. Send to continue.” This is honest, but it makes readiness, restored
history, and the current task boundary compete for attention. Likewise, unused
ready connections are useful diagnostics but poor primary run status. A workbench
landing should make “continue this task,” “start a new task,” and “which tools will
start” immediately legible.

### P2 — Session actions need a stronger accessibility contract

The exact Close Session flow works, but row actions remain materially easier to
operate by pointer than through a direct named accessibility action. Long-lived
task management needs keyboard and VoiceOver parity for rename, close, pause,
resume, and review actions.

## Campaign-wide requirements

Every slice must preserve these rules:

1. **Thread first.** Put normal progress and exact work receipts in the thread;
   reserve Activity for expanded diagnostics and cross-session monitoring.
2. **One intent, one dispatch.** Never require a second submit after startup and
   never risk duplicate billable sends.
3. **Demand-driven tools.** Terminal, files, Git, MCP, Browser, Computer Use, and
   workers are peer tool families. Start only what the task or explicit attachment
   requires, subject to CLI capabilities.
4. **Exact truth.** Requested, ready, used, succeeded, failed, cancelled, and
   unavailable are distinct states. Do not infer tool use from process readiness.
5. **Durable long work.** Plans, checkpoints, worker handoffs, artifacts, review
   state, stop/resume, and next actions must survive view changes and relaunch where
   the CLI provides authoritative continuity.
6. **Progressive disclosure.** A normal task stays quiet; a multi-hour run scales
   into a navigable record instead of a wall of debug chrome.
7. **Thin wrapper.** No alternate executor, session authority, provider router,
   daemon, proxy, synthetic completion, or hidden retry lane.
8. **Bounded spend.** Each acceptance plan names prompts, routes, retry ceilings,
   token ceilings, exact cleanup targets, and a zero-owned-process exit gate.

### Execution authorization — 2026-08-09

Jimmy authorized execution through Slice 12 in strict order. Each slice has a hard
ceiling of **1,000,000 total acceptance tokens** and must include at least one
settled native Grok prompt and one settled OpenRouter prompt. These requirements
replace the smaller prompt/token ceilings written in the original plan; retries
still require a preserved failed receipt. Every slice closes its exact local tabs
and backends, checks marker/process cleanliness, commits only its scope, pushes to
`personal`, opens a ready PR, merges normally, reinstalls merged `main`, and repeats
the close gates before the next slice begins.

## Slice 7 — One-submit startup and performance ledger

### Objective

Make a first prompt behave like one durable submit intent and establish repeatable
cold/warm startup evidence before optimizing individual stages.

### Required behavior

- Pressing Return once while startup is incomplete latches the exact draft as a
  pending submit intent.
- The UI changes immediately to a clear “Preparing task…” state with stage text
  derived from real app/process state.
- The exact prompt dispatches automatically once the selected generation and model
  are confirmed ready.
- A pre-dispatch Cancel returns the exact draft to editable state and spends
  nothing. Editing after submit intent either cancels explicitly or is disabled;
  silent mutation is forbidden.
- Repeated Return/click events cannot duplicate the billable request.
- Startup failure preserves the draft and presents retry/start-new choices without
  fabricating a backend.
- README and accessibility help match the real contract.
- A repository-owned performance command records cold launch, first window, layout,
  restore, process spawn, ACP ready, session ready, model confirmed, selected MCP
  ready, dispatch, first chunk, and settled durations without secrets or prompt
  bodies.

### Likely implementation surfaces

`ChatStore`, `ChatView`, `ContentView`, `GrokProcess`,
`PerformanceInstrumentation`, `ComposerSubmissionPolicy`, and focused startup /
submission tests.

### Acceptance

- Unit/state-machine coverage for latch, cancel, failure, retry, duplicate input,
  restore, and exactly-once dispatch.
- At least three cold process-zero samples and three warm fresh-thread samples from
  the signed installed app.
- One bounded native Grok terminal prompt proving a single Return causes exactly
  one billable dispatch and exactly one terminal call.
- Campaign override: 1,000,000 total tokens; at least one native Grok and one
  OpenRouter acceptance prompt; retry only after preserving the failed receipt.
- Exact thread/backend cleanup, marker search zero, normal quit, owned-process zero.

### Exit decision

Publish measured medians and ranges. Do not set aspirational performance budgets
until the stage ledger identifies the dominant costs.

## Slice 8 — Demand-driven tool startup

### Objective

Remove Browser and Computer Use from the critical path of terminal/files/Git work
while preserving honest readiness for explicitly requested tools.

### Required behavior

- Define a deterministic requested-tool-family plan from explicit attachments,
  task mode, saved project policy, and safe user intent signals.
- Terminal/files/Git-only tasks do not spawn Browser or Computer Use helpers and do
  not wait on their readiness barrier.
- Explicit Browser or Computer Use tasks start the selected helper, expose its real
  preparing/ready/failure state, and do not dispatch until its required readiness
  contract is satisfied.
- User-configured MCP attachments remain explicit requested inputs. “Configured,”
  “requested,” “ready,” and “used” remain separate.
- If the CLI cannot attach a newly requested server to an active process, the app
  must disclose the required fresh-thread or controlled-restart boundary. It may
  not silently restart or pretend the tool attached.
- Settled summaries list used tools first and demote unused ready connections to a
  Connections detail.

### Likely implementation surfaces

`ChatStore.restartProcess`, MCP assembly/readiness policy, composer attachment
models, `GrokProcess`, Activity projection, and tool-family policy tests.

### Acceptance

- Installed terminal-only lane: exact terminal call, no Browser/Computer Use helper
  process, no unused helper readiness row.
- Installed Browser lane: one exact browser action with requested → ready → used
  attribution.
- Installed Computer Use lane: one harmless exact app-inspection action with the
  same attribution contract.
- Relaunch and selected-tool failure lanes remain honest and recoverable.
- Campaign override: 1,000,000 total tokens; at least one native Grok and one
  OpenRouter acceptance prompt; retry only after preserving the failed receipt.

## Slice 9 — Thread-native run spine

### Objective

Make the thread itself a navigable record of long agentic work.

### Required behavior

- While active, a compact run spine shows the current phase, completed/remaining
  steps, active workers, and exact current tool call.
- Tool receipts name the tool family and operation, status, duration, worker, and
  artifact/output boundary. Sensitive arguments remain redacted by existing policy.
- Parallel workers group beneath the plan step that owns them and settle into a
  compact summary rather than interleaving unreadably with prose.
- Checkpoints and recovery-required states remain visible after settlement.
- The final response links back to relevant plan steps, tool receipts, artifacts,
  tests, and review state without duplicating their full contents.
- Activity remains an expanded projection of the same authoritative events, not a
  competing ledger.

### Acceptance

- Fixture/state tests for no-tool, one-tool, sequential multi-tool, two parallel
  workers, failure, cancellation, and recovery-required outcomes.
- One installed multi-step terminal/files/Git task and one two-worker task.
- Scroll-away, narrow/wide, reduced-motion, light/dark, keyboard, and VoiceOver
  checks on the affected thread surface.
- Campaign override: 1,000,000 total tokens; at least one native Grok and one
  OpenRouter acceptance prompt; retry only after preserving the failed receipt.

## Slice 10 — Durable task controls and resume

### Objective

Let long-running work pause, stop, relaunch, and resume without losing the task
contract or making the user reverse-engineer backend state.

### Required behavior

- The thread header exposes a compact task contract: objective, current phase,
  project/worktree, branch, model receipt, requested tool families, and review
  state.
- Pause/stop/cancel/continue-as-new/resume actions use distinct honest semantics.
- Quit/relaunch restores the exact authoritative backend when resumable; otherwise
  it explains why a fresh thread is required and preserves the prior record.
- Background tasks and scheduled workflows link into their owning thread and return
  outputs to a named checkpoint.
- Worker handoffs show exact parent/child identity and terminal status.
- No UI control implies work continues after all owning processes have exited.

### Acceptance

- Installed long turn with an active worker: pause/stop behavior, quit/relaunch,
  successful resume where supported, and explicit continue-as-new where not.
- Exact process and session identity receipts before and after relaunch.
- Keyboard and VoiceOver parity for every task/session action.
- Campaign override: 1,000,000 total tokens; at least one native Grok and one
  OpenRouter acceptance prompt; retry only after preserving the failed receipt.

## Slice 11 — Artifact, review, and Git usefulness in the thread

### Objective

Turn completed agent work into an immediately reviewable product result without
leaving the thread.

### Required behavior

- A settled run groups changed files, tests, command outputs, generated artifacts,
  warnings, and unresolved decisions under the plan step that produced them.
- File and diff views use fresh Git truth from the selected canonical worktree;
  staged, unstaged, commit, branch, and last-turn scopes are explicit.
- “Last turn” attribution is evidence-based. If exact attribution is unavailable,
  the UI says so and falls back to repository truth without guessing.
- Per-file safe revert exists only with an exact preflight, selected-path boundary,
  recoverable action, and post-action Git proof.
- Commit/PR readiness is a review state, not an automatic publication permission.
- Generated artifacts open from exact local paths and retain tool/worker provenance.

### Acceptance

- Fixture coverage for clean, unstaged, staged, mixed, renamed, deleted, untracked,
  and unrelated dirty-work states.
- Installed bounded edit/test/review task in a disposable fixture repository; no
  publication.
- Safe-revert acceptance uses only disposable fixture paths and proves unrelated
  changes survive.
- Campaign override: 1,000,000 total tokens; at least one native Grok and one
  OpenRouter acceptance prompt; retry only after preserving the failed receipt.

## Slice 12 — Product polish, context cost, and campaign closeout

### Objective

Close the campaign with a quiet launch, measurable cost/performance budgets, and a
signed installed-app proof of sustained thread-native work.

### Required behavior

- Launch clearly distinguishes resume-current-task, start-new-task, and browse-old-
  tasks without foregrounding stale process warnings.
- Session actions have named keyboard and VoiceOver operations.
- Settled thread summaries foreground used tools and outputs; unused configured or
  ready connections remain discoverable but quiet.
- Capture the CLI-owned request composition by category where the CLI exposes it:
  system/instructions, skill catalog, MCP/tool schemas, project context, transcript,
  and user content. If exact category bytes/tokens are unavailable, record that
  limitation instead of estimating silently.
- Reduce avoidable fixed context and unused tool schemas without weakening system,
  project, skill, approval, or safety contracts.
- Establish release budgets from measured Slice 7/8 evidence for cold window,
  first-intent readiness, dispatch-to-first-chunk, idle/helper process count, and a
  minimal terminal turn's tokens.

### Final installed acceptance

- Three cold and three warm startup samples.
- A sustained multi-phase task using terminal, files, Git, two parallel workers,
  checkpoints, review, stop/resume, and exact artifacts in one thread.
- Separate explicit Browser and Computer Use spot lanes prove they still work but
  do not dominate the primary acceptance.
- Light/dark, narrow/wide, reduced-motion, keyboard, VoiceOver, restore, continuity,
  failure, cancellation, cleanup, and process-zero gates.
- Full test suite, clean marker searches, signed installed/dist parity, normal PR
  merge, merged-main reinstall, and Gates A–H ledger closeout.
- Campaign override: 1,000,000 total tokens; at least one native Grok and one
  OpenRouter acceptance prompt; retry only after preserving the failed receipt.

## Slice order and hard stops

Execute in strict order: **7 → 8 → 9 → 10 → 11 → 12**.

- Slice 7 fixes the broken first-intent contract and creates trustworthy timing.
- Slice 8 removes irrelevant GUI helpers from ordinary tool work.
- Slice 9 makes exact agentic activity legible in the thread.
- Slice 10 makes that work durable across time and relaunch.
- Slice 11 turns work into a reviewable product result.
- Slice 12 sets budgets and proves the whole product as one coherent system.

After each slice: scoped cleanup, full tests, `git diff --check`, signed installed
acceptance, exact receipt ledger, commit, push, ready PR, normal merge, merged-main
verification, and owned-process zero. A failed gate stops the campaign at that
slice. Do not borrow work from a later slice to make an earlier receipt look green.

## Current authorization boundary

Slices **7 → 12** are authorized in strict order, including scoped implementation,
build/install, bounded billable acceptance, exact cleanup, commit, push, ready PR,
normal merge, merged-main reinstall, and final gate verification. A slice may not
begin until the preceding slice is merged and clean.
