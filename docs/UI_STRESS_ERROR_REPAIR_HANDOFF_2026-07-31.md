# GrokBuild hostile-stress error repair handoff — 2026-07-31

## Repair closeout — Fixed

UXR-12, UXR-13, UXR-14, and UXR-15 are fixed in the rebuilt installed app. The combined focused filter for ACP contracts, permission/capability handling, transcript import/reconciliation, session persistence, and Computer Use core/integration completed **139 tests with 0 failures**. `make test` completed **409 tests with 0 failures**; `SessionPersistenceTests` alone completed **41 tests with 0 failures**, including the final empty-only post-start rehydration regression, whose direct filter completed **1 test with 0 failures**. The disposable stress fixture remains **2 tests with 0 failures**. `git diff --check` and the repository-wide Markdown/Swift/MDC trailing-whitespace scan both passed.

The final signed `dist/GrokBuild.app` and `/Applications/GrokBuild.app` main executables match byte-for-byte at SHA-256 `48ca90bd7beaa31b8a2a82fab048fb95d49503a30a6f1893be64c13475e863c8`. `codesign --verify --deep --strict --verbose=2` passes; the app and native helpers are signed under Team `DD2GCQJVB4`; quarantine is absent. The retained signed rollback checkpoints are `/Users/jimmyschmitz/.Trash/GrokBuild-pre-stress-error-repair-20260731-223704.app`, `/Users/jimmyschmitz/.Trash/GrokBuild-pre-final-persistence-20260731-230355.app`, and `/Users/jimmyschmitz/.Trash/GrokBuild-pre-final-repair-20260731-233408.app`; fourteen superseded intermediates were permanently retired during closeout cleanup.

Installed acceptance restored one clean Grok subagent parent marker (`SUBAGENT-STRESS-OK-0731`), fresh GPT Browser completion/reload markers (`GPT-BROWSER-REPAIR-OK-0731`, `GPT-RELOAD-IDENTITY-OK-0731`), the full DeepSeek rich transcript and reload marker (`OPENROUTER-DEEPSEEK-RICH-OK-0731`, `DEEPSEEK-RELOAD-IDENTITY-OK-0731`), and the Kimi native-close marker (`KIMI-CLOSE-REPAIR-OK-0731`) after relaunch without duplicate assistant messages. Always approve terminal/browser/Computer Use paths were non-blocking; Ask produced one correctly labeled card and ran its displayed command; final state is Always approve, Sandbox Default, web enabled, subagents enabled, Browser Tools Ready, and Computer Use Ready with Accessibility granted. Screen Recording is denied and screenshot fallback is off because accessibility snapshots were sufficient. Settings → App reports CLI Installed 0.2.118 / Latest 0.2.118. The app is left idle on the restored Kimi marker above the composer.

## Mission

Fix and live-verify the four open integration defects from the installed-app hostile workbench pass:

1. **UXR-12 / P1:** complete final assistant synthesis exists in Grok backend history but is absent from the visible and restored GrokBuild transcript.
2. **UXR-13 / P1:** the effective policy says **Always approve**, yet GrokBuild still presents blocking approval cards.
3. **UXR-14 / P2:** a configuration reload can split one visible session across Grok backend IDs and leave only a partial transcript tail in the client.
4. **UXR-15 / P2:** Computer Use tells the agent to pass `--force` for a blocked shortcut even though `computer_press` exposes no force argument; fallback window targeting is ambiguous.

This is a GrokBuild feature repair, not a chatbot polish exercise. Preserve the project-workbench framing: project/session identity, execution truth, tool receipts, durable results, interruption policy, and native automation matter more than decorative conversation chrome.

## Full authorization

Work autonomously through diagnosis, implementation, tests, documentation, rebuild, installation, and live installed-app acceptance. Do not pause for ordinary confirmations.

You are explicitly authorized to:

- edit GrokBuild source, tests, bundled skills, scripts, and documentation required for these four defects;
- use Grok 4.5, GPT 5.6 Terra, OpenRouter models, Kimi/API models, Browser Tools, Computer Use, terminal tools, and subagents for bounded functional acceptance;
- make bounded billable provider calls needed to prove the repaired paths;
- click **Yes**, **Proceed**, **Allow**, or the affirmative equivalent when macOS or GrokBuild asks during this authorized repair;
- when a GrokBuild permission card displays a command, run that exact command through its affirmative action;
- grant/reconfirm Accessibility and Screen Recording if macOS asks, without disabling useful security controls;
- stop/restart GrokBuild and its session helpers as needed;
- move the currently installed app to a uniquely timestamped, recoverable Trash backup, install the newly built bundle, clear quarantine attributes, and verify it;
- use parallel subagents for bounded code/test investigation while keeping final integration ownership in the main task.

Authorization is **local through installed acceptance**. No commit, push, pull request, release publication, history rewrite, force push, broad staging, or destructive cleanup is requested. If a later message separately authorizes publication, stage only the exact intended paths.

## Non-negotiable safety and workspace rules

- Repository: `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- Branch: `codex/warm-glass-ui`
- Installed app: `/Applications/GrokBuild.app`
- The working tree is heavily dirty from ongoing Fable 5/UI work. Immediately before this handoff file was added it contained **69 changed/untracked paths**. Treat every pre-existing change as Jimmy's work.
- Read `AGENTS.md` and `ARCHITECTURE.md` before editing.
- Begin with `git status --short --branch`, then inspect only relevant diffs. Never reset, checkout, clean, stash, or broadly stage the tree.
- Use `apply_patch` for edits. Keep each repair and its tests narrowly attributable.
- Do not print, copy, commit, or document provider credentials. Backend history may contain tool content; quote only the minimal non-secret evidence.
- Use Computer Use against the exact installed path. Re-query the accessibility tree before every action and after any detected user/UI change.
- Keep the final UI on a verified repaired transcript with its unique marker visibly above the composer.

## Current artifact and rollback truth

- Last full production suite: **409 tests, 0 failures**.
- Disposable stress fixture after repair: **2 tests, 0 failures**.
- Current `dist` and installed executable SHA-256:
  `48ca90bd7beaa31b8a2a82fab048fb95d49503a30a6f1893be64c13475e863c8`
- `/Applications/GrokBuild.app` passes `codesign --verify --deep --strict --verbose=2`.
- Quarantine is absent.
- Current recoverable prior install:
  `/Users/jimmyschmitz/.Trash/GrokBuild-pre-final-repair-20260731-233408.app`
- Grok CLI:
  `/Users/jimmyschmitz/.grok/bin/grok`
  `grok 0.2.118 (1e1687c1cf6a) [stable]`
- Final Settings state during the stress pass:
  **Always approve**, **Sandbox Default**, web enabled, subagents enabled.
- Final Settings → App receipt:
  CLI **Installed 0.2.118 / Latest 0.2.118**.
- Last verified installed transcript:
  Kimi session with `KIMI-CLOSE-REPAIR-OK-0731` visible above the composer after relaunch; Grok subagent, GPT Browser, and DeepSeek rich/reload markers were also restored from the same installed build.
- The deterministic local browser server was stopped. The disposable fixture remains at:
  `/private/tmp/grokbuild-stress-20260731.hQwFzd`

## Evidence ledger

All five backend receipts below currently exist under:

`/Users/jimmyschmitz/.grok/sessions/%2Fprivate%2Ftmp%2Fgrokbuild-stress-20260731.hQwFzd/`

| Lane | Backend session | Evidence |
|---|---|---|
| Concurrent Grok subagents | `019fbb1c-827c-73b3-b292-2cc66de125b6` | Backend has clean `SUBAGENT-STRESS-OK-0731`; live UI showed interleaved worker fragments and never rendered/restored the synthesis |
| GPT Browser Tools | `019fbb20-0b85-7462-b956-8fa3439adf05` | Browser work completed and backend has `DIRECT-GPT-BROWSER-OK-0731`; live/relaunched transcript ended before the final answer |
| Kimi before reload | `019fbb20-7f40-70c3-8874-4fc4cc985232` | Earlier partial visible history |
| Kimi after reload | `019fbb35-b7d9-7910-a33c-be2b2078a5ab` | Backend contains successful Calculator clicks and fresh-snapshot value `42`; visible session retained only part of the run |
| OpenRouter DeepSeek control | `019fbb3d-4566-7562-aba1-91b5ec2dd14c` | Complete rich result, marker, Settings restoration, relaunch persistence, and bottom-follow all passed |

The two subagent workers were also observed as:

- explore: `019fbb1c-a483-73f3-8f0b-943bb7d2fd76`
- general-purpose: `019fbb1c-a483-73f3-8f0b-9454bbba363d`

Treat on-disk history as evidence, not as the desired UI database. The fix must make the normal ACP/client commit path correct and use history reconciliation as a bounded recovery layer, not poll the whole session directory forever.

## Repair 1 — UXR-12: missing final synthesis — Fixed

**Fixed:** ACP `turn_completed` is now an ordered, acknowledged ChatStore barrier rather than an immediate process release. Completion waits for the prompt response and queued completion event before clearing the streaming target. Bounded exact-session reconciliation repairs partial local transcripts using role/turn/occurrence identity, preserves newer local text, and is idempotent across repeated restore. Fresh GPT Browser and concurrent-subagent finals rendered immediately and restored exactly once after relaunch.

### Reproduction

1. Launch the exact installed app and open the disposable fixture project.
2. Open the GPT Browser Tools session. The sidebar identifies `gpt-5.6-terra`; the visible transcript does not contain `DIRECT-GPT-BROWSER-OK-0731`.
3. Confirm that the corresponding `chat_history.jsonl` does contain the marker and a complete final assistant record.
4. Quit and relaunch. The marker remains absent from the UI.
5. Repeat with the concurrent-subagent session and `SUBAGENT-STRESS-OK-0731`.
6. Compare with the DeepSeek control session, whose final marker renders and restores correctly.

### Primary code path

- `GrokBuild/Services/GrokProcess.swift`
  - `send(_:)`
  - `awaitTurnCompletion()` / `markTurnCompleted()`
  - `handleJsonLine(_:)`
  - `routeUpdate(_:)`
- `GrokBuild/Services/ChatStore.swift`
  - `deliverPrompt`
  - `finishPrompt` / `finishPromptNow`
  - `handleAcpEvent`
  - `appendAssistantText`
  - streaming-buffer flush/deferred completion
- `GrokBuild/Services/SessionMessageStore.swift`
- `GrokBuild/Services/SessionTranscriptRecovery.swift`
- `GrokBuild/Services/GrokSessionTranscriptImporter.swift`
- `GrokBuild/ContentView.swift`
  - `.liveSessionMessagesChanged` persistence boundary

### Leading hypothesis to prove or falsify

`GrokProcess.handleJsonLine` currently intercepts `turn_completed`, calls `markTurnCompleted()`, and returns. That can release `process.send`; `ChatStore.finishPromptNow` then clears `streamingMessageID`. If a final `agent_message_chunk` is queued or arrives after `turn_completed`, `appendAssistantText` silently drops it because there is no active streaming message. This ordering fits both missing-final cases, but do not patch by folklore—capture a deterministic fixture first.

A second weakness is recovery scope: `SessionTranscriptRecovery` repairs empty/non-restorable transcripts, while these sessions are **partially** populated. A partial transcript can therefore remain permanently incomplete. UUID-only merging cannot safely deduplicate content imported from backend history because imported message IDs are not necessarily the local streaming UUIDs.

### Required automated coverage

Add deterministic ACP fixtures for at least these orders:

1. final chunk → prompt response → `turn_completed`;
2. prompt response → final chunk → `turn_completed`;
3. `turn_completed` → final chunk;
4. tool-call update → `turn_completed` → final synthesis chunk;
5. concurrent/subagent tool updates interleaved before one clean parent synthesis;
6. quit/relaunch with a partial local transcript and a longer authoritative backend transcript;
7. reconciliation repeated twice without duplicates;
8. no regression to progressive streaming, Stop, tool ordering, or settled autoscroll.

Prefer an explicit turn-completion event/barrier owned by `ChatStore` over arbitrary sleeps. If the ACP contract permits late chunks, completion must not clear the target message until queued events are drained. Add bounded backend-tail reconciliation at completion/restore as defense in depth, with stable content/role/turn deduplication and no replacement of newer local text.

### Acceptance gate

- A fresh GPT Browser Tools turn ends with a unique final marker visible above the composer immediately.
- A fresh two-subagent turn presents worker activity cleanly and then one non-interleaved parent synthesis with a unique marker.
- Both markers remain visible after Settings → Session and after quit/relaunch.
- Backend history and visible transcript agree on the final assistant answer.
- No duplicate assistant messages appear after repeated restore/reconciliation.

## Repair 2 — UXR-13: Always approve still interrupts — Fixed

**Fixed:** every launch/restart exposes a credential-free effective launch receipt. Always approve safely auto-selects a real ACP allow option unless explicit deny/sandbox enforcement already blocked it; Ask still waits; Deny unapproved rejects without an affirmative card. The card copy comes from the live receipt. Installed terminal, Browser Tools, and Computer Use activity did not block under Always approve; Ask showed and resolved one correctly labeled card.

### Reproduction

1. In Settings → Permissions select **Always approve**, Sandbox **Default**, web enabled, subagents enabled, then Apply Changes.
2. Start a fresh session and request a harmless terminal command.
3. Observe that a permission card may still appear. During the stress run its own copy said:
   `Current launch policy: Always approve. This tool will not run until you choose an option...`
4. Run the command affirmatively. Repeat with Browser/Computer Use tool activity.

### Primary code path

- `GrokBuild/Services/GrokCLIService.swift`
  - `GrokPermissionMode`
  - `GrokPermissionLaunchArguments`
- `GrokBuild/Services/GrokProcess.swift`
  - process argument construction
  - `session/request_permission` parsing
- `GrokBuild/Services/ChatStore.swift`
  - `loadPermissionSettings`
  - process launch options
  - `.permissionRequest` handling
- `GrokBuild/Views/SettingsView.swift`
- `GrokBuild/Views/ChatView.swift`
  - permission card and policy explanation
- `Tests/GrokBuildTests/AgentsAndCapabilitiesTests.swift`
- `Tests/GrokBuildTests/ACPClientContractTests.swift`

### Leading hypotheses to prove or falsify

- The mapping correctly emits `--always-approve`, but a later restart path may launch with stale/default settings.
- The CLI may still emit explicit permission requests under Always approve for some tool classes.
- GrokBuild only auto-responds to ACP permission requests when `isYolo` is true; YOLO agent mode is not the same concept as the Settings permission mode.

Capture a redacted runtime launch receipt that proves the effective permission flag for every restart path. Never log credentials or unrestricted environment values.

### Required behavior and tests

- **Always approve:** no blocking approval card for otherwise permitted terminal, browser, file, or Computer Use actions. Explicit deny rules, hooks, and sandbox restrictions still win.
- **Ask:** unmatched tools produce a card and wait.
- **Auto:** follows the CLI's automatic safety classification; dangerous/unmatched requests may ask.
- **Deny unapproved (CI):** unmatched actions are denied without a misleading affirmative card.
- If the CLI emits a permission request despite Always approve, GrokBuild should safely select an allow option automatically unless an explicit deny/sandbox result has already blocked the action. Keep the event receipt visible in tool activity without blocking the turn.
- The card must describe the **effective live process policy**, not merely the current Settings value.
- Add end-to-end launch/restart tests, not only the existing pure argument-mapper assertions.

### Acceptance gate

Run at least one terminal command, one Browser Tools action, and one Computer Use action under Always approve. None may block on an approval card. Then switch a disposable session to Ask and prove one card still appears and responds correctly. Restore Always approve before closeout.

## Repair 3 — UXR-14: configuration reload fractures identity — Fixed

**Fixed:** reload captures the durable backend ID before teardown, queues/coalesces streaming changes, preserves model/agent, and prevents transient process `nil` from overwriting the receipt. A legitimate stale-backend fallback imports the prior transcript and emits one explicit fork note. A final installed relaunch exposed a second lazy-start race—seven persisted DeepSeek messages briefly rendered as an empty in-memory view—so post-start recovery now rehydrates only an empty store from a non-empty durable transcript and never replaces newer live text.

### Reproduction

1. Open a populated Kimi session and record the visible local tab UUID, backend Grok session ID, selected model, and last user/assistant turn.
2. Apply a Browser, Computer Use, permission, MCP, or provider configuration change that restarts the connection.
3. Continue the same task.
4. Compare the saved layout, live `grokSessionId`, and backend history directories. The stress run split between `019fbb20-...` and `019fbb35-...` and left only a partial visible transcript.

### Primary code path

- `GrokBuild/Services/ChatStore.swift`
  - `reloadConfiguration`
  - `performRuntimeReload`
  - `applyRuntimeConfigurationChange`
  - `restartProcess`
  - `resolvedResumeSessionID`
- `GrokBuild/Services/GrokProcess.swift`
  - `start(workspace:options:)`
  - session load/new/fallback receipt
- `GrokBuild/ContentView.swift`
  - `bindTabSession`
  - layout persistence callbacks
- `GrokBuild/Services/SessionLayoutStore.swift`
- `Tests/GrokBuildTests/SessionPersistenceTests.swift`
- `Tests/GrokBuildTests/LifecycleAndSubprocessTests.swift`

### Required behavior and tests

- A runtime configuration reload resumes the same durable backend ID when that backend remains valid.
- The selected model and agent remain attached to the resumed backend.
- Teardown's transient `nil` cannot overwrite the receipt.
- If the CLI legitimately cannot resume and must fork, show an explicit recovery/fork note, persist the new ID intentionally, and import the complete prior transcript before allowing another send.
- Cover reload during idle, reload queued during streaming, reload immediately after a tool-heavy turn, and stale-backend fallback.
- Repeated reloads must not duplicate `Reloaded Grok configuration.` notes or transcript messages.

### Acceptance gate

In Grok, GPT, DeepSeek, and Kimi sessions independently: record backend ID, apply one Settings change/reload, return, send a follow-up, quit/relaunch, and prove that session identity/model/transcript remain coherent. Any intentional fork must be visibly disclosed and lossless.

## Repair 4 — UXR-15: Computer Use close/safety contract — Fixed

**Fixed:** `computer_close_app` maps to the bundled `agent-desktop close-app` primitive, defaults to graceful close, and exposes an explicit optional `force` boolean for the elevated path. Hidden, zero-size, and helper windows no longer outrank the main visible standard window. Kimi entered `7 × 6 =`, read `42` from a fresh accessibility snapshot, closed Calculator gracefully, and proved it absent. The outer acceptance harness opened Calculator once after the model stalled on Spotlight; the entire target/calculate/read/close lane used the repaired Computer Use contract without terminal or AppleScript fallback.

### Reproduction

1. With Accessibility and Screen Recording granted, open Calculator.
2. Use Computer Use snapshot/click/get to enter `7 × 6 =` and verify `42`.
3. Call `computer_press` with `cmd+q`.
4. Current agent-desktop returns a policy error instructing the caller to pass `--force`, but `computer_press` exposes only `combo` and `buildPressArgs` cannot emit force.
5. Menu fallback encounters multiple/hidden Calculator windows and may not identify the main visible application window.

### Primary code path

- `GrokBuildComputerUseCore/ComputerUseCore.swift`
  - `computerUseTools`
  - `buildPressArgs`
- `GrokBuildComputerUseMCP/main.swift`
- `GrokBuild/Services/ComputerUseService.swift`
- `GrokBuild/Resources/Skills/grokbuild-computer-use/SKILL.md`
- `Tests/GrokBuildTests/ComputerUseCoreTests.swift`
- `Tests/GrokBuildTests/ComputerUseIntegrationTests.swift`
- bundled `agent-desktop` contract/version; inspect its current help before selecting the implementation.

### Required behavior and tests

Choose the smallest safe contract that can actually complete an ordinary app-close workflow:

- either expose an explicit boolean force argument and map it to the currently installed agent-desktop syntax with narrowly documented safety behavior;
- or add a dedicated safe close-window/close-application action implemented through visible accessibility state;
- or use another supported agent-desktop close primitive if current help exposes one.

Do not silently force arbitrary destructive shortcuts. The model must request the elevated close action explicitly, and the tool description must explain it. Improve window selection so hidden/zero-size/helper windows do not outrank the main visible standard window. Update the bundled skill and the exact-surface test together.

### Acceptance gate

From a fresh installed-app Kimi session, use Computer Use only to:

1. list apps;
2. identify/open or target Calculator;
3. enter `7 × 6 =`;
4. read back `42` from a fresh snapshot;
5. close Calculator using the repaired callable contract;
6. prove Calculator is no longer running.

No terminal/AppleScript fallback is allowed in this acceptance lane.

## Regression matrix

After fixing the four defects, exercise at minimum:

| Provider/lane | Required proof |
|---|---|
| Grok 4.5 agentic | terminal + edit + tests + diff + final marker; Settings and relaunch persistence |
| Grok 4.5 subagents | two named workers, readable activity, one parent synthesis, final marker, restore |
| GPT 5.6 Terra | Browser Tools open/type/click/read/screenshot plus final marker visible and restored |
| OpenRouter DeepSeek | long one-shot rich result with table/code/math, marker above composer, Settings/relaunch bottom-follow |
| Kimi K3 | Computer Use Calculator 42 and clean close, no terminal fallback |
| Attachments | select exact file, remove wrong chip, grounded answer, no unauthorized edit |
| Permission modes | Always approve non-blocking; Ask blocking; deny rules still enforced |
| Stop/recovery | interrupt a stalled/tool-heavy turn, composer recovers, next short turn succeeds |
| Performance | silent reasoning, streaming, settled rich transcript, and idle; no sustained core pin |

Separate model failures from client failures. A model omitting a requested table or using a forbidden fallback is model behavior when the client faithfully renders the actual result. A backend final answer missing from the client, a mislabeled live policy, or a fractured session receipt is product behavior.

## Build, installation, and proof

1. Add failing tests before each fix where practical.
2. Run focused suites during development.
3. Run the repository's complete `make test` suite before packaging; report the exact test count and failures.
4. Run `git diff --check` and a trailing-whitespace check that includes untracked documentation.
5. Build/package using the repository's current documented flow. Do not trust a stale `.build/GrokBuild.app`; the accepted artifact is `dist/GrokBuild.app`.
6. Quit the installed app and prove its grok/helper children exit.
7. Move `/Applications/GrokBuild.app` to a unique recoverable backup such as:
   `/Users/jimmyschmitz/.Trash/GrokBuild-pre-stress-error-repair-20260731-HHMMSS.app`
8. Install the new `dist/GrokBuild.app` at `/Applications/GrokBuild.app`.
9. Clear quarantine attributes from the new installed bundle.
10. Verify:
    - `codesign --verify --deep --strict --verbose=2 /Applications/GrokBuild.app`
    - SHA-256 parity between `dist/GrokBuild.app/Contents/MacOS/GrokBuild` and `/Applications/GrokBuild.app/Contents/MacOS/GrokBuild`
    - helper signatures and executability
    - quarantine absent
    - no orphaned app/grok/helper processes
11. Run the live regression matrix against the exact installed path.
12. Leave a repaired unique-marker transcript visible above the composer.

## Documentation closeout

Update all three canonical receipts with fixed/open status, exact tests, installed hash, backup path, CLI update receipt, and installed-app proof:

- `ARCHITECTURE.md`
- `docs/UI_ACCEPTANCE_MATRIX.md`
- `docs/UI_UX_REVIEW_2026-07-31.md`

Update this handoff's four defect sections to **Fixed** only after both automated and installed-app acceptance pass. If any defect remains, preserve its raw evidence, explain the exact blocker, and do not declare the overall repair complete.

## Final deliverable format

Lead with the outcome. Report:

- fixes shipped and the architectural cause of each;
- focused and full-suite results;
- installed-app provider/tool matrix;
- exact installed/dist hash and signing result;
- backup path and quarantine state;
- final permission mode/sandbox/capability state;
- remaining product defects versus model behavior;
- exact files changed;
- confirmation that nothing was staged, committed, or pushed.
