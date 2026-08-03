# GrokBuild visual UX and ACP slices — 2026-08-02

## Scope

This pass exercised the installed main GrokBuild app with live Grok 4.5 prompts. It inspected the visible workbench while turns were active and again after authoritative ACP settlement. The disposable stress fixture was not used. The repairs change only native presentation and the active ACP bridge; they do not rewrite Grok transcripts or durable backend logs.

Evidence rule: live projections may explain what appears to be happening, but only ACP lifecycle, worker, tool, usage, artifact, model, process-generation, and continuity receipts may settle the Activity surface.

## Prompt matrix

| # | Surface | Live result | UX finding |
|---:|---|---|---|
| 1 | Plain consumer answer | Clean sentence and three bullets; turn settled | The composer and persistent developer controls consume too much room for simple work. |
| 2 | Architecture table and focused tests | 35 tests passed | The table compressed useful ownership text into narrow columns while leaving a large empty region. |
| 3 | Two workers and test run | Both workers and 8 tests succeeded | Tool activity was useful when expanded, but Activity showed no live worker evidence and lagged visible tool completion before authoritative settlement. |
| 4 | Long Markdown reading view | Final headings, list, and block quote rendered | Streaming exposed raw Markdown markers and unstable partial layout before settlement. |
| 5 | Swift and hypothetical diff | Code blocks and Copy actions were good | A hypothetical diff polluted the Git projection: the app showed one changed file and opened Preview although the repository still had 31 real changes. |
| 6 | Failed command followed by recovery | Failure, recovery, unresolved count, and turn completion were honest | This is the strongest current surface: error state and recovery stayed distinct. |
| 7 | `ask_user_question` | The same question card appeared twice; the first click did not resume the backend | Tool-call surrogate and authoritative ACP request were projected as separate interactions. |
| 8 | Plan approval | A flat 25+ row tool stream ended in `Plan: Exit, other`; no native review card appeared | Plan-exit ownership is not bridging into the intended approval surface and can leave the turn spinning. |
| 9 | Equation, table, Mermaid | Math rendered; table sizing was poor; Mermaid remained raw text | Rich-content capability is inconsistent and needs explicit supported/fallback behavior. |
| 10 | Sourced web result | Official links were accessible and clickable | Streaming joined a preamble to a heading and rendered every ordered item as `1.`. |
| 11 | Stop generation | Partial output remained; owned process stopped; forbidden final marker never appeared | Mechanical stop is good, but the disabled composer and empty Activity state do not explain how to continue. |
| 12 | Multi-turn base | Definitions rendered and settled cleanly | Numbered content is readable when the parser receives a stable final block. |
| 13 | Same-session follow-up | Prior-turn context was correctly compressed | Continuity works; the transcript stack remains visually coherent across turns. |
| 14 | External artifact | Activity showed `/tmp/grokbuild-visual-artifact-0802.txt` as completed | Artifact evidence is useful. The visible tool receipt also exposed that Grok added `cat` and `ls` despite being told to run exactly one command—good evidence, not something the UI should hide. |
| 15 | Local file references and nested checklist | README and ARCHITECTURE links were exposed to accessibility | Nested checklist hierarchy flattened into repeated bullets, reducing scanability. |

## Ranked changes

1. **Keep authoritative interactions singular.** A user must never choose twice because a tool preview and ACP request have different transport IDs. The authoritative request ID must own the response.
2. **Separate live projection from settled evidence.** Activity should show bounded in-progress tool and worker state labeled `Live`, then atomically replace it with the settled receipt. `No settled run evidence` is technically true but operationally useless during a real run.
3. **Make Git review repository-authoritative.** Assistant prose, hypothetical diffs, and tool payloads must never change the changed-file count or open review UI. Only a fresh repository status/diff may project Git state.
4. **Repair native plan review.** `exit_plan_mode` must map to one native review card and one authoritative ACP response, not a flat protocol row plus an endless spinner.
5. **Reduce composer and chrome density.** Start compact, grow with content, and move model/MCP/branch details behind progressive disclosure for consumer work while keeping them one click away for developers.
6. **Stabilize rich text.** Hold incomplete Markdown blocks during streaming, size tables from available width and content, render Mermaid when supported, and show a clearly labeled code fallback otherwise.
7. **Give stop a recovery state.** Say `Stopped`, preserve partial output, and offer a clear `Continue in a new turn` or `Start fresh` action when the old process is intentionally dead.
8. **Preserve semantic hierarchy.** Nested lists, checklists, headings, and source blocks need deliberate indentation, spacing, and accessibility grouping.

