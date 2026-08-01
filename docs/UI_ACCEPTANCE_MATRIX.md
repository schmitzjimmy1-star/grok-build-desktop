# GrokBuild UI acceptance matrix

Date: 2026-07-31
Target: `/Applications/GrokBuild.app`

“Single click” means one pointer activation with no second click needed to unstick focus. The live-result column is completed against the installed application, not a SwiftUI preview.

| Route/control | Expected single-click result | Busy/disabled behavior | Keyboard route | Live result |
|---|---|---|---|---|
| Main toolbar Settings gear | Open Settings on the last selected Settings tab | Remains enabled; no model/process mutation | App Settings command where available | **Pass** — first click reopened Models |
| Sidebar Settings gear | Same route and tab as toolbar gear | Remains enabled | Focus + Space/Return | **Pass** — first click reopened Models; sidebar state restored afterward |
| Settings sidebar → Models | Show Models on first activation; preserve pane state while visiting another tab | Only the active provider request is disabled | Tab/arrow navigation + Space/Return | **Pass** — first activation; Models view remained responsive |
| Contextual Browser setup link | Open Settings directly on Browser | Remains enabled after recoverable error | Focus + Space/Return | **Code/AX pass** — route uses the same selected-tab model; no live error card was available to trigger |
| Contextual Computer Use setup link | Open Settings directly on Computer Use | Remains enabled after recoverable error | Focus + Space/Return | **Code/AX pass** — route uses the same selected-tab model; no live error card was available to trigger |
| Settings Session button | Return to the same active session | 32×32 target; never changes model | Focus + Space/Return | **Pass** — first click returned to the existing transcript |
| Escape in Settings | Return to the same active session | Available unless a system modal owns Escape | Escape | **Pass** — Escape returned immediately |
| Save Default, unchanged | No action | Disabled until selection differs from persisted default | Focus skips disabled control | **Pass** — disabled at No default override |
| Save Default, changed | Save for future sessions; do not restart current session | Applying/Saved/error visible; duplicate tap blocked | Space/Return | **Pass** — Saved appeared, active helper PIDs stayed unchanged, original default restored |
| Provider Test connection | Fetch one catalog and classify the result | Only that provider action disables; shows Checking | Focus + Space/Return | **Pass** — OpenAI 125 models; Kimi 12 models |
| Provider missing configured model | Keep valid authentication distinct from model availability | Shows Model missing and missing ID; no false auth blame | Same as Test connection | **Fixture pass** — both live configured IDs were present, so missing state was exercised by the local stub |
| Add model for official preset | Open only after a successful non-empty catalog; save only a returned model | Disabled with reason before catalog | Focus + Space/Return | **Pass** — disabled before check, enabled after each live catalog |
| Custom/local unverified model | Require explicit advanced opt-in | Save disabled until opt-in | Toggle with Space | **Code/fixture pass** — explicit advanced toggle and save guard present |
| Provider Save | Store credential in Keychain, metadata without secret, project CLI copy to secure config | Save blocked by validation; actionable storage error | Focus + Space/Return | **Pass** — both Keychain records present, two metadata records contain zero secrets, config is `0600` |
| Model API protocol | Persist Grok-native `api_backend`; OpenAI preset starts on Responses | Local to edited model; unsupported routes remain user-selectable | Picker keyboard navigation | **Pass** — installed app showed OpenAI as Responses, Kimi as Chat Completions, and the OpenAI editor exposed Responses in the protocol picker |
| Copy diagnostics | Copy redacted endpoint/auth/status/count/time only | Appears after a check | Focus + Space/Return | **Pass** — action appeared after each check; payload construction has no credential field |
| Browser Apply Changes | Persist applied settings and restart active Grok connections once | Disabled when clean; visible applied/current state | Focus + Space/Return | **Pass** — one apply, helpers restarted once; one expected refused status probe and zero repeats in the following 20 seconds; 0% CPU |
| Main model selector before/after Settings | Same session model before entry and after return | Settings validation cannot modify it | Menu keyboard navigation | **Pass** — Grok 4.5 before and after all routes/checks/default saves |
| Toolbar controls | Hover, pressed, focus, disabled, and busy styling; minimum 32×32 hit target | State local to action | VoiceOver name and keyboard focus present | **Pass** — AX exposed named Settings/Session/sidebar controls and pointer/keyboard routes agreed |

