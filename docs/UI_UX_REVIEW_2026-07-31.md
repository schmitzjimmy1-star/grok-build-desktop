# GrokBuild product UI/UX stress review — 2026-07-31

## Executive assessment

GrokBuild now behaves like a credible native macOS project workbench rather than a thin terminal transcript wearing a SwiftUI coat. It is not a chatbot product. The core loop is choose a project and durable build session, confirm branch/model/agent/capabilities, direct work, observe tools, review results or diffs, leave, return, and resume. That loop survived long streaming output, rich artifacts, tool activity, Settings navigation, sidebar changes, stop/recovery, and full application relaunches.

The follow-up feature review in [`GROKBUILD_FEATURE_REVIEW_2026-07-31.md`](GROKBUILD_FEATURE_REVIEW_2026-07-31.md) evaluates projects, git/worktrees, agents, workflows, tasks, MCPs, skills, plugins, automation, permissions, and review authority directly. This document retains the deeper rendering and stress evidence without pretending response quality is the whole product.

The most important result of this review is not cosmetic. A restored GPT or DeepSeek conversation can no longer silently become a new Grok conversation after quit. The defect crossed three product boundaries at once: session identity, model persistence, and transcript truth. Its root cause was teardown persisting the live ACP session ID after `GrokProcess.shutdown()` had cleared it. The selected record was correct before Command-Q and rewritten with `grokSessionID: null` during termination. The repaired policy preserves a non-empty durable receipt, ignores teardown's transient `nil`, reasserts the receipt when binding a restored tab, and centrally resolves it for any populated-tab restart.

The second major outcome is that transcript following is now reliable across both content growth and view reconstruction. Streaming/final layout changes get settled retries, and a recreated `ChatView` schedules the same bottom-follow work on appearance. Long-answer markers remained above the composer after Settings → Session and after quit/relaunch.

The follow-up repair resolves the original client defects identified here: permission choices now name the CLI's real semantics, links have native visual and accessibility affordances, tables and equations expose spoken structure, restored-session startup is named, drafts survive failed/racing submission, build-agent attribution is neutral, and session metadata/actions are discoverable. The later hostile workbench pass exposed four cross-boundary defects in transcript settlement, effective permission handling, reload identity, and Computer Use close semantics. UXR-12 through UXR-15 are now fixed with deterministic fixtures and installed-app provider/tool acceptance.

## Scope and evidence model

The pass used the signed app at `/Applications/GrokBuild.app`, not a SwiftUI preview. It mixed fresh one-prompt sessions, multi-turn sessions, Settings round trips, tab/sidebar changes, stop/recovery, and quit/relaunch. Grok 4.5, `gpt-5.6-terra`, and `deepseek/deepseek-v4-flash-0731` were exercised independently. Backend session files under `~/.grok/sessions/` were used to distinguish rendered labels from actual provider/model identity.

The matrix intentionally combined requirements instead of spending model calls on a theatrical Cartesian product. GPT supplied the large one-shot rich reply and the hardest relaunch race. DeepSeek supplied the longest silent-reasoning and mixed-math path. Grok supplied progressive output, Stop recovery, terminal/web tools, links, and tool rows. Short, normal, long, correction/follow-up, and interrupted-turn shapes were all represented.

Final automated receipt after the hostile-stress repair: `make test` ran **409 tests with 0 failures**. The final installed executable SHA-256 is `48ca90bd7beaa31b8a2a82fab048fb95d49503a30a6f1893be64c13475e863c8`; deep/strict signing passed for the app and native helpers under Team `DD2GCQJVB4`, the installed executable matches `dist/GrokBuild.app` byte-for-byte, and quarantine is absent. The retained signed rollback checkpoints are `/Users/jimmyschmitz/.Trash/GrokBuild-pre-stress-error-repair-20260731-223704.app`, `/Users/jimmyschmitz/.Trash/GrokBuild-pre-final-persistence-20260731-230355.app`, and `/Users/jimmyschmitz/.Trash/GrokBuild-pre-final-repair-20260731-233408.app`; fourteen superseded intermediates were permanently retired during closeout cleanup. Grok CLI receipt: `grok 0.2.118 (1e1687c1cf6a) [stable]`.