## Slice 0 — one authoritative question card

**Status:** implemented and verified.

**Observed failure:** the `ask_user_question` tool call created a surrogate `QuestionRequest` keyed by tool-call ID. The direct ACP request then created another request keyed by the backend request ID. Both reached SwiftUI. Clicking the surrogate removed only that card; clicking the authoritative card was still required to resume the backend.

**Native ownership fix:** `QuestionRequest.merging` now deduplicates semantically identical questions inside the active session. A direct ACP request replaces a tool-derived surrogate, preserving the only ID that `GrokProcess.respondToQuestion` can answer. A later tool replay cannot replace an already authoritative request. Different questions remain independent.

**Safety:** no delay, timer, transcript rewrite, durable-log mutation, or chat-shaped workaround. This is an in-memory reducer at the ACP-to-UI boundary.

**Acceptance:** three reducer tests cover surrogate→authoritative, authoritative→surrogate, and distinct-question order. The focused ACP contract suite passed 38/38; the complete suite passed 542/542. A fresh installed-app turn displayed exactly one Consumer/Developer card, resumed after one Developer click, emitted `Developer` plus `QUESTION_DEDUP_PASS_0802`, and settled `Turn completed` with no unresolved tool failures.

**Superseded by Slice 3:** live protocol evidence established that tool-call ids are not reply-capable ACP request ids. Slice 3 therefore removes tool-derived question cards instead of semantically reconciling them with authoritative direct requests. This section remains the historical Slice 0 receipt.

## Slice 1 — calm consumer surface

**Status:** implemented; automated and installed-app acceptance recorded below.

The empty composer now starts at one accessible 36-point line and grows through eight lines with content. Mode, commands, voice, attachment, and Send remain visible. A native **Details** control progressively reveals model certainty, context usage, changed-file count, MCP readiness, project, branch, and Activity. The disclosure is presentation-only, starts closed with each fresh `ChatView`, and does not alter backend, session, or durable receipt state.

**Acceptance:** focused composer/ACP contracts passed 53/53 and the complete suite passed 543/543. The installed app opened with Details collapsed and only composer, mode, commands, Details, voice, attachment, and Send in the accessibility path. Expanding once exposed the original stable model and Activity identifiers plus context, changed files, project, branch, Browser, and Computer Use; collapsing removed them again. A 395-character draft grew the editor to several visible lines without opening Details, then was cleared without sending. Deep/strict signing passed and the packaged/installed executable SHA-256 matched at `fe00566ff82eb93269f32d1bd87f9fad2dc606b63b75dbd2daef039ef3551c28`.

## Slice 2 — live and settled evidence

**Status:** implemented and verified.

Activity now renders a separate, non-persisted `RunEvidenceLiveProjection` under an explicit **Live** badge. It exists only while the current tab, backend session, and process generation own the active turn; it reports observed plan steps, current-turn worker rows, tools, successful artifact receipts, model, MCP readiness, and generation while explicitly withholding outcome and usage. The ordered authoritative completion barrier replaces it with the existing **Settled** `RunEvidenceSnapshot`. Session-wide background tracking remains intact, but only worker rows created or changed during the active turn can enter that turn's Live or Settled evidence, so an old worker cannot be relabeled by a newer barrier. Successful tool payload JSON is retained in the receipt state but omitted from the calm visual summary; active and failed detail remains visible.