## Automated acceptance supporting the live pass

- `make test`: 307 tests, 0 failures.
- Provider fixtures: populated catalog, empty catalog, missing configured model, 401, 403, 404, 429, 5xx, malformed JSON, timeout/offline, and keyless local auth.
- Persistence fixtures: concurrent section mutations, unrelated-section preservation, atomic owner-only config writes, Keychain preference/migration/conflict/rollback, metadata redaction, and authentication-header selection.

## Live provider and CLI result

- OpenAI catalog: connected, 125 models, configured `gpt-5.6-terra` present.
- Kimi catalog: connected, 12 models, configured `kimi-k3` present.
- Config migration: `grok inspect --json` exits 0 with zero schema warnings; two model tables and two CLI key projections remain; config mode is `0600`. Compatibility Apply was exercised on and restored off, leaving 13 supported capability cells and no legacy blanket `enabled` field.
- Postman and BrightData cleanup: both plugins were uninstalled, their stale `[plugins].enabled` entries were removed, and no matching config references, files, processes, or startup warnings remain.
- Refreshed OpenAI CLI smoke: exact `OK`, exit 0 through Grok's native Responses backend, with zero warning lines. Usage: 11,539 input, 5 output, 0 reasoning tokens.
- Refreshed Kimi CLI smoke: exact `OK`, exit 0 through Chat Completions, with zero warning lines. Usage: 10,325 input, 2,560 cached input, 39 output, 23 reasoning tokens.
- Backend quiet check: GrokBuild and its helper were at 0% CPU, port 9222 had no listener, and the preceding 30 minutes contained no GrokBuild warning/error/refused log lines.
- Signed installed bundle: `/Applications/GrokBuild.app` passes strict deep code-sign verification and its executable hash matches the packaged `dist/GrokBuild.app`. The main → Settings → Models → Session route was repeated against the installed bundle; the active model remained Grok 4.5.

## Fable 5 endpoint-trust slice — live pass (2026-07-31 afternoon)

Build: `codex/warm-glass-ui` @ `ac31979` + endpoint-trust slice, rebuilt with `make app`, reinstalled via `make install`; strict deep code-sign pass (Team `DD2GCQJVB4`), installed binary byte-identical to `dist`, Dock pin preserved across the install. `make test`: **324 tests, 0 failures** on this build.

| Route/control | Expected single-click result | Live result |
|---|---|---|
| Keyless remote provider Test connection (Authentication **None / local**, empty key, `https://` remote URL) | Button enabled; request issued; typed transport failure, never an auth demand | **Pass** — enabled immediately after choosing None / local; click produced "A server with the specified hostname could not be found." (DNS-level typed transport error) |
| Remote `http://` base URL in provider editor | Validation message and Save blocked | **Pass** — "Remote endpoints must use https:// — http:// is allowed only for local servers." shown; Add Provider disabled |
| Remote `http://` + Bearer key Test connection | Instant typed refusal; no request leaves the app | **Pass** — "This remote endpoint uses http:// — GrokBuild will not send a credential over an unencrypted connection…" rendered with no network delay (request-time guard; fixture also proves zero requests issued) |
| Draft cancel → Session return after failed checks | Same active session and model | **Pass** — composer showed Grok 4.5 · 9K/500K before and after; no new "Reloaded Grok configuration." note; transcript intact |
| Quiet idle after the pass | No runaway work | **Pass** — GrokBuild 0.0% CPU / ~69 MB RSS, one `grok … agent stdio` child, browser bridge + Computer Use helper idle, no port-9222 sockets, no grok-owned listeners, zero error/refused/fail lines in the 12-minute unified-log window |

