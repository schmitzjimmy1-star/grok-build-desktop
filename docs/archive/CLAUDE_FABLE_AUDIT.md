# GrokBuild Desktop — Independent Senior Review (Claude Fable)

Reviewed: `codex/warm-glass-ui` @ `1a8fc22` against `origin/main` @ `3686682`.
Date: 2026-07-30. Read-only pass — no code was changed. Method: full test run, live app launch with process/CPU sampling, five parallel static audits (dead code & target membership, performance, Computer Use, line-level diff review, UI/accessibility), with every headline finding re-verified by hand against the source.

---

## Verdict in one paragraph

The UI overhaul is real and largely well-executed: the status-bar app was removed cleanly with every capability but one rehomed, menus are correct (no selector or key-equivalent errors), the process tree is healthy (one grok child, one helper each, 0.0% idle CPU, clean teardown with zero orphans), and all 262 tests pass. But the branch also introduced two genuine user-facing regressions (thinking trace lost on failed turns; composer draft destroyed on tab switch), the window-frame logic makes the app full-screen forever regardless of user resizing, and — the biggest finding of the review — **Computer Use is currently 100% non-functional in local builds** because `agent-desktop` is bundled best-effort (`|| true`) and does not exist in the bundle or anywhere on this machine. Two of the "262 green tests" actively guard wrong behavior. None of this blocks the branch as a UI milestone; all of it should be fixed before any merge or release.

---

## Verified baseline