The composer pointer repair is part of this slice's interaction acceptance: a frontmost click-through AppKit tracking region owns the editor's I-beam on enter, movement, and cursor-update events and restores the standard arrow on exit. It uses no timer, SwiftUI hover animation, or cursor push/pop stack and does not intercept text-field clicks.

**Acceptance:** the redacted ACP fixture observed two current-turn workers, one artifact, five failed tools, exact tab/backend/generation ownership, and no settled snapshot before the completion barrier; after the barrier the Live projection was absent and the settled snapshot retained the exact worker, tool, artifact, plan, and usage receipts. A separate test proves a prior-turn worker remains untouched. The installed app showed **Live — Current receipts, not settled** with two active workers and one active collection tool, then atomically changed to **Settled — Authoritative run evidence** with both terminal worker receipts and `141.4K` usage after `SLICE2_LIVE_SETTLED_PASS_0802`. A final exact-binary prompt produced the visible Live accessibility value and settled with `FINAL_EXACT_LIVE_SETTLED_PASS_0802`. Focused Activity tests passed 9/9; the complete suite passed 545/545. Deep/strict signing passed and packaged/installed executable SHA-256 matched at `f41d69a204258a4459bd5764540d97df34fb5a4dc806f0b33e48038bb39b30d3`.

## Slice 3 — interaction parity

**Status:** implemented; automated and installed-app acceptance recorded below.

Question, permission, and plan actions now require the exact active backend-session/request identity still pending in `ChatStore`. Direct interaction requests for another backend are rejected by `GrokProcess`. Replays of the same request update one card. Distinct authoritative question ids remain distinct even when their content matches, and ask-shaped tool calls remain explanatory activity instead of reply-capable cards carrying an invalid tool-call id.

The live protocol probe against grok 0.2.118 proved that plan exit arrives as `_x.ai/exit_plan_mode` with a JSON-RPC id and blocks until the client returns `{"outcome":"approved"}`. Before the repair, one click correctly answered that request but immediately exposed **Queue (1)**; after the original turn continued, the transcript gained a synthetic `You: [Plan approved]` and launched a second agent turn. `respondToExitPlan` now writes only the authoritative JSON-RPC result. The plan card says **Approve & continue**, exposes stable accessibility identifiers, and no longer offers an optional comment field whose text had no ACP response field.

**Safety:** interaction state is an in-memory projection only. There is no timer, transcript rewrite, durable Grok-log mutation, tool-id promotion, or synthetic chat marker.

**Acceptance:** identity/replay reducers and a fake-ACP end-to-end test prove that one plan decision produces one approval response, one `session/prompt` total, and no `[Plan approved]` content. The focused ACP contract suite passed 41/41 and the complete suite passed 548/548. Deep/strict signing passed, and packaged/installed executable SHA-256 matched at `c8ec6d656d2a1f8d8092c95027b71aaa57a7994296db967b5956594a416949cc`.

After explicitly terminating the pre-install process and launching `/Applications/GrokBuild.app`, the exact installed tree ran as PID 39063 and rendered one accessible plan review card with **Approve & continue** and no comment field. One click removed the card, returned the same turn to Agent mode without a **Queue (1)** badge, and settled with `SLICE3_FINAL_EXACT_TREE_PASS_0802`, **Turn completed**, and no unresolved tool failures. The visible transcript contained one user prompt and no synthetic approval row. Read-only inspection of backend session `019fc510-8eb3-7fe0-8b31-d1b687992426` confirmed one `prompt_index` user record, zero `[Plan approved]` records, one `turn_completed` receipt, `stop_reason: end_turn`, 49,295 total tokens, three model calls, and three model turns. Three other `user`-typed records were Grok-owned `project_instructions` or `system_reminder` context, not extra prompts. No durable log was edited.

## Slice 4 — readable technical output

**Status:** implemented and verified.