Fixture-only on this pass (no live redirecting server): cross-origin/downgrade/hop-limit redirect refusal — covered by `ProviderEndpointPolicyTests` and the `ProviderReliabilityTests` end-to-end stub, which also proves the second origin is never contacted. "Insecure URL"/"Redirect blocked" badges on saved provider rows were not exercised live (no provider was saved during the pass); the draft-editor message surfaces were.

Live observation (new, P3): inside the provider editor, moving between text fields by pointer needs an unstick click — a single click on another field leaves keyboard focus in the current field (typed text lands in the old field). Keyboard Tab traversal works correctly (id → name → URL → auth picker → API key). Recorded as finding F23 in `FABLE_5_AUDIT_FINDINGS.md`.

## Fable 5 lifecycle slice — live pass (2026-07-31 evening)

Build: same branch + slices 3/4/5/7-partial (session teardown, resume-preserving reloads, subprocess timeouts, action-safety guards), rebuilt and reinstalled; strict deep code-sign pass; installed binary == dist. `make test`: **334 tests, 0 failures** on this build.

| Check | Live result |
|---|---|
| Old instance quit before install | **Pass** — exited with zero GrokBuild/grok orphans |
| New build launch + session restore | **Pass** — Chicago Culture Radar transcript, Grok 4.5 · 9K/500K, one grok child + bridge + helper, all 0.0% CPU |
| Bounded quit (new `.terminateLater` path) | **Pass** — scripted quit round-trip **0.32 s**; grok child, browser bridge, and Computer Use helper all gone the instant quit returned (previously children died on stdin EOF after the app exited) |
| Relaunch after bounded quit | **Pass** — session restored intact again; no duplicate processes; Dock tile stable |

Fixture-only on this pass: closed-tab store deallocation (proven by `SessionLifecycleTests` weak-reference test; not directly observable live), streaming-deferred runtime reload (fixture; live mid-stream browser toggle needs an interactive conversation), and all subprocess timeout/drain contracts (`SubprocessHygieneTests`).

## Fable 5 updater-hardening slice — live pass (2026-07-31, third install)

Build: same branch + slice 6 (fail-closed TeamID policy, stage-then-swap installer, hardened helper signing, off-main verification). `make test`: **340 tests, 0 failures**.

| Check | Live result |
|---|---|
| Quit of prior build before install | **Pass** — again zero orphans (bounded-quit path consistent) |
| Helper signatures on the packaged app | **Pass** — `GrokBuildComputerUseMCP` and `agent-desktop` both `flags=0x10000(runtime)` with secure Timestamp, `Identifier=com.grokbuild.app`, Team `DD2GCQJVB4`; agent-desktop carries allow-jit + allow-unsigned-executable-memory |
| Signed agent-desktop under hardened runtime | **Pass** — `agent-desktop version` returns ok JSON (v0.6.0), exit 0, post-signing |
| Installed bundle | **Pass** — `codesign --verify --deep --strict` on `/Applications/GrokBuild.app`; installed binary == dist |
| Relaunch + session restore | **Pass** — transcript intact; grok child + browser bridge + hardened CU helper all running at ~0% CPU |
| Install-script contracts | **Fixture pass** — end-to-end against real dummy bundles: whole-bundle swap removes upstream-deleted files, unsigned staged update refused with target untouched, no staging leftovers, helper runs from a byte-identical temp copy |

~~Pending release authorization: one real notarized-release update through the new stage-then-swap path.~~ Retired 2026-07-31: GrokBuild is personal-use only (no distribution), so no notarized release is planned; the installer contracts stay proven by the fixture pass above. Note: the update feed watches upstream `rimusz/grok-build-desktop`; foreign-team installs now fail closed.

## Fable 5 quick-wins batch — live pass (2026-07-31, fourth install)

Build: + dead-skill removal, doc-drift fixes, personal-use app-release feed gate, ⌘,-tab preservation, pill VoiceOver labels, keyboard-activatable sidebar disclosure. `make test`: **341 tests, 0 failures**.