| Claim | Result |
|---|---|
| `make test` → 262 tests, 0 failures | **Confirmed** (re-run during this review, 5.3s) |
| Dev bundle `.build/GrokBuild.app`, v0.1.20, `com.grokbuild.app` | **Confirmed** |
| Runtime process tree | **Confirmed healthy**: GrokBuild → `~/.grok/bin/grok` → `grokbuild-browser-mcp` (Python) + `GrokBuildComputerUseMCP`. One of each. CPU 0.0% at T+20s and T+45s. AppleScript quit leaves **zero** survivors. The handoff's runaway-CPU concern does not reproduce at idle. |
| Draft PR [#1](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/1) open, mergeable | **Confirmed** — but `statusCheckRollup` is empty and the fork has **zero Actions runs**, so `pr.yml` (which would run `make test` + `make app` and gate agent-desktop bundling) has never executed. All verification is local-only. |
| Branch state | Clean; only `CLAUDE_FABLE_HANDOFF.md` untracked (and now this file). Neither is in `.gitignore` — decide commit-or-ignore before they get swept into an unrelated commit. |

---

## Q1 — What is genuinely dead or redundant?

### Confirmed dead (zero external references; grep evidence re-verified)

| Item | Location | Note |
|---|---|---|
| `GrokBuildApp.swift` (excluded legacy `@main`) | `GrokBuild/GrokBuildApp.swift` + `Package.swift:22` exclude | Never compiled; duplicates AppDelegate menu wiring and drifts freely (no Edit/Window menus, no Simulate Updates). Contains the only `preferredAppearance` reference in the repo — i.e. that "setting" is dead too. Decide: delete (recommended) or keep as documented fallback; if deleted, drop the `exclude:`. |
| `WorkflowChipBar` + `WorkflowChip` | `ComposerViews.swift:58,76` | **Orphaned by this branch** — live at base (`ChatView.swift:581` @ 3686682). The chip-row removal was deliberate design; the leftover structs are not. |
| `SessionStatusDot`, `ChatSessionRow`, `SessionGearPopover` | `GrokChatChrome.swift:3,19,39` | Dead at base too. |
| `DiffLinesView` | `ChatView.swift:2028` | Dead at base; live renderer is `DiffView` in `PreviewPane.swift:647`. |
| `ChatStore.handleChunk(_:)` | `ChatStore.swift:1427` | Self-labeled "Legacy fallback", zero callers. |
| `ChatStore.modelCapabilityHint(for:)` | `ChatStore.swift:1107` | Orphaned by the model-menu rework in this branch. |
| Dead SidebarView helpers: `openProjectButton`, `appIcon(for:)`, `installedApp(...)`, `open(_:with:)`, `finderURL` | `SidebarView.swift:313-367` | Live copies exist in `ChatView`/`ContentView` — `installedApp` is triplicated verbatim; consolidate to one helper when deleting. |
| `MainWindowLayout.composerMaxWidth = .infinity` | `MainWindowLayout.swift:11-12` | Zero production readers; the real cap is `AppTheme.Layout.composerMaxWidth = 820`. Its only reader is a test that asserts fiction (see Tests below). |
| `SidebarView.isSettingsSelected` | `SidebarView.swift:37,221,226` | Unreachable — sidebar is never rendered while Settings is open (`ContentView.swift:84`). |

### Orphaned notification plumbing (all re-verified by grep)

- `.grokStatusChanged` — posted from `ChatStore.swift:170`, `GrokProcess.swift:1127`, `ContentView.swift:1393`; **zero observers** since `StatusBarController` was deleted. The entire status-broadcast chain (including `GrokProcessState.statusString(for:)`) now shouts into the void, while `ARCHITECTURE.md` still mandates posting it as a convention. Either delete the chain or keep it deliberately as the seam for a future status surface — but say so in the doc.
- `.showMainWindowRequested` — observer in `AppDelegate.swift:69`, zero posters. (The distributed `com.grokbuild.showMainWindow` single-instance path is separate and load-bearing — keep.)
- `.retryConnectionRequested` — receiver in `ContentView.swift:1404`, zero posters. Retry itself survives via the chat error banner (`ChatView.swift:136`), so this is dead plumbing, not lost functionality.
- `.grokBuildCLIUpdated` — posted twice in `GrokCLIUpdater.swift`, zero observers (pre-existing).

### Memory leaks that look like plumbing (pre-existing, found by two auditors independently)

- `GrokProcess.outputStream` — `AsyncStream(bufferingPolicy: .unbounded)` (`GrokProcess.swift:361`), yielded on **every** stdout line (`:865`), **never consumed anywhere**. An unbounded stream with no consumer retains every element: memory grows with session length, per live session. Delete the stream plumbing.
- `GrokProcess.outputLines` (`:211`) — appended per line (`:864`), cleared only on restart, never read. Same fix.
- `startupStderr` (`:851`) — accumulates forever; only used for startup diagnostics. Cap it (~64 KB).

### Keep — looks legacy, is load-bearing

`isLegacyResumeNote`/`filteredPersistedMessages` (restore filtering), `ComputerUseService.legacyGranted` (agent-desktop v1 payloads), `GrokMemoryFlag` (live launch flag), per-tab-model decode fallbacks in `SessionLayoutStore`, `SessionTranscriptRecovery`. **Caution:** `GrokSettingsKeys.noMemory` is *not* a migration — nothing reads the old key, so upgrading users silently lose that preference. Either add a one-shot migration or delete the constant knowingly.

### Assets

- `MenuBarIcon` imagesets and the Makefile/script copy blocks are **deliberately retained and still needed** — `GrokBrandIcon.swift:7-27` reads those filenames for the welcome-screen brand mark and icon fallback. Name is legacy; behavior is live. Do not delete.
- `AppIcon.appiconset` is an **empty placeholder** — all ten entries lack `filename`, no PNGs in the set, so `NSImage(named: "AppIcon")` can never resolve from the catalog; the icon only works via the executable-dir copy of the root `AppIcon.png`. Populate it or remove the dead catalog branch.

### Tests

- `MainWindowLayoutTests.testComposerUsesFullChatColumnWidth` asserts `composerMaxWidth == .infinity` — a green test guarding behavior the app does not have. Delete or repoint at `AppTheme.Layout.composerMaxWidth`.
- Deleting `GrokAuthProbeTests` was legitimate (the probe was removed with zero dangling refs), but `StatusBarMenuTests` took the only coverage of `GrokProcessState.statusString(for:)` — still live code — with it. Move those four assertions into a surviving file, and add coverage for `ChatStore.authRequiredMessage` (now the only auth surface, untested).

### Docs drift (fix in one docs commit)

- `ARCHITECTURE.md:934` anti-pattern "don't store chat history in UserDefaults" vs `:404` documenting exactly that (`GrokBuild.sessionMessages.v1`). Real contradiction; see Q2 for the code-side fix.
- `ARCHITECTURE.md:615` names settings groups "Intelligence… Safety & System" — code and `SettingsTabTests` say `Grok, Tools, Extensions, Controls, Application`.
- `ARCHITECTURE.md:728` claims a 960pt welcome width the code clamps to 760 (see Q4); `:861` still lists `WorkflowChipBar`; the notifications table lists three dead names; the test table lists 12 of 25 files.
- `MainWindowLayout.swift:11` comment "no artificial mid-width cap" is false (820 cap).
- `AGENTS.md:21` + `README.md:77` say agent-desktop is "bundled" — bundling is best-effort and currently absent (see Q3). `BUILDING.md:80` has it right.

---

## Q2 — How can the app carry less weight?

### The master finding (one causal chain, explains most of it)

Every streamed token does: `ChatStore.appendAssistantText` mutates `messages` → `ContentView.body` re-evaluates, because the sidebar reads `session.store.messages` transitively inside `body` (`ContentView.swift:90 → 461` `SessionTitle.auto(from:)`) — for **every** live session. That per-token `ContentView.body` pass then:

1. **Re-scans the entire transcript for diffs** — `.onChange(of: activeStore.messages)` (`ContentView.swift:1330`) → `autoSelectLatestDiffMessage()` (`:881`) → `last(where: { $0.hasDiff })`, where `hasDiff` (`Message.swift:13-18`) runs three full substring searches per assistant message. Prose replies fail the predicate on every message, so the scan is O(entire transcript) **per token** — the clearest quadratic in the app. *(Re-verified by hand.)*
2. **Re-initializes `ChatView`**, whose `@State` default expressions run per struct init: `WorkflowsConfigStore.loadEnabled()` (`ChatView.swift:84`) synchronously opens and char-scans `~/.grok/config.toml` on the main thread, and `VoiceInputService()` (`:65`) allocates an `AVAudioEngine` + `SFSpeechRecognizer` (XPC to the speech daemon). **Per token.** *(Re-verified by hand.)*

**Fixes are small:** change the diff trigger to `.onChange(of: activeStore.messages.count)` (1 line; diffs then select at message boundaries, which is arguably better since mid-stream diffs are incomplete); default `workflowsEnabled = true` and populate in the existing `.onAppear`; make `VoiceInputService` internals lazy; cache sidebar titles keyed on the existing `sessionListRevision`. Risk: low. Benefit: streaming stops degrading with transcript length.

### Ranked remaining items

| # | Sev | Finding | Evidence | Smallest fix | Risk |
|---|---|---|---|---|---|
| 3 | High | `stdoutBuffer` line-split is quadratic (front-`removeSubrange` + `firstIndex` re-scan per line), and `String(data:encoding:)` **silently drops a whole chunk** that ends mid-UTF-8-codepoint | `GrokProcess.swift:830-845`, `:833` | Buffer `Data`, split on byte `0x0A`, decode complete lines. Fixes the latent UTF-8 bug too | Low |
| 4 | High | Unbounded retention: `outputStream` (unconsumed), `outputLines`, `startupStderr` — every CLI byte held ~2.5× per session | `GrokProcess.swift:211,227-228,361,851,864-865` | Delete stream, ring-buffer/cap the other two | Low |
| 5 | High | `persistSessionLayout(saveMessages: true)` (8 call sites: tab select, rename, close, reorder…) re-encodes **every** session's transcript, and each `SessionMessageStore.save` loads the full multi-session map twice and rewrites the whole blob — O(N²) in total bytes, in UserDefaults, undebounced. (Per-chunk saves do **not** happen — prompt-boundary only, and `handleLiveSessionMessagesChanged` correctly saves just one store.) | `SessionMessageStore.swift:13-24`, `ContentView.swift:633-638` | Batch: one load → merge all → one write. Real fix: move transcripts to per-session files under Application Support (also resolves the ARCHITECTURE.md contradiction) | Low-Med |
| 6 | Med-High | One `WKWebView` per Mermaid/LaTeX block, no shared process pool, destroyed/recreated on scroll, and the HTML loads **mermaid/katex from cdn.jsdelivr.net** — message content rendered against third-party CDN script; blank blocks offline | `RichMessageView.swift:568-573,590,636-641,659-660` | Bundle the JS/CSS locally with `baseURL`; share a `WKProcessPool` | Low |
| 7 | Med | Markdown re-parse cost on scroll-in and per state change for visible rows: `NSRegularExpression` compiled per call (6 sites), `AttributedString(markdown:)` per paragraph/list item/**table cell** | `RichMessageView.swift:79,93,103,341,361,480,504-514` | `static let` regexes (3 lines, zero risk); memoize `parse(text)` keyed by content hash | Low |
| 8 | Med | Settings keep-alive is well-designed (only visited panes mount — verified), but visited panes re-evaluate on every `SettingsView.body` pass because each gets a freshly-allocated closure; and four panes independently spawn `grok inspect --json` (~6 spawns where 2 would do) | `SettingsView.swift:214-286`; `GrokCLIService.swift:461-480` | Reuse one stored closure (or `EquatableView`); shared TTL cache for inspect | Low |
| 9 | Low-Med | `SessionNameStore.name(for:)` bridges the whole dictionary twice per session per `ContentView.body`; title-sanitizing regex compiled per call | `ComposerModels.swift:395,427`, `ContentView.swift:454-458` | Cache map + `split(whereSeparator:)` | Low |

**Cleared by the audit (don't chase):** `GrokCLIService` one-shots run off-main and drain both pipes correctly; stderr of the grok child is drained; no timers/pollers leak (24h update loop only); streaming rows deliberately render plain `Text` so the markdown parser never sees partial fences (good, documented in-code); per-chunk UserDefaults writes do not exist. File length alone (SettingsView 5,215 lines) is a maintainability problem, not a measured runtime one — split it for the next engineer, not for the frame rate.

---

## Q3 — How should Computer Use become a trustworthy product feature?

Architecture (verified): GrokBuild only *injects* an MCP config; grok spawns `GrokBuildComputerUseMCP` (stdio JSON-RPC), which spawns the third-party `agent-desktop` CLI **per tool call**. 10 tools implemented in the helper. The chat pill and draft/applied settings pattern are sound. The blockers, in order:

| # | Sev | Finding | Evidence (re-verified) | Smallest fix |
|---|---|---|---|---|
| 1 | **S1** | **agent-desktop is absent** — bundling is `\|\| true` best-effort, and it exists neither in `.build/GrokBuild.app/Contents/MacOS/` nor anywhere on this machine (PATH, Homebrew, `~/.local/bin` all checked). The feature is currently non-functional locally while the helper process runs and the tools register — the handoff's "helper processes prove packaging" was misleading. CI would gate it (`npm install -g agent-desktop` + `test -x`) but **Actions has never run on the fork**. | `scripts/build-dev-app.sh:60`, `build-macos-app.sh:104`; `ls` of bundle | Fail packaging hard (like the helper already does) with the `npm install -g agent-desktop` remedy in the message; add `agent-desktop version` (not just `test -x`) to CI |
| 2 | **S1** | Helper never drains agent-desktop's pipes until exit; the wait loop polls `isRunning` with pipes full → any output over the ~64 KiB pipe buffer **deadlocks the child**, burns the full 60-180s timeout, and reports a bogus "timed out". Deterministic on dense-app snapshots — the most important tool breaks on the most real targets. | `GrokBuildComputerUseMCP/main.swift:374-394` | Drain both pipes concurrently (`readabilityHandler` into locked buffers), then `waitUntilExit()`; escalate SIGTERM→SIGKILL after grace. Same class of bug in `ComputerUseService.runResult` |
| 3 | **S1** | Permission status lies: the bundled/non-bundled branches of `resolvePermissionStatus` are the **identical OR expression** (`\|\|` is commutative), so GrokBuild's own Accessibility grant masks a denied external agent-desktop → UI shows "Ready", guidance suppressed, first click fails. Two tests **enshrine** this as intended. Screen Recording is never probed at all (`CGPreflightScreenCaptureAccess` absent from repo) yet the badge says Ready with screenshots enabled. | `ComputerUseService.swift:339-344,348`; tests `:190-230` | Non-bundled: require `agentDesktopGranted`. Add screen-capture preflight to app + helper; include in `isReady` when screenshots on. Update the two tests — them breaking is the point |
| 4 | **S1** | No way to prove the chain without burning a chat turn — every green indicator is inference. | Settings pane `SettingsView.swift:2328-2452` | One **"Test Computer Use"** button: spawn helper, `initialize` + `tools/call computer_list_apps`, render result or error. Converts the pane from claims to evidence. Highest-value single addition |
| 5 | S2 | Dead safety controls presented as guardrails: "Allow physical mouse actions", "Max steps", "Session name", "Screenshot mode" are persisted and sent as env vars the helper **never reads** (reads only SESSION/POLICY/TIMEOUT/SCREENSHOTS, and SESSION is itself unused); policy "ask" ≡ "auto" (only "deny" enforces) while the card promises "Grok asks before high-risk actions". | app sets `ComputerUseService.swift:143-148`; helper reads `main.swift:34-38`; `enforceActionPolicy:279-283` | Delete the four dead controls; keep deny; add a test asserting env keys == helper's read set |
| 6 | S2 | Cursor installer rewrites `~/.cursor/mcp.json` (another vendor's global config) on **incidental UI events** including opening the pane, destroys user formatting via JSONSerialization round-trip, and leaves permanently stale binary copies after app updates (a test asserts the staleness as correct). | `ComputerUseCursorInstaller.swift:129-137,212-233`; triggers `SettingsView.swift:2297,2469-2516` | Write only on explicit Install/Update; re-copy binaries on mtime/size drift. Medium-term: move out of the app — it also blocks sandboxing |
| 7 | S2 | `ComputerUseIntegrationTests` (563 lines) contains **zero integration** — the helper is an executable target that cannot be imported, so argv construction, tool dispatch, error mapping, and the probe JSON contract are all untested; `parseAccessibilityTrustProbe` is tested against a hand-written literal that can drift from the helper's real output. SKILL.md advertises 6 of 10 tools, and its own suggested first test needs an unlisted one. | `Package.swift:31-38`; `SKILL.md:21-25` vs `:48` | Extract helper logic into a small library target shared with tests; add tool-parity + env-parity tests; list all 10 tools in SKILL.md |
| 8 | S3 | Misc: model-controlled `save_path` is an unvalidated arbitrary write; "Reinstall the latest GrokBuild release" copy is wrong for local builds; every permission row renders gray regardless of state; `agentDesktopPath` hardcoded to `""` on Apply makes the custom-path branch unreachable (and one test tests that unreachable branch); helper answers notifications with `id: null` errors (JSON-RPC violation). | `main.swift:305-314,228-229`; `SettingsView.swift:2346,2623,2792` | Per item — all small |

**Live acceptance checklist once #1-2 land:** bundle carries a runnable agent-desktop (`version` from inside the bundle) → signed via `codesign-app-bundle.sh` (shared bundle-id trick makes one Accessibility grant cover all three; re-grant after every re-sign, CDHash changes) → grok session lists all 10 `computer_*` tools → `computer_snapshot` against Safari with `--include-bounds` (exercises the >64 KiB path — the one that fails today) → click/type round trip → screenshot with Screen Recording denied (error must be comprehensible) → deny-policy negative test → process census across 4 tabs, LRU eviction, and quit.

---

## Q4 — Where can the UI/UX still become more native and polished?

The graphite direction is genuinely well-executed where it's applied — the verdicts below are about finishing it, not changing it.

### Behavioral (fix first)

1. **Composer swallows arrow keys** — `.onKeyPress(.upArrow/.downArrow)` return `.handled` unconditionally (`ChatView.swift:700-719`), so caret movement is dead inside a multi-line draft and ⌥↑/⌘↓ die too. Return `.ignored` when the slash popover is closed and history is nil; bail on modifiers.
2. **Fake traffic lights in sheets** — one working close button styled as a red traffic light next to **two decorative dead circles** (`GrokChatChrome.swift:260-299`; used by Sessions/Memory/SavedWorkflows panels). Sheets don't have traffic lights on macOS; this reads as broken UI and carries the app's only saturated red. Replace with a plain ✕ + `.keyboardShortcut(.cancelAction)`.
3. **Raw CLI stderr as error UI** — `GrokCLIService.swift:390-392` builds ``"`grok plugin list --json` failed with exit code 1.\n<stderr>"`` and 10+ surfaces render it verbatim in red caption text. Keep one plain sentence + `DisclosureGroup("Details")` with the raw output; treat missing-CLI as a first-class empty state.
4. **Settings panes keep stale data after failed refresh** — error is set but collections aren't cleared (5 panes), so users see a stale list with a red line instead of the existing `ContentUnavailableView`. `SessionsBrowserPanel.swift:304-307` already does it right.
5. **Sheets missing Escape/Return** — Create Skill, Imagine, Set Goal lack `.cancelAction`/`.defaultAction`; `DeepResearchSheet` is the correct in-repo template. Exactly one `@FocusState` exists in the whole app — first fields don't focus.
6. **No sidebar-toggle menu item or shortcut** — the persisted preference's only affordance is one small unlabeled button; add View menu + ⌃⌘S.

### Consistency (mechanical, do as a sweep)

- **147 theme-token bypasses outside AppTheme**: 45 `cornerRadius:` literals shipping radii of 2/5/6/7/8/10 against the stated 4/6/8; ~27 raw `.system(size:)` (30, 20, 19, 15, 13, 10.5, 9, 8, 7…) against the 11/14/17 ladder; four different muted grays stacked in the same column (`textMuted` 0.62 / `status` 0.58 / `.secondary` / `.tertiary`); ~44 decorative-color sites concentrated in `ComposerViews` (four differently-colored cards in a row: accent goal, orange aside, blue plan, green question) and two independent diff colorizers; 9 `Color(nsColor: .textBackgroundColor)` system-background patches under the graphite canvas in SettingsView.
- **Accessibility floor**: 16 icon-only controls with no label — including the **send button** (`ChatView.swift:1426`), API-key reveal eye, banner dismiss ✕s, attachment eye toggle. 13 `accessibilityLabel` calls repo-wide. Zero `.focusable()` custom rows; zero reduced-motion checks against 8 animation sites (drop the `.scale` spring on `PermissionCard` regardless); VoiceOver hears nothing when streaming ends (one completion announcement is enough); user/system messages aren't grouped (`MessageBubble.swift:12-29,52-56`); thinking disclosure has a 6pt dead zone (no `contentShape`) and no expanded trait. The Settings sidebar (`SettingsView.swift:183-206`) is the best-executed a11y in the repo — use it as the template.
- **Table cells fixed at 172pt** (`RichMessageView.swift:483`) guarantee truncation on real tables; six horizontal scrollers hide indicators, removing the only cue that code blocks/tables continue sideways.
- **Forced-dark residue**: `AppDelegate.swift:150-155` duplicates the canvas color as raw NSColor components (drift risk — derive from `AppTheme`); the palette is `white.opacity()` throughout, so light mode stays impossible until tokens become semantic. Fine as a deliberate dark-only app; just keep it deliberate.

---

## Regressions introduced by `1a8fc22` specifically

These are the review of "the version I made" — things that worked at `3686682` and don't now. All re-verified in source.

| Sev | Regression | Evidence | Fix |
|---|---|---|---|
| **High** | **Thinking trace lost or mis-attached on failed turns.** Failure path deletes the empty assistant anchor (`ChatStore.swift:872-875`) after `streamingMessageID = nil`, so `thinkingMessageID` falls back to the *previous* turn's answer — the trace renders above an older message — or, on a first-turn failure, disappears entirely, taking the only diagnostic with it. The old tail-rendering never lost it. `ChatTranscriptLayoutTests.testThinkingHasNoAttachmentWithoutAssistantMessage` **asserts the disappearance**. | `ChatView.swift:118-126`; `ChatStore.swift:852-876` | Keep attachment as primary; render an unattached tail `ThinkingBlock` when `thinkingMessageID == nil` but thinking content exists. Update the test to assert the fallback, not the loss. |
| **High** | **Composer draft and all ChatView state destroyed on tab switch** — `.id(activeStore.tabSessionID)` (`ContentView.swift:168`) tears down `ChatView`, resetting `input`, sheet flags, disclosure state, and the chat/preview divider. Type a long prompt, glance at another session, come back: gone. | `ContentView.swift:168`; `ChatView.swift:58-84` | Scope `.id` to the ScrollView (the stated goal was scroll identity only), or hoist `input` into `ChatStore`. |
| Med | **Window size never respects the user.** The autosave name is set and saved but `setFrameUsingName` is never called, and `screenFillingFrame` is applied unconditionally at launch — resize to half-screen, relaunch, full-screen again, forever. Also `screenFillingFrame` isn't clamped to `minimumSize`, so a small display forces a window larger than the screen. | `AppDelegate.swift:158-159,174-185`; `MainWindowLayout.swift:16` | Restore via `setFrameUsingName`; apply the screen-filling frame only when restore returns false; clamp to `minimumSize`. |
| Med | **"View Usage on grok.com…" lost with no new home** — the only status-bar capability not rehomed (all others verified rehomed: sessions, projects, settings, updates, about, login hint, retry). | zero post-image hits for `_s=usage` | Add to the app or Session menu. |
| Med | **Check-for-Updates re-entrancy** — `autoenablesItems` re-enables the item during menu tracking, so the `isEnabled = false` guard is a no-op; concurrent checks/panels can stack. | `AppDelegate.swift:317-320` | `appMenu.autoenablesItems = false` or an `isChecking` flag. |
| Med | **Divider positions reset** — sidebar is now a conditional `HSplitView` child; inserting/removing it (and the `.id` teardown inside the inner split) loses dragged divider positions. | `ContentView.swift:83-126` | Persist positions or avoid conditional insertion. |
| Low | Welcome grid's 960pt cap is dead code — clamped to 760 by the parent transcript column, contradicting `ARCHITECTURE.md:728`; effective card text width ~124pt. | `ChatView.swift:542` vs `:228` | Hoist `welcomeState` out of the capped stack (or accept 760 and fix the doc). |
| Low | Model menu lost its explanatory copy (per-model capability subtitles; "Saved for this project…" effort hint; custom-models pointer). | `ChatView.swift:1518-1560` | One footnote row in the menu restores the per-project hint. |
| Low | Skills pane filter still matches `sourcePath` but no longer displays it — unexplainable search hits. | `SettingsView.swift:1711` vs `:1756-1764` | Filter on visible fields or show the path as caption. |

**Verified fine (don't re-check):** menu selector/keyEquivalent correctness; Makefile/scripts changes are comment-only; `SettingsTab` raw values stable across the reorder (persisted selections survive); Escape-from-Settings intact; sidebar visibility survives the Settings round-trip; inline-math gating and Mermaid reload guards untouched by this commit; streaming never feeds partial markdown to the parser; `clearTurnState()` prevents cross-turn thinking leakage on the success path.

---

## Proposed commit sequence

> **Status 2026-07-30:** Group A landed as `4abe6e8` (thinking tail fallback), `4e22e96` (composer draft), `0fda61c` (frame restore + clamp), `578bec3` (update re-entrancy, View Usage, View menu ⌃⌘S). Live-verified: menu contents, sidebar toggle round-trip, frame restore across relaunch.
> Group B landed as `f80d5a4` (diff detection at prompt boundaries), `5129155` (cheap ChatView init), `be50d7b` (sidebar title cache), `b54e9e3` (Data-based stdout framing + UTF-8 chunk fix; outputStream/outputLines deleted; startupStderr capped), `95689b2` (batched transcript saves + static regexes). Live-verified: ACP handshake and both MCP helpers healthy on the new reader.
> **2026-07-31:** Group C landed as `29e1191` (pipe drain + SIGKILL escalation), `dee9d82` (truthful permissions + Screen Recording preflight), `8c8e0b2` (fail-hard bundling + CI runs the binary), `3a01313` (dead safety controls removed; Allow/Block policy), `838971c` (Test Computer Use button + per-binary rows + honest colors), `55bc74f` (Cursor writes on explicit actions only + stale-binary refresh), `12d013a` (GrokBuildComputerUseCore library + argv/env/SKILL parity tests). agent-desktop 0.6.0 installed and bundled — the dev bundle carries it for the first time. 290 tests pass. **Live acceptance:** end-to-end through the shipped bundle binaries: `tools/list` → 10 tools; `computer_list_apps` round-tripped helper → agent-desktop → real app list. **Live acceptance complete (2026-07-31):** Accessibility and Screen Recording both Granted, all three per-binary rows Granted, and "Test Computer Use" returned the green end-to-end banner in the real UI. Root cause of the permission churn found and fixed in `d4a784c`: `build-dev-app.sh` ignored `SIGN_IDENTITY` and always ad-hoc signed, so every `make run` minted a new CDHash and macOS silently revoked TCC grants; dev builds now sign with the developer's Apple Development identity (TeamIdentifier DD2GCQJVB4) and the `--deep` flag was dropped from the identity path because it would re-sign nested tools with filename-derived identifiers and break the shared-`com.grokbuild.app` trick. `8d21b9d` makes the app actually call `CGRequestScreenCaptureAccess`, without which GrokBuild never appeared in the Screen Recording pane at all. Verified: a subsequent rebuild kept both grants. Only remaining unverified item: a dense-app snapshot >64 KiB (the drain fix is covered by a 256 KiB unit test).
> Group D landed as `9b9dc34` (dead types/helpers deleted; app-finder trio consolidated; fiction test removed), `4e97aba` (orphaned status-broadcast and dead notification wiring deleted), `9bdd764` (legacy GrokBuildApp + exclude deleted; empty appiconset removed; noMemory one-shot migration), `93376fa` (docs truth-up). Group E landed as `8b3494e` (arrow keys, PanelCloseButton replacing fake traffic lights, sheet Escape/Return, stale-pane clears) and `537f7d5` (icon-only control labels incl. send, reduced motion, VoiceOver grouping + turn-complete announcement). 290 tests pass; rebuilt and relaunched clean. **Deferred, deliberately:** the full theme-token sweep (45 radius literals, ~27 raw type sizes, decorative-color triage), focusable custom rows, Mermaid/KaTeX local bundling, and transcripts-out-of-UserDefaults — each is its own pass with visual QA.

Small, independently-testable commits on `codex/warm-glass-ui`, in this order. Each ships with tests + doc updates per `AGENTS.md`; nothing here is a rewrite.

**A. Regression fixes (restore what the overhaul broke)**
1. Thinking-block tail fallback on failed turns + updated `ChatTranscriptLayoutTests`.
2. Composer draft survival: scope `.id` to the scroll container (or hoist `input`).
3. Window frame: restore-then-fill-if-absent + `minimumSize` clamp + test.
4. Menu fixes: `autoenablesItems = false`; re-add "View Usage on grok.com…"; View menu sidebar toggle ⌃⌘S.

**B. Hot-path performance (all one-to-few-line mechanical fixes)**
5. `.onChange(of: messages.count)` for diff detection; cache `hasDiff` if desired.
6. `ChatView` `@State` initializers: constant defaults, populate in `.onAppear`; lazy `VoiceInputService`.
7. Sidebar title caching keyed on `sessionListRevision`; `SessionNameStore` map cache.
8. `Data`-based stdout line splitting (also fixes the UTF-8 chunk-drop); delete `outputStream`/`outputLines`; cap `startupStderr`.
9. Batch `SessionMessageStore.save`; `static let` regexes in `RichMessageView`.

**C. Computer Use to trustworthy (matches the audit table order)**
10. Helper pipe drain + SIGTERM→SIGKILL escalation.
11. Permission resolution truthfulness + Screen Recording preflight + the two tests updated.
12. Fail-hard agent-desktop bundling + CI runs `agent-desktop version`. (Also: enable Actions on the fork or run `pr.yml` steps locally per release.)
13. Delete the four dead safety controls; fix policy copy.
14. "Test Computer Use" button + per-process permission rows + honest colors/copy.
15. Cursor installer: explicit-write-only + stale-binary refresh (or excise it).
16. Extract helper logic into a shared library target; add tool/env-parity tests; SKILL.md lists all 10 tools.

**D. Dead code & docs (mostly deletion; zero behavior change)**
17. Delete confirmed-dead types/helpers/constants + the fiction-guarding test; consolidate the triplicated `installedApp` helper.
18. Delete or consciously keep the orphaned notification chains; rename `StatusMenuNotificationHandlers`.
19. `GrokBuildApp.swift` decision (delete + drop exclude, recommended); `AppIcon.appiconset` populate-or-remove; `noMemory` migration decision.
20. One docs commit: ARCHITECTURE.md (settings groups, persistence contradiction, notifications, welcome width, test table), AGENTS.md/README.md agent-desktop wording, MainWindowLayout comment.

**E. Polish sweep (after the above so it doesn't conflict)**
21. Arrow keys, sheet ✕ replacement, error-copy pattern, stale-pane clears, sheet keyboard shortcuts, focus states.
22. Token sweep: radii → `AppTheme.Radius`, type → ladder, grays → two tokens, decorative-color triage; a11y labels on the 16 icon-only controls; reduced-motion; VoiceOver grouping + completion announcement.

**Mermaid/KaTeX local bundling and the transcripts-out-of-UserDefaults move** are worth doing but are larger; schedule them as their own passes after A-D land.

---

## What this review did not do

- No Instruments run — the two NEEDS-PROFILING questions (eager `Menu` content evaluation in `topBar`; `JSONSerialization` vs buffer split cost share) need one Time Profiler trace during a long streaming turn.
- No live Computer Use verification — impossible on this machine until agent-desktop is installed (`npm install -g agent-desktop`) and re-bundled; the acceptance checklist above is written for that session.
- No screenshot-level visual QA of the new UI (needs an interactive session with screen access); the code-level polish findings stand on their own.
- No edits, commits, or pushes. The branch and draft PR are exactly as the handoff left them.