Tables now size from the actual transcript viewport with bounded content-aware columns; when the data cannot fit at readable widths, the table alone scrolls horizontally. During a live ACP stream, incomplete code fences and table blocks are withheld behind an explicit **Formatting code…** or **Formatting table…** label, so unfinished raw syntax is not passed off as final output. This is an in-memory presentation split only: the exact message body continues to be the source of truth and no Grok transcript or durable backend log is rewritten. Final code blocks retain Copy, while Mermaid remains either a rendered WebKit diagram or a clearly labeled, copyable Mermaid source block after renderer failure.

**Acceptance (2026-08-02):** focused `MarkdownBlockParserTests` passed **13/13**; complete `make test` passed **550 tests, 0 failures**. The exact signed package and `/Applications/GrokBuild.app` executable match at SHA-256 `183785ec71869c6ab7485bd65282c24dc42e3d47715aecb895847be23e5cc3a8`; the installed receipt names `https://github.com/schmitzjimmy1-star/grok-build-desktop`, `codex/activity-parity-slice-0`, `a9bc1845ec07b40301874f66cfb7ac6a84e15965`, dirty `true`, and Team `DD2GCQJVB4`. Deep/strict code-sign verification passed. Live native Computer Use selected an existing technical transcript in the installed app and exposed a semantic **Table, 3 columns, 4 data rows** accessibility surface with readable ownership rows; screenshot evidence showed the adaptive table in the centered workbench. The app quit cleanly and exact relaunch restored a readable saved transcript and the continuity-blocked composer. No prompt was submitted, provider run started, or Grok durable log rewritten for this slice.

## Slice 5 — Git truth boundary

Refresh changed-file count and review content only from the selected workspace's Git status and diff. Tag assistant-provided diffs as examples. Never let transcript content or tool output mutate repository review state.

**Acceptance (2026-08-02):** Assistant `diff` and `patch` fences now render as **EXAMPLE DIFF** code blocks and retain only Copy behavior; they cannot open Preview, affect the changed-file count, or become an apply input. The review pane uses only `GitService.changedFiles` and `GitService.diffForChangedFile` from the selected workspace at bounded prompt boundaries, and its footer explicitly says **Repository changes from Git**. Focused boundary coverage passed (example labeling, source-contract review authority, and an isolated temporary-Git fixture); complete `make test` passed **550 tests, 0 failures**. The exact signed package and `/Applications/GrokBuild.app` executable match at SHA-256 `370937420a863251eae47695d08ddf7a834a578dddc846ef7f4926647bbe3a4f`; the installed receipt names `https://github.com/schmitzjimmy1-star/grok-build-desktop`, `codex/activity-parity-slice-0`, `a9bc1845ec07b40301874f66cfb7ac6a84e15965`, dirty `true`, and Team `DD2GCQJVB4`; deep/strict code-sign verification passed. Live native Computer Use quit the older process, launched the installed bundle, then exposed matching **43 changed files** in Details and Preview with **Repository changes from Git** visibly attached to the active `grok-build-desktop` workspace. The restored saved transcript stayed inert and its composer was continuity-blocked; no provider prompt was submitted, no Git operation was invoked, and no Grok durable log was rewritten.

## Slice 6 — interruption and continuity

After Stop, present a settled local outcome that distinguishes `user stopped` from backend failure, then expose the valid next action. Resume only with a continuity receipt bound to the same backend session and process generation; otherwise start a fresh run and say so.

**Acceptance (2026-08-02):** Stop now records the local terminal outcome as **Stopped by you**, rather than a backend failure, with an explicit next action: reverify an exact tab/backend/process-generation continuity receipt before reconnecting, or start a fresh, ledgered run when that receipt is absent or mismatched. The restart boundary independently consumes the fresh-start guard, so workspace selection or another restart path cannot bypass it. Focused coverage passed for the settled stop outcome and exact receipt matching, and `ActivitySidebarTests` passed **9/9**; complete `make test` passed **552 tests, 0 failures**. The exact signed package and `/Applications/GrokBuild.app` executable match at SHA-256 `baf8263c0beb7c68d6e743de59a4b00f1c7da031151f8b9a09dda69b4b7743fa`; the installed receipt names `https://github.com/schmitzjimmy1-star/grok-build-desktop`, `codex/activity-parity-slice-0`, `13fb5fad9ad4f604e183cb5f69132d7ea829033f`, dirty `true`, and Team `DD2GCQJVB4`; deep/strict code-sign verification passed. Native Computer Use quit and relaunched the installed bundle, restored the existing workbench transcript, and exposed the native composer as **Send blocked by conversation continuity**, with the active workspace and Details control visible. No provider prompt was submitted and no actual Stop was invoked because that would add or alter a Grok durable log; the exact Stop-state projection is covered by the deterministic lifecycle tests instead.