The final hostile feature supplement used a disposable Swift package and local browser target at `/private/tmp/grokbuild-stress-20260731.hQwFzd`. The package's intentionally broken arithmetic failed before repair and passed **2 tests with 0 failures** afterward. The rebuilt installed binary was exercised through real terminal, subagent, browser, Computer Use, attachment, model-routing, permission-mode, settings, reload, relaunch, and persistence paths.

## Exhaustive agentic workbench supplement

This supplement treated GrokBuild as an execution and review environment, not a chatbot. The point was to make providers operate the product's machinery: repair code, delegate independent work, drive a deterministic webpage, automate a native application, inspect attachments, surface tool receipts, stop a stuck run, and survive navigation and relaunch.

| Lane | Installed-app evidence | Judgment |
|---|---|---|
| Grok 4.5 agentic repair | Ran the failing Swift tests, identified and edited the one-line arithmetic defect, reran 2/2 green, inspected the diff, and emitted `GROK-AGENTIC-REPAIR-OK-0731` | **Pass** — terminal, edit, test, diff, final rendering, Settings restoration, and relaunch persistence |
| Grok subagents | Spawned named `explore` and `general-purpose` workers concurrently; backend history contains `SUBAGENT-STRESS-OK-0731` | **Product fail (P1)** — concurrent raw output interleaved visibly and the clean final synthesis never appeared, including after relaunch |
| GPT 5.6 Terra Browser Tools | Opened the deterministic local page, entered `DIRECT-GPT-BROWSER-0731`, clicked Render, verified the heading/result, saved a screenshot, and wrote `DIRECT-GPT-BROWSER-OK-0731` to backend history | **Function pass / transcript fail (P1)** — browser actions worked, but the complete final answer never rendered or restored |
| OpenRouter DeepSeek rich result | Ran `swift test`, returned exactly 20 findings plus code/math/table content, and visibly ended at `OPENROUTER-DEEPSEEK-RICH-OK-0731` | **Pass** — rich rendering, bottom-follow, Settings restoration, relaunch persistence, and model persistence |
| Kimi K3 Computer Use | After Accessibility and Screen Recording were re-authorized, discovered Calculator, targeted its real window, pressed 7 × 6 =, and verified the value 42 from a fresh accessibility snapshot | **Partial pass (P2)** — native perception and clicking worked; `cmd+q` was policy-blocked while the exposed schema offered no force option, and the menu fallback could not disambiguate multiple windows |
| Grok attachment | Attached only `README.md`, read it without terminal/edit tools, correctly rejected the prompt's nonexistent Contents heading, and visibly emitted `ATTACHMENT-GROK-OK-0731` | **Pass** — native picker, attachment chip/removal, file-read receipt, grounded response, and marker rendering |
| Stop and recovery | Stopped the stuck Kimi turn; composer immediately returned to a usable Send state | **Pass** — interruption is immediate and recoverable even when a provider/tool path stalls |
| Permission modes | The effective card said `Current launch policy: Always approve`, while Settings said tool prompts are skipped; approval cards still appeared for terminal and tool actions | **Product fail (P1)** — displayed authority and runtime interruption behavior disagree |
| Model persistence | Grok, GPT, DeepSeek, and Kimi each retained their selector across Settings and relaunch; fresh sessions defaulted to Grok | **Pass with caveat** — per-session model persistence is sound, but a configuration reload can split backend/session history |
| Idle performance | Installed app and all live grok/helper children sampled at 0.0% CPU; the app used about 78 MB with five threads | **Pass** — no recurrence of the silent-reasoning core pin |

The browser lane also exposed two provider/tool-contract mismatches (`browser_eval_js` attempted an unsupported `js` command and `browser_wait_for_load` omitted required wait arguments). The agent recovered and completed the task, so these are capability-discovery/schema-quality findings rather than evidence that Browser Tools cannot work.

## Fixed in this pass

