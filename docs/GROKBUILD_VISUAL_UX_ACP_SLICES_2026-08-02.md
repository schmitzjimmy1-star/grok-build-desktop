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