## Slice 7 — semantic reading hierarchy

**Status:** implemented; final automated and installed-app acceptance is recorded below.

Settled Markdown now preserves H1–H6 heading levels, nested list indentation, authored ordered-list numbers, and checked/unchecked task state in a native `MarkdownListItem` presentation model. Nested rows receive bounded visual indentation and exact level/state accessibility labels, while link-only list groups identify themselves as source lists and keep their native link children. The parser strips only Markdown marker syntax for presentation; the exact `Message` body, file-backed transcript, and Grok backend logs remain unchanged.

**Acceptance (2026-08-02):** `swift test --filter MarkdownBlockParserTests` passed 15/15 and `make test` passed 554/554 in 22.326 seconds; `git diff --check` was clean. `make signed` and `make install` used `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)` (team `DD2GCQJVB4`). The installed personal-channel app is stamped branch `codex/activity-parity-slice-0`, commit `352080f72b35d832cbc7ece669baafcd1f9c1a0e`, `dirty=true`, and repo `https://github.com/schmitzjimmy1-star/grok-build-desktop`; both dist and installed executables hash to `5dc4d12750519fac1133eea4923e1228bb3c23faa2a10a67897e87677b72af99`, and both bundles pass `codesign --verify --deep --strict`.

Native Computer Use against `/Applications/GrokBuild.app` showed the installed renderer exposing a settled response as `List, 3 items` (`grok-markdown-list`) with three child rows labeled `Level 1, bullet: …` (`grok-markdown-list-item-0` through `-2`), matching visible native bullet indentation. A clean quit/relaunch restored another saved response through the same installed binary and again exposed the native list container. The exact nested README/ARCHITECTURE checklist fixture is covered by the focused tests with depths `[0, 1, 0, 1]`, checked/unchecked state, H1–H6 semantics, and source-list labeling. The dashboard's older-session rows remained inert during acceptance, so the older Pass 15 transcript was not claimed as reopened visual proof.

No provider prompt was sent. Before/after SHA-256 remained `57c6c2ff2acbae9b34b38fe3877608cc3768294403e20c8550dc16af23c29e27` for the local saved transcript and `1ad069c99e21281bffa7281f0c73cc1dc32dc57786a36f627054de8887157f18` for Grok's durable `chat_history.jsonl`; neither was rewritten. After startup settled, the installed app was at 0.0% CPU with zero child processes. The recoverable pre-install bundle is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-visual-slice-7-20260802-2040.app`.

## Ten-prompt consumer/developer study — 2026-08-02

Ten fresh installed-app sessions exercised casual guidance, current sourced research, local-project explanation, one authoritative question, structured comparison, architecture orientation, a focused test loop, parallel subagents, native plan review, and external-artifact/Git truth. Conservative tracked usage was **1,752,616 / 2,000,000 tokens**, leaving **247,384** unused; no further provider call is authorized by this study.