| Area | Defect and evidence | Repair | Accepted result |
|---|---|---|---|
| Transcript restoration | Settings → Session recreated a populated `ChatView` at the top | Schedule settled bottom-follow from `ChatView.onAppear` | Existing and new unique bottom markers remained visible after Settings → Session and quit/relaunch |
| Late rich layout | One-shot GPT/DeepSeek output could grow after the final ACP chunk | Retry final bottom scrolls across roughly 800 ms | GPT, DeepSeek, and Grok bottom markers settled immediately above the composer |
| Session identity | Restored GPT transcript sent its next prompt to a new Grok backend | Preserve non-empty backend IDs through teardown; rebind and centrally resolve the saved ID | GPT base and follow-up both remained in backend `019fbae7-a0ce-7620-a7b1-0471a87f8698`, both recorded `gpt-5.6-terra` |
| Model persistence | Composer could initially say GPT, then flip to Grok on the next turn | Same identity repair; model now follows the resumed backend instead of a replacement session | GPT stayed GPT/128K; DeepSeek stayed DeepSeek/200K through Settings and quit/relaunch |
| Updater freshness | A kept-alive App pane could keep showing CLI 0.2.117 after the updater had installed 0.2.118 | Observe `.grokBuildUpdateStateChanged` and invalidate the pane's cached receipt | Settings → App showed Installed/Latest 0.2.118; source contract covers live notification refresh |
| Streaming CPU | Periodic transcript invalidation could hold a core near 100% while a model was silent | Static working/Stop glyphs, buffered text, bounded scroll work | Silent DeepSeek reasoning and settled idle sampled at 0%; no sustained runaway loop returned |
| Math/Markdown | Standard display delimiters, one-column tables, and inline math inside table cells were unreliable | Parse `\[...\]`, preserve inline math in native blocks, add one-column table recognition and dark KaTeX styling | Fractions, inequalities, sums, inline equations, one-column and three-column tables rendered together |
| Composer targets | Small or intermittent targets affected hammer, attach, send/stop, model, and tool activity | Unified 36-point targets and stable cached hammer inventory | Hammer, model menu, attach panel, sidebar, Settings, tool row, send, and Stop responded on first intentional click |

## Information architecture

The two-level structure is sound: project/session navigation remains on the left, while the central surface switches between the conversation and a Settings hierarchy. Returning from Settings through the explicit Session button is understandable and preserves spatial continuity. The model, agent, capabilities, context, attachment, and send/stop controls stay adjacent to the composer, which is where users form intent.

The Settings sidebar is comprehensive but close to the limit of what one flat hierarchy can carry. “Grok,” “Tools,” “Extensions,” “Controls,” and “Application” provide useful grouping, yet Models, MCP Servers, Plugins, Marketplace, Hooks, Compatibility, Permissions, and App all compete with equal visual weight. The next structural improvement should be task-oriented entry points from the chat rather than another Settings reorganization: model problems should deep-link to Models, approval problems to Permissions, and unavailable tool problems to the exact tool pane with a concise diagnosis.

The session sidebar prioritizes recent titles and now exposes model, running/idle state, and last activity through help and accessibility text. Hover, selection, and right-click expose Rename and Close Session. A new tab without a persistence record announces **New session** rather than manufacturing a year-one date. These details materially improve long-history navigation without permanently increasing row density.

## Conversation model and session identity

A conversation is only trustworthy if four identifiers agree: the visible transcript, the local tab UUID, the persisted Grok backend ID, and the active model. Before repair, the UI preserved two of those while losing the backend ID on quit. The result was especially dangerous because it looked correct until the user sent the next prompt.

The repaired invariant is the right one: a populated restored tab resumes its durable backend identity unless the user explicitly creates or forks a session. Process teardown is not a product event and must never erase that identity. A stale backend remains a separate, explicit recovery case: `FS_NOT_FOUND` can start fresh while retaining the local transcript and showing a system note.

The backend receipts matter. GPT's base marker and follow-up marker are in one session and both assistant records identify `gpt-5.6-terra`. DeepSeek's saved layout retained its backend ID and model through quit. This is stronger evidence than a selector screenshot because it proves where the prompt actually ran.

## Composer ergonomics and click reliability

The composer is compact without being microscopic. The 36-point interaction contract is a good compromise for macOS: it avoids an iPad-sized toolbar while providing enough forgiveness for pointer input. In live use, model, hammer, attach, sidebar, Settings, tool-row disclosure, send, and Stop were all reachable through named accessibility elements.

The attachment button correctly opened a native `NSOpenPanel`; Cancel closed it without mutating the draft. The hammer menu opened from a lazy restored session with eight cached entries. Stop changed from an active static symbol back to a disabled Send control after cancellation, and a new short turn succeeded immediately.

Lazy startup now explicitly distinguishes **Starting agent…** from **Resuming session…** in the workbench status. Submitted text is cleared only after `ChatStore` accepts it and only if the user has not edited the draft in the meantime. Failed resume and send/typing races therefore preserve the user's input.