| Check | Live result |
|---|---|
| Installed skills payload | **Pass** — `Contents/Resources/Skills/` contains exactly `grokbuild-browser-control`, `grokbuild-computer-use`, `grokbuild-grok-web` |
| Update panel with gated feed | **Pass** — grok CLI section checked live against xAI (0.2.117 / stable / up to date); GrokBuild section rendered from the local stub ("Latest release: 0.1.20 / Up to date") with no GitHub query |
| Install + relaunch | **Pass** — deep-strict codesign verify; session restored and actively in use mid-conversation on the new build |

## Fable 5 final polish pass — live receipts (2026-07-31 evening, fifth install)

Build: + F13 pill/branch caching, F15b workspace-keyed panes, F17 stall watchdog, F23 focus fix, trusted-LAN http opt-in. `make test`: **344 tests, 0 failures**.

| Check | Live result |
|---|---|
| Provider-editor field focus (F23) | **Pass on attempt 3** — id → Name → Base URL clicked once each; every string landed in its intended field (`focus-test-id` / `Focus Test Name` / URL). Attempt 1 (stable `.id()`s) and attempt 2 (FocusState + tap gestures) both failed live and are recorded as falsified hypotheses; the shipped fix is the unfocused-only `focusClickCatcher` overlay driving `@FocusState` |
| Trusted-LAN http opt-in | **Pass** — typing a remote `http://` base URL surfaced the "Insecure HTTP" checkbox with the persistent orange warning and Add Provider disabled; checking it enabled Add Provider with the warning still shown; Cancel discarded everything |
| Session integrity | **Pass** — after all editor exercises: transcript intact, composer Grok 4.5 · 9K/500K, no reload note |
| Quiet idle | **Pass** — app + grok child + helper at 0.0% CPU, no 9222 sockets, zero error lines in the log window |

Fixture-only: stall banner rendering (triggering needs a genuinely wedged grok; state machine covered by `testTurnStallFlagsQuietStreamAndClearsOnActivityOrStop`), pill-cache refresh triggers (visual states matched pre-change behavior on this pass).

## Fable 5 OpenRouter setup — live pass (2026-07-31, sixth install)

Build: + OpenRouter provider preset, composer hit-target growth, stray-print removal. `make test`: **346 tests, 0 failures**.

| Check | Live result |
|---|---|
| OpenRouter template tile | **Pass** — renders second in the Provider Templates grid: "OpenRouter", `https://openrouter.ai/api/v1`, `e.g. openrouter/auto`, Install button |
| Install → editor prefill | **Pass** — "Install OpenRouter" editor pre-filled id `openrouter` (locked), Name, Base URL, **Bearer token** (locked), Documentation link, and the `…/models` catalog-query hint; **only the API key field empty**. No key was entered (that's Jimmy's step) |
| Composer hit targets (F22) | **Superseded below** — this pass reached 28pt; later installed builds unify the composer at 36pt while preserving compact glyphs |
| Quiet idle | **Pass** — app + grok child + helper 0.0% CPU, no 9222, zero error lines |