| Prompt | Tracked tokens | What worked | Finding that earns a slice |
|---:|---:|---|---|
| 1 | 15,763 | Calm answer, headings, numbered variations, next action | A simple answer still lives inside project-first starter copy, session clutter, Git counts, and developer terminology. |
| 2 | 55,451 | Current web result settled with official links, uncertainty, and honest tool receipts | Useful progress is hidden behind Details/Activity; streaming still briefly presents a dense tool-and-raw-text story. |
| 3 | 36,686 | README read, native local link, plain-language explanation | Intent such as “checklist” is not always reflected by model-authored Markdown, so user actions need stronger native affordances than prose alone. |
| 4 | 31,402 | Exactly one authoritative three-choice question resumed the same turn | Guided choices work beautifully and should become a reusable consumer pattern rather than a special-case tool surface. |
| 5 | 15,795 | New hierarchy renderer exposed a four-item checklist at depths `[0, 1, 1, 0]` | The five-column table clipped its useful final column without an obvious overflow or alternate reading mode. |
| 6 | 84,615 | Six read-only tools produced an accurate architecture map and exact diagnostic command | Developer orientation is strong, but tool progress and the final answer are visually disconnected; prose also joined directly to a heading. |
| 7 | 32,307 | One visible command receipt, 15 focused tests, clear regression risk | Results need native actions such as rerun, copy command, open test source, and keep-as-receipt without turning the transcript into toolbar soup. |
| 8 | 1,107,977 | Activity correctly showed two named parallel workers and their terminal receipts | One worker ran 2.3 minutes / 51 tools and the other 3.9 minutes / 60 tools; the parent waited silently and live usage was unavailable. Stop protected the budget but the stopped receipt withheld tokens. |
| 9 | 340,874 | Native plan review exposed four detailed steps, acceptance, risks, and Approve/Reject/Cancel | The card sprawled across hundreds of accessibility rows; Cancel removed the plan and surfaced one failed tool instead of preserving a cancelled decision record. |
| 10 | 31,746 | External `/tmp` artifact remained separate from the five-file Git projection | Artifact and Git truth are correct but deserve direct reveal/copy/reuse actions after settlement. |

## Slice 8 — deterministic session navigation

**Status:** implemented; final automated and installed-app acceptance is recorded below.

Make every dashboard row a full-width, keyboard- and VoiceOver-activatable control with a stable identifier and explicit selected state. Selection must dismiss once, target one existing local tab, hydrate its transcript exactly once, and never silently no-op, bounce the scroll position, create a duplicate tab, or start a backend merely because the user looked at saved work. Browse Sessions remains historical-backend discovery; the dashboard remains the live local-tab switcher.

**Gate:** with at least twelve live tabs, activate the oldest idle tab by accessibility identifier and by keyboard. The sheet dismisses once, the correct transcript/title appears, the sidebar selection moves, the scroll position does not bounce, no duplicate local tab or Grok child appears, and transcript/backend-log hashes are unchanged by selection.

**Acceptance (2026-08-02):** The dashboard now uses one lazy native scroll stack rather than `List` row-selection machinery. All 95 installed local-tab buttons exposed exact `grok-session-dashboard-row-{local UUID}` identifiers, status/model/workspace labels, a selected trait, full-width hit regions, and native Tab/Space activation. The presenting `ContentView` owns the single dismissal; a generation token rejects stale A → B → A hydration; selection performs no process start, while `ChatStore.deliverPrompt` retains the existing continuity-gated lazy resume on a real submission. The four-process LRU cap is re-enforced when an active store receives an authoritative backend ID.

Native Computer Use clicked the bottom-most stable row `grok-session-dashboard-row-ff8ba9fa-470c-42bc-836b-138bcfdce661` after `AXScrollToBottom`, dismissed the sheet once, moved the sidebar selection, and restored the exact `grokbuild-installed-terminal-pass` transcript without a visible bounce. A separate keyboard pass tabbed from selected row `5dc250e4-dfce-4f9e-8f0e-99b72cbffe57` to `0050b36f-53bf-4bd7-97a7-9afb6a30d921` and activated it with Space, restoring the exact `FINAL GB_MAIN_ACP_ACCEPTANCE_0802` transcript. Across click, keyboard, quit, and relaunch, SHA-256 manifests for **205 local transcript files** and **256 Grok `chat_history.jsonl` files** stayed byte-identical. The three focused dashboard tests passed 3/3; the complete suite passed **557/557** in 21.868 seconds; `git diff --check` was clean.