## Streaming, perceived latency, and autoscroll

Grok still provides the strongest perceived streaming because content appears progressively. GPT often presents useful content near completion, and DeepSeek can remain silent for tens of seconds. Those are provider characteristics; the client should make them feel intentional rather than broken.

The static **Agent working…** state is materially better than a periodic TimelineView because it does not invalidate the entire transcript. Thinking duration remains available after completion without forcing the thinking body open. Tool activity appears above the result, preserving reading order and bottom-follow ownership.

Autoscroll now handles four distinct events: streamed text growth, final chunk completion, delayed rich block sizing, and view reconstruction. The settled retry window is justified because WebKit/KaTeX/table layout can finish after the ACP text stream. The interrupted-turn recovery screenshot also showed the short follow-up marker fully visible above the composer even though the scroll bar's normalized value was not exactly `1.0`; viewport truth, not the raw scroll fraction, is the correct acceptance criterion.

Recommendation: add an explicit user-detach rule. When the user scrolls materially upward, stop automatic following and show a “Jump to latest” affordance. Current tests focus on the follow-the-bottom path; protecting deliberate reading position is the complementary contract.

## Model switching and persistence

Fresh selection worked for Grok, GPT, and DeepSeek. Settings did not mutate the active model. Quit/relaunch preserved GPT and DeepSeek once backend identity survived teardown. The composer context labels matched the selected provider: Grok 500K, GPT 128K, DeepSeek 200K when available.

Model labels should not be treated as authority. During the reproduced defect, the selector initially said GPT while the follow-up ultimately ran in a new Grok session. The repaired tests correctly pin session identity and restart resolution, and live acceptance verifies backend history. Keep this evidence standard for future model-routing changes.

The current model menu is appropriately direct: models are first-level choices and reasoning effort is the only submenu. Avoid adding provider configuration or capability prose to this menu; that belongs in Models Settings and contextual help.

## Markdown, code, math, and web rendering

The mixed-content renderer passed the important composition case: explanatory prose, inline code, fenced bash, fenced Swift, one-column and multi-column tables, inline math, display math, fractions, inequalities, and ordered lists in one response. Dark-mode KaTeX matched the surrounding surface, and math did not shred table rows.

Backend history proved that Grok supplied three valid Markdown links to Apple Developer content. Clicking the first rendered title opened the exact Actor documentation page in Chrome. The follow-up renderer applies accent/underline treatment and exposes individual accessibility link children; rebuilt live acceptance showed a distinct source link with its destination in the AX tree.

Rich tables now expose a table summary plus header and cell labels. Display LaTeX hides fragmented WebKit descendants behind one spoken equation label, and Mermaid does the same with a diagram description. Source contracts cover these semantics; a full VoiceOver rotor pass remains a worthwhile acceptance expansion.

## Permissions and interruption design

The stored Settings receipt was `dontAsk`, Sandbox Default, Disable web search off, and Disable subagents off. The defect was the label, not proof that the CLI violated that mode: official xAI documentation defines `dontAsk` as deny-by-default headless/CI behavior. The repaired UI calls it **Deny unapproved (CI)**, groups it under Advanced, and offers Ask, Auto, and Always approve as the interactive choices.

The app deliberately does not change an existing `dontAsk` preference to Always approve because that would expand authority. Always approve uses the CLI's exact `--always-approve` launch flag, while Ask omits a flag and the advanced modes keep their exact `--permission-mode` values. Legacy explicit `bypassPermissions` values normalize to Always approve.

Permission cards should never push the answer behind the composer or disappear inside collapsed tool activity. The current placement remained visible and preserved Stop.

## Accessibility and native macOS behavior

The application uses a standard window, standard menu bar, `NSOpenPanel`, SwiftUI menus/pickers, native scrolling, and Command-Q termination. Settings and Session are named buttons. Composer controls have descriptive accessibility labels rather than raw SF Symbol names in their resting states.

Keyboard coverage is credible but not fully audited end-to-end in this pass. Return sends, Shift-Return is documented for a newline, Escape closes menus, and native panels retain their platform keyboard behavior. Links, tables, equations, and diagrams now expose semantic accessibility descriptions. Permission cards say **Tool approval required** and name the effective launch policy. A hands-on VoiceOver rotor pass remains the next acceptance depth, especially for long tables and multiple virtual link children.