Not exercised (needs Jimmy's key / a billable call, by design): Test connection / live catalog fetch, adding an OpenRouter model, and the `Reply OK` end-to-end session smoke.

## Streaming auto-scroll + thinking — live pass (2026-07-31, seventh install)

Jimmy reported: model thinking seemed shown-not-hidden, and "the answer does not show up on screen, I have to scroll down." Root cause: a streaming answer appends to the existing assistant message's content, changing neither `messages.count`, `isGrokking`, nor `thinkingText` — so **none** of the scroll triggers fired for the answer; only thinking (which has a trigger) stayed in view, stranding the answer below the fold behind the collapsed thinking chip. Thinking itself was already collapsed-by-default (confirmed live: "Thought for 12s" chip, expands on click).

Fix: `ChatStore.streamRevision` bumps on every thinking/answer chunk; the transcript scrolls to a dedicated 1pt **bottom anchor** (reliable in a `LazyVStack`, unlike scroll-to-last-message-id for a tall freshly-streamed item), throttled to ~12/sec with a trailing scroll. `make test`: **346 tests, 0 failures**.

| Check | Live result |
|---|---|
| Long answer follows during streaming | **Pass** — a 3-paragraph George Bellows answer scrolled to keep the latest text in view as it streamed (verified mid-stream and at completion) |
| Final position | **Pass** — completed answer's last line sits just above the composer; no manual scroll needed |
| Thinking default | **Pass** — collapsed "Thought for Ns" chip by default; click expands to the reasoning; confirmed for grok reasoning turns |
| Earlier stranded answer | **Pass** — the previously below-the-fold "17×23=391" answer now renders in view too |

## Reported terminal, model, and click failures — full-send pass (2026-07-31, eighth install)

Build: same branch + ACP client-terminal support, tool receipts, dynamic CLI model catalog, unified 32-point composer targets, off-main Models loading, explicit turn-completion gating, and the OAuth loopback cancellation repair found during full-suite closeout. `make test`: **365 tests, 0 failures**. The Apple signing identity's timestamp step stalled, so this personal-use build was packaged with the repository's ad-hoc path; `/Applications/GrokBuild.app` passes deep/strict code-sign verification and its main executable is byte-identical to `dist/GrokBuild.app`. The previous installed copy was moved to the Trash as a recoverable backup.

| Check | Installed-app result |
|---|---|
| Fresh chat before first prompt | **Pass** — Grok 4.5 and `0/500K`; no vanished model and no stale Composer entry |
| Model menu | **Pass** — one Agent selector and one Model selector; Grok 4.5, GPT 5.6 Terra, Kimi K3, and DeepSeek V4 Flash 0731 appear directly, with Effort as the only submenu |
| Composer click surface | **Superseded below** — mode, model, skills, voice, attach, send/stop, tool group, and tool row shared a 32-point minimum; the streaming/click follow-up raises the contract to 36 points |
| Settings → Models first click | **Pass** — pane returned in ~1.4 seconds and remained interactive; default picker contained No override plus the same four current CLI models |
| ACP terminal command | **Pass** — approved `printf 'grokbuild-installed-terminal-pass\n'` completed with exit 0; assistant output was visible and the expandable tool row reported Done with the complete receipt |
| Completed-turn persistence | **Pass** — quit via the application shortcut, relaunched the exact installed bundle, and recovered the complete terminal answer in the selected chat |
| Failure diagnostics | **Pass** — live debug acceptance showed Failed with the exact executable error; the installed source is pinned by the ACP parsing/receipt fixture |
| Installed bundle parity | **Pass** — deep/strict verification succeeded; dist and `/Applications` SHA-256 both `2a37e830a83b4b045f797ef221a6efb3c724c3db70ae41cc2da65b58c4401a0f` |

## Composer reliability + web-stream pacing — live pass (2026-07-31, ninth install)

Jimmy reported intermittent composer clicks, a hammer that sometimes did nothing in new chats, and web-search answers that exposed the website/tool UI before snapping in as one late block. Reproduction found three independent causes: lazy tabs had no command inventory until their first Grok process launch; the current tool group mounted below the answer and captured bottom-follow; and the streaming Stop button's indeterminate `ProgressView` continuously invalidated the long `LazyVStack`, pinning the app near 100% CPU during a wedged web turn.

Fix: command inventory is cached without letting an empty discovery erase the last known catalog, the hammer always has a `/` browse fallback, composer targets are 36pt, current-turn tool activity anchors before the assistant answer, web-sized ACP text bursts drain through an adaptive 20 ms buffer, and Stop uses a static symbol. `toolActivityExpanded` also resets between turns so a previously opened website never auto-opens over the next response. `make test`: **368 tests, 0 failures**.

| Check | Live result |
|---|---|
| Fresh lazy chat hammer | **Pass** — enabled before the first prompt with 8 cached workflows; opened on 6/6 normal-cadence clicks |
| Tool placement | **Pass** — in the exact installed app, AX order exposed `Tool activity, 5` before the live Grok answer; terminal and layout fixtures agree |
| Web-answer rendering | **Pass** — the exact installed app completed a sourced five-paragraph Cubs recap without the old website/tool-below-answer snap; burst pacing preserves byte-for-byte text in fixtures |
| Streaming CPU | **Pass** — installed web streaming showed bounded work bursts and settled through 0.0% at idle, rather than the reproduced sustained ~100% invalidation loop |
| Content integrity | **Pass** — the long sourced answer completed through its Sources line; no final-chunk loss |
| Installed bundle parity | **Pass** — deep/strict verification succeeded; dist and `/Applications` executables both SHA-256 `5e9b13dc6f64aac221468ecba597c50e44883bfd188aaa3bd2e4254bfa5b4e18`; prior install moved recoverably to `~/.Trash/GrokBuild-pre-stream-fix-20260731-190119.app` |

## UI/UX restoration, identity, and broad stress pass — final installed receipt (2026-07-31)

This pass began with the reported Settings-return autoscroll defect and expanded into fresh and resumed Grok/GPT/DeepSeek conversations, one-shot and progressive rich answers, exact math, code, terminal/web tools, links, sidebar/Settings/relaunch restoration, Stop recovery, click targets, and CPU sampling. `make test`: **379 tests, 0 failures**. Grok CLI: `/Users/jimmyschmitz/.grok/bin/grok`, `grok 0.2.118 (1e1687c1cf6a) [stable]`; Settings → App displayed Installed and Latest 0.2.118 after its update notification.

| Check | Final installed-app result |
|---|---|
| Restored transcript bottom-follow | **Pass** — `RESTORE-FIX-20260731`, `GPT-ONE-SHOT-BOTTOM-0731`, and `DEEPSEEK-MATH-BOTTOM-0731` remained above the composer after Settings → Session; the restored markers also survived quit/relaunch without manual scrolling |
| GPT session/model identity | **Pass** — the base and `GPT-QUIT-RECEIPT-FOLLOWUP-0731` turns remained in backend `019fbae7-a0ce-7620-a7b1-0471a87f8698`; both backend assistant records identify `gpt-5.6-terra` |
| DeepSeek session/model identity | **Pass** — backend `019fbae8-c6a4-7442-86f3-635d5199871a`, DeepSeek model, 200K selector, and bottom marker survived Settings and quit/relaunch |
| Teardown receipt policy | **Pass** — Command-Q no longer rewrites a valid saved backend ID to `null`; non-empty identity remains durable while the live process clears transient state |
| Rich content | **Pass** — inline/display LaTeX, fractions, inequalities, one-column and multi-column tables, bash/Swift fences, inline identifiers, ordered lists, and long one-shot/progressive replies rendered together in dark mode |
| Web/tool path | **Pass with open interruption defect** — Grok ran terminal and official Apple web research, displayed tool activity before the answer, emitted three functional links, and ended at `GROK-TOOLS-WEB-BOTTOM-0731`; the first link opened the exact Apple Actor documentation. A harmless combined shell command still produced an approval card despite “Don't ask” |
| Composer/control targets | **Pass** — hammer exposed eight entries; attach opened a native Open panel; sidebar, Settings, model menu, tool row, send, and Stop all responded. Stop interrupted a 200-item turn before its forbidden marker, and `STOP-RECOVERY-OK-0731` succeeded immediately afterward |
| CPU | **Pass** — DeepSeek silent reasoning sampled 0.0% across three one-second samples at about 47 MB; settled rich transcript sampled 0.0% at about 68 MB; idle was 0.0%. Progressive rich rendering still produces bounded transient work and remains an Instruments candidate |
| Model-vs-product behavior | **Separated** — DeepSeek ignored “No tools” and wrote an untracked file; the app honestly showed the receipt, and the file was moved recoverably to `~/.Trash/GrokBuild-stress-stray-exact-math-reference-20260731-202229.md` |
| Installed bundle parity | **Pass** — deep/strict verification succeeded; `dist` and `/Applications` main executables both SHA-256 `e42d45b2d25265230a12548edb127c198ca7145b4c35808b1702721ff5bb957b`; the previous installed app is recoverable at `~/.Trash/GrokBuild-pre-final-ui-ux-acceptance-20260731-203242.app` |

At that install, open findings were permission naming, link/table/math semantics, restoration-state explanation, model attribution, and session metadata. The workbench follow-up below closes those client findings and leaves model instruction failures classified separately.

## GrokBuild workbench feature pass — final installed receipt (2026-07-31)

This follow-up deliberately evaluated GrokBuild as an agentic project workbench, not as a chatbot. The automated suite ran **388 tests with 0 failures**. The CLI receipt remains `/Users/jimmyschmitz/.grok/bin/grok`, `grok 0.2.118 (1e1687c1cf6a) [stable]`.

| Check | Rebuilt/live result |
|---|---|
| Build Workspace entry | **Pass** — new session showed `Grok Git Build Workspace` with architecture mapping, scoped implementation, working-tree review, and build/test diagnosis actions |
| Workbench context | **Pass** — project, `main` branch, session agent, Browser Tools, Computer Use, Workflows, Tasks, and Memory were visible by default above the composer |
| Branch/worktree management | **Pass** — opened native Git Branches & Worktrees sheet, confirmed project path/current branch, worktree list, search, New branch, and New worktree; closed without mutation |
| Agents and orchestration | **Pass** — session agent menu showed Default plus discovered `general-purpose`, `explore`, and `plan`; workflow menu showed run refresh, saved workflows, Deep Research, and settings |
| Sessions | **Pass** — sidebar exposed title/model/state/last-used AX metadata; right-click exposed Rename and Close; session dashboard and backend session browser opened successfully |
| Fresh-session metadata | **Fixed/pass** — live acceptance found `Dec 31, year 1` for an unpersisted tab; optional timestamp handling now announces **New session**, with fixture coverage |
| MCP, skills, plugins | **Pass** — live Settings panes exposed MCP Doctor/Refresh/config/status, searchable user+bundled skills with source actions, and installed plugin state/version/provenance |
| Permission truth | **Pass** — stored `dontAsk` now displays **Deny unapproved (CI)** with a deny-by-default explanation; picker separates Ask/Auto/Always approve from advanced modes; existing authority was not silently widened |
| Draft recovery | **Fixture pass** — failed/racing submission retains input; an unchanged draft clears only after accepted send; startup copy distinguishes Starting agent from Resuming session |
| Rich-result accessibility | **Pass + fixtures** — rebuilt AX tree exposed a native source link with destination; tests pin styled link runs, virtual link children, spoken equation descriptions, and table/header/cell labels |
| Product attribution | **Pass** — assistant results are labeled **Build agent**, not Grok, avoiding false model attribution and generic-chat framing |
| Installed bundle | **Historical pass** — executable SHA-256 `e9cf164cad8cdb1b00718e5612c2d1f67c0b1b16bf1e360190d1110ebba8eff3`; deep/strict signing and dist/install parity passed; quarantine cleared. The then-prior `/Users/jimmyschmitz/.Trash/GrokBuild-pre-workbench-feature-review-20260731-210606.app` bundle was superseded and permanently retired after the later hostile-stress repair |

The corresponding product analysis is `docs/GROKBUILD_FEATURE_REVIEW_2026-07-31.md`. The earlier open UI findings for permission labels, link semantics, table/math semantics, resume explanation, attribution, and session metadata are fixed in this build. Remaining recommendations concern persistent working-tree/test summary, task-oriented capability navigation, explicit user-detached autoscroll, and honest lifecycle language for non-durable scheduled tasks.

## Exhaustive provider/tool stress supplement — repaired final installed state (2026-07-31)

The signed installed bundle was rebuilt after the four hostile-stress integration repairs and exercised against the same disposable Swift package and deterministic local web target using Grok 4.5, GPT 5.6 Terra, OpenRouter DeepSeek V4 Flash 0731, and Kimi K3. The combined focused repair filter finished at **139 tests / 0 failures**, the production suite finished at **409 tests / 0 failures**, and the disposable fixture remains **2 tests / 0 failures**. Focused suites covered ACP wire-order settlement, permission launch/restart receipts, partial/idempotent transcript reconciliation, lazy post-start rehydration, durable reload/fallback, Computer Use schema/argument construction, and native integration.

| Feature path | Installed-app result |
|---|---|
| Grok agentic terminal/edit/test/diff | **Pass** — repaired the intentional arithmetic defect, proved fail-before/pass-after, and visibly restored `GROK-AGENTIC-REPAIR-OK-0731` after Settings and relaunch |
| Concurrent subagents | **Pass / UXR-12 fixed** — both named workers remain readable, one parent synthesis ends in `SUBAGENT-STRESS-OK-0731`, and the installed app restores exactly one final synthesis after relaunch |
| GPT Browser Tools | **Pass / UXR-12 fixed** — real page open/type/click/read/screenshot completed; fresh `GPT-BROWSER-REPAIR-OK-0731` and reload marker `GPT-RELOAD-IDENTITY-OK-0731` rendered immediately and restored after relaunch |
| OpenRouter DeepSeek rich response | **Pass / UXR-14 fixed** — terminal receipt, 20 findings, table/code/math rendering, `OPENROUTER-DEEPSEEK-RICH-OK-0731`, and `DEEPSEEK-RELOAD-IDENTITY-OK-0731` all restored. A final lazy-start race that briefly produced an empty in-memory view despite seven durable messages was repaired with empty-only post-start rehydration and reverified installed |
| Kimi Computer Use | **Pass / UXR-15 fixed** — Kimi used Computer Use snapshots/clicks to enter `7 × 6 =`, read `42` from a fresh snapshot, call graceful `computer_close_app`, and prove Calculator absent via `computer_list_apps`; `KIMI-CLOSE-REPAIR-OK-0731` restored after relaunch. The outer acceptance harness opened Calculator once after Kimi stalled on Spotlight; every target/calculate/read/close step used the repaired lane |
| Attachment workflow | **Pass** — incorrect directory attachment was removable; exact `README.md` selection, read receipt, grounded response, and `ATTACHMENT-GROK-OK-0731` all rendered |
| Stop/recovery | **Pass** — stuck Computer Use turn stopped immediately and composer recovered |
| Permission truth | **Pass / UXR-13 fixed** — terminal, Browser Tools, and Computer Use did not block under effective Always approve; Ask produced one card labeled `Effective live process policy: Ask`, its affirmative action ran the displayed command, and final state was restored to **Always approve / Sandbox Default / web enabled / subagents enabled** |
| Per-session model persistence | **Pass** — Grok, GPT, DeepSeek, and Kimi selectors survived Settings and quit/relaunch independently; a new chat correctly defaulted to Grok |
| Config-reload session continuity | **Pass / UXR-14 fixed** — Grok, GPT, DeepSeek, and Kimi retained coherent model/transcript identity through reload and relaunch. Teardown `nil` cannot erase the durable ID; stale resume creates one disclosed, transcript-complete fork instead of a silent split |
| Restored autoscroll | **Pass** — ordinary Grok and rich DeepSeek bottom markers remained above the composer through Settings and relaunch; missing GPT/subagent finals were absent data, not hidden below the fold |
| Idle CPU | **Pass** — installed app plus all live grok/helper children sampled at 0.0% CPU; no periodic transcript invalidation regression |
| Update-pane refresh | **Pass** — final Settings → App showed CLI Installed 0.2.118 / Latest 0.2.118 after the earlier stale 0.2.117 reproduction |
| Installed integrity | **Pass** — `/Applications/GrokBuild.app` and `dist/GrokBuild.app` executable SHA-256 are both `48ca90bd7beaa31b8a2a82fab048fb95d49503a30a6f1893be64c13475e863c8`; deep/strict signing passes for app and native helpers under Team `DD2GCQJVB4`; quarantine is absent; three signed rollback checkpoints remain and fourteen superseded intermediate bundles were retired |

Model behavior is kept separate: DeepSeek omitted a requested one-column table and bash fence and changed the exact display-math delimiter. Kimi initially skipped typing after a Spotlight attempt, so the outer harness opened Calculator once; Kimi then completed the complete repaired Computer Use target/calculate/read/close path without terminal or AppleScript. Those instruction-following misses are not client defects. UXR-12 through UXR-15 are fixed product contracts with automated and installed-app proof.