`make install` rebuilt and signed with `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)` (Team `DD2GCQJVB4`). The final dist and `/Applications/GrokBuild.app` executables both hash to `10c0903893126f3456332cfae5f1d0ee81c93532b1d666598402f997807c5006`; both bundles pass deep/strict verification and carry personal channel, `schmitzjimmy1-star/grok-build-desktop`, branch `codex/activity-parity-slice-0`, commit `352080f72b35d832cbc7ece669baafcd1f9c1a0e`, dirty `true`. A final launch of that exact hash independently exposed the identified native buttons and reopened `0050b36f-53bf-4bd7-97a7-9afb6a30d921` into the matching transcript/sidebar state. Settled installed state was 0.0% CPU with zero child processes and no provider submission. The recoverable pre-install bundle is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-session-slice-8-20260802-2132.app`.

## Slice 9 — quiet workbench focus

Start new work with three plain-language intents—**Ask**, **Build**, and **Review**—rather than assuming every person understands architecture/test vocabulary. After Send, place the answer and its next action first; keep project navigation, model, Git, MCP, and receipt power one click away in the unchanged developer Details surface. This is progressive disclosure, not a generic-chatbot pivot or feature removal.

**Gate:** a first-time keyboard/VoiceOver user can start a useful project-grounded request without decoding CLI/Git language, while an expert reaches model, branch/worktree, changed files, MCP readiness, Activity, and raw receipts in one deliberate expansion.

**Acceptance (2026-08-02):** The fresh-work surface now offers exactly three plain-language intents—**Ask**, **Build**, and **Review**—with outcome descriptions and ordinary editable drafts. Choosing an intent only fills the composer; it does not send, start a provider process, or conceal the draft. A compact model menu is available before the first send, while Agent mode, the full model/reasoning control, context, changed files, branch/worktree, MCP readiness, and Activity remain one deliberate **Details** expansion away. Existing model-routing and effective-readback authority are reused rather than duplicated.

Native installed-app acceptance clicked **Ask**, opened the starter model menu, selected `gpt-5.6-terra`, observed the truthful saved/no-process receipt, restored Grok 4.5, and cleared the draft without a provider submission. A keyboard-only pass reached **Review** with Shift-Tab/Space, filled its editable draft, cleared it, then reached and opened the starter model menu. One Details click exposed Agent mode, the full model/reasoning selector, context, changed files, Activity, branch/worktree, Browser Tools, and Computer Use. Accessibility exposed stable intent labels/hints, `grok-starter-model-selector`, `grok-message-composer`, and the Details disclosure state.

After that send-free acceptance, Jimmy independently submitted `what's the weather like in chicago tomorrow` with Terra. GrokBuild reported **Live model `gpt-5.6-terra`, confirmed by the current process** and **Turn completed / No unresolved tool failures**. Exact backend receipts agreed: `turn_started` on `gpt-5.6-terra`, `end_turn`, 23,677 total tokens, two model calls, and one completed web search. That user-authored session increased the durable baseline to 207 transcript files and 257 Grok `chat_history.jsonl` files; the final packaging pass verifies those post-turn files byte-for-byte rather than rewriting or excluding them.

Focused `WorkbenchIntentTests` passed **5/5** and the complete suite passed **557/557** in 21.713 seconds. `make install` produced matching dist/install executable SHA-256 `e7b1222605d16f1071baf35cb4d98bfb04d1eb9a31d5e481fd2d8b635760d5db`; both bundles passed deep/strict verification under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)` / Team `DD2GCQJVB4`. The installed stamp names personal repository `schmitzjimmy1-star/grok-build-desktop`, branch `main`, commit `e1f0ed4b7444511ddc16878ef7829eb34fb37928`, dirty `true`.

Exact installed quit/relaunch restored Jimmy's weather transcript and preserved its Terra backend receipts, then a send-free New Session exposed the complete Slice 9 welcome again. The disconnected restored row inherited the project's next-turn Grok 4.5 default and correctly blocked Send until continuity reconciliation; that label is not retroactive authority for the completed turn. Five settled samples were 0.0% CPU at 122,528 KB RSS with zero owned children. All 207 post-turn transcript files and 257 Grok histories remained byte-identical through final install/relaunch. The immediate recoverable predecessor is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice9-20260802-2208.app`.