The always-dark appearance is coherent, but it overrides the user's system appearance rather than participating in it. That is a product choice, not automatically a bug. If retained, verify increased contrast, reduce transparency, and differentiate-without-color system settings. The current warm-glass borders are subtle enough that low-contrast users may lose card boundaries.

## Visual hierarchy, typography, spacing, density, and dark mode

The central transcript has calm rhythm and strong separation between user prompts and assistant content. Code blocks and tables provide useful containment without turning every block into a card. The composer reads as the primary persistent control because it is wide, anchored, and separated from the transcript.

Assistant output is now labeled **Build agent**, avoiding false attribution to Grok when GPT or DeepSeek produced the result while preserving the product's agent-workbench language.

Tool activity, thinking, and answer headings use similar small secondary treatments. They are individually tidy but can become a gray stack. Give tool activity a compact status icon/color and preserve thinking as a disclosure. The current density is appropriate for a desktop developer tool; resist adding permanent explanatory text to the composer.

## Error, loading, empty, stalled, and recovery states

Empty sessions provide four build-oriented quick starts and a clear composer. Working states are static and low-cost. Stop is immediate and recoverable: the deliberately interrupted 200-item turn stopped after item 16, the impossible end marker never arrived, and the next prompt returned `STOP-RECOVERY-OK-0731` in the same session.

Stall handling is implemented as a bounded watchdog with Stop-and-retry rather than automatic process killing. It remains fixture-proven because manufacturing a genuine 120-second wedge would add little confidence and waste provider time. Failure receipts and stale-session fallback have automated coverage.

Restored sessions now show **Resuming session…**, and an unchanged draft is cleared only after accepted submission. The corresponding failure/race policy is fixture-covered.

## Performance and CPU behavior

The original severe defect was architectural: a periodic UI invalidation traversed a long lazy transcript while the provider was silent. Removing the timer and using event-driven revisions restored idle CPU to 0%.

Current observations:

| State | Observed app CPU / memory | Assessment |
|---|---|---|
| DeepSeek silent reasoning | 0.0% across three one-second samples, ~47 MB | Pass; provider latency does not burn the UI thread |
| Grok progressive/rich rendering | Bounded bursts were previously observed around 65%; no sustained pin | Acceptable but worth Instruments profiling on very long tables/math |
| Settled rich transcript | 0.0% across three samples, ~68 MB | Pass |
| Idle after completed turns | 0.0% | Pass |

The remaining performance opportunity is rich-block construction. Multiple KaTeX WebViews and horizontally scrolling tables are more expensive than native text. Cache parsed block identity, avoid rebuilding completed blocks when only a later message changes, and profile body evaluation plus WebKit process memory with Instruments before adding more rich types.

## Model behavior, separated from product behavior

DeepSeek ignored “No tools,” invoked a write tool, created `exact-math-reference.md`, and then claimed no tools were needed. The app accurately displayed the tool receipt. The untracked file was moved recoverably to `~/.Trash/GrokBuild-stress-stray-exact-math-reference-20260731-202229.md`. This is a model instruction-following failure; the honest tool UI prevented it from becoming a hidden product failure.

In the OpenRouter rich-result lane, DeepSeek omitted the requested one-column table and bash fence and substituted `$$...$$` for the requested `\[...\]` delimiter while claiming all constraints were met. The renderer correctly displayed what it received. Kimi used an approved terminal/AppleScript fallback despite an explicit no-terminal instruction. These are model instruction-following failures. By contrast, a complete final assistant record that exists in backend history but is absent from the UI is a GrokBuild transcript-finalization defect.

Grok and GPT have sometimes omitted requested links in earlier stress prompts. In the final Grok web turn, backend content did contain all three requested URLs and the first link opened successfully, so the renderer passed that case. Never infer renderer failure solely from absent link styling without inspecting the model's emitted Markdown.

Provider latency differs substantially and should be described, not normalized into a false benchmark. Grok was usually fastest and most progressive; GPT was often one-shot; DeepSeek was slowest but detailed. These samples are interaction evidence, not a durable model leaderboard.

## Prioritized findings