## Slice 10 — glanceable live progress

Project one compact, answer-adjacent live status line for meaningful work: current phase, active workers, active tool, elapsed time, and budget status. Expanding it opens the existing generation-bound Activity truth; collapsing it never hides a question, plan decision, failure, or budget warning. Settled evidence still replaces live projection atomically.

**Gate:** the parallel fixture is understandable without opening Details, then expands to the exact same workers/tools/receipts already owned by Activity; no outcome or usage is fabricated before settlement.

## Slice 11 — adaptive result surfaces

Give wide tables an obvious horizontal affordance plus an alternate stacked-card reading mode, retain full exact table text for copy/accessibility, and prevent preamble text from welding itself to the next heading. Preserve native nested lists, source links, code, Mermaid fallback, and developer-grade exactness.

**Gate:** the five-column rainy-day comparison is fully readable at the minimum window width by sight, keyboard, and VoiceOver without losing a cell; the same fixture still copies as an exact Markdown table.

## Slice 12 — concise, durable plan decisions

Render plan review summary-first: objective, affected areas, risk, tests, and estimated scope before collapsed step detail. Approve, Reject, and Cancel remain one authoritative ACP response each; rejected/cancelled plans stay in the transcript as durable decision records and are not mislabeled as failed tools. Raw plan text remains available for developers.

**Gate:** the four-step session-navigation plan opens to a bounded summary, exposes full detail on demand, and remains visibly labelled **Cancelled** after Cancel with zero edits and no unresolved-tool fiction.

## Slice 13 — run budgets and worker control

Add per-run token, time, model-call, tool-call, and worker ceilings with a conservative preflight estimate, live consumption when the backend reports it, and explicit **Stop worker** / **Stop all** controls. When live usage is unavailable, show that fact and enforce local elapsed/tool ceilings instead of presenting limitless animation. Multi-agent power stays intact; runaway work becomes bounded and inspectable.

Also single-flight model-catalog discovery across restored tab shells. Final Slice 8 acceptance observed 95 transient `grok models` child probes at launch; they settled to zero without provider calls, but one shared catalog lookup should serve every prepared tab instead of multiplying startup work by session count.

**Gate:** the two-worker diagnosis cannot exceed its configured ceiling unnoticed; the UI warns before the boundary, can stop one worker without killing the other, and settles with known usage or an explicit unavailable/upper-bound receipt.

## Slice 14 — actionable results and artifacts

Attach restrained native actions to settled developer results: rerun/copy a command, open the named test/source, reveal or copy an artifact path, and promote a successful result into a follow-up draft. Actions must derive from successful receipts and keep external artifacts, repository changes, hypothetical code, and assistant prose in separate authorities.

**Gate:** the focused-test and `/tmp` artifact fixtures expose the correct actions; no action mutates Git without a separate user decision, and an external artifact never enters Files in review.

## Release gates

- All request/response cards are one-to-one with authoritative ACP request identity.
- Activity never presents live projections as settled receipts.
- Worker, usage, artifact, model, generation, and continuity evidence reject stale or mismatched ownership.
- Git review matches a fresh repository status/diff after hypothetical-diff prompts.
- Plan approval resumes after one decision and settles normally.
- Stop leaves an understandable, accessible next action.
- VoiceOver exposes list hierarchy, link destinations, control purpose, and live-versus-settled status.
- Installed and packaged executables match; the installed build identity names the canonical personal repository, branch, HEAD, and dirty state.

## Non-goals

No disposable sidecar, no backend-log rewriting, no timer-based settlement, no fabricated worker state, no publication, and no attempt to make GrokBuild look like a generic chatbot.