| ID | Severity | Status | Evidence | User impact | Recommended fix |
|---|---|---|---|---|---|
| UXR-01 | P0 | **Fixed** | Quit changed the selected record from valid GPT backend ID to `null`; next prompt created a Grok session | Silent conversation/model corruption | Ignore teardown `nil`, persist non-empty receipt, rebind and resolve saved ID centrally |
| UXR-02 | P1 | **Fixed** | Settings → Session reopened a populated transcript at its top | User loses the current answer and must scroll | Settled auto-scroll on `ChatView.onAppear` |
| UXR-03 | P1 | **Fixed** | `dontAsk` was labeled like a prompt preference though the CLI defines headless deny behavior | Users inferred full-capability prompt suppression | Honest Deny unapproved (CI) label; Ask/Auto/Always approve interactive group; exact launch flags |
| UXR-04 | P1 | **Fixed** | Periodic working/Stop UI pinned CPU near 100% during silence | Battery drain, heat, stalled-feeling app | Event-driven/static state and bounded stream/scroll updates |
| UXR-05 | P2 | **Fixed** | Links worked but resembled body text and flattened in AX | Low discoverability; weaker VoiceOver navigation | Accent/underline treatment and individual AX link children |
| UXR-06 | P2 | **Fixed** | Rich tables/math flattened into coarse AX text/HTML fragments | VoiceOver users could not interpret structure efficiently | Table/header/cell labels and single spoken equation/diagram descriptions |
| UXR-07 | P2 | **Fixed** | Restored transcript was visible before connection readiness was obvious | Send felt delayed or could appear lost | “Resuming session…” state and accepted-send draft retention |
| UXR-08 | P2 | **Model behavior** | DeepSeek wrote a file after “No tools” | Unexpected workspace mutation | Keep tool receipts prominent; consider deterministic no-tool request mode if ACP exposes one |
| UXR-09 | P3 | **Fixed** | Assistant label said “Grok” for GPT/DeepSeek answers | Confusing model attribution and chatbot framing | Neutral **Build agent** label |
| UXR-10 | P3 | **Fixed** | Session titles truncated into near-duplicates | Slow navigation in long histories | Model/state/time help and AX metadata; hover/context Rename and Close |
| UXR-11 | P3 | **Fixed** | Fresh tab surfaced Dec 31, year 1 as last-used time | Obviously broken native metadata | Treat missing persistence timestamp as **New session** |
| UXR-12 | P1 | **Fixed** | ACP completion is now an acknowledged ordered event; bounded exact-session reconciliation repairs partial local transcripts. Fresh GPT Browser `GPT-BROWSER-REPAIR-OK-0731` and one clean Grok parent `SUBAGENT-STRESS-OK-0731` rendered and restored exactly once | Final synthesis is committed before the client settles, with an idempotent backend-tail recovery layer | Keep the settlement wire-order and repeated-reconciliation fixtures |
| UXR-13 | P1 | **Fixed** | Credential-free launch receipts drive the card copy and ACP disposition. Always approve terminal/browser/Computer Use ran without cards; Ask produced one correctly labeled blocking card and its affirmative action ran `GB-ASK-CARD-OK-0731` | Effective authority is predictable without conflating Always approve with YOLO mode | Keep explicit deny, hook, and sandbox precedence ahead of auto-allow |
| UXR-14 | P2 | **Fixed** | Reload captures the durable backend ID before teardown, queues/coalesces streaming reloads, preserves model/agent, and makes stale fallback explicit/lossless. Empty-only post-start rehydration fixed the final lazy restored-view race | Settings reload and relaunch no longer silently split or blank a populated work session | Never let transient process `nil` overwrite persisted identity or let recovery replace newer non-empty live text |
| UXR-15 | P2 | **Fixed** | Added explicit graceful `computer_close_app` with optional force, aligned it to `agent-desktop close-app`, and filtered hidden/zero-size/helper windows. Kimi read Calculator `42`, closed it gracefully, and proved it absent | Native automation can complete ordinary close workflows without an impossible shortcut argument | Keep force explicit and opt-in; prefer the main visible standard window |

## Ship judgment

The repaired build is suitable for continued supervised personal use as a GrokBuild project workbench. Standard Grok, GPT, DeepSeek, and Kimi sessions; agentic code repair; subagents; browser execution; attachments; rich rendering; transcript settlement/restoration; permission modes; configuration reload; Computer Use close; updater freshness; signing; and idle performance are at a defensible level. No open product defect remains from UXR-12 through UXR-15. Remaining caveats are model behavior and environment capability: Kimi needed the outer harness to open Calculator once after a Spotlight stall, and Screen Recording remains denied because the accepted Computer Use lane required only Accessibility snapshots.
