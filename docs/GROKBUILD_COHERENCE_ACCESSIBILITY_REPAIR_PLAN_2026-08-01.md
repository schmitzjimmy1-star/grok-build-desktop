# GrokBuild coherence, accessibility, and backend-continuity repair plan

| Field | Value |
|---|---|
| Prepared | 2026-08-01 |
| Status | Slices 0–12 implemented and installed-app accepted; ready for the existing draft PR, with merge/release still separate |
| Scope | Maintained SwiftUI app, current Grok CLI 0.2.118 contract, installed-app acceptance, and every unresolved hole from the Settings/startup/performance/backend-CPR audit |
| Canonical worktree | /Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop |
| Canonical branch | codex/warm-glass-ui |
| Publication remote | personal → https://github.com/schmitzjimmy1-star/grok-build-desktop.git |
| Preserved upstream | origin → https://github.com/rimusz/grok-build-desktop.git |
| Installed acceptance target | /Applications/GrokBuild.app |

## 1. What this plan is for

This is the implementation contract for making GrokBuild feel like one coherent, native project workbench instead of several individually competent surfaces that occasionally disagree about identity, state, or time.

The repair is successful only when a person can answer the following questions from the visible app without reverse-engineering process arguments or preference files:

1. Which project and tab am I in?
2. Which local transcript am I looking at?
3. Which Grok backend session, if any, is this tab attached to?
4. Which model and agent were requested, inherited, restored, and confirmed live?
5. Which Settings changes are drafts, which are saved, which are applied to new sessions, and which are confirmed in the current process?
6. If continuity is uncertain, what is safe to do next without destroying work?

The target is not decorative polish. It is legible truth, bounded recovery, keyboard and VoiceOver completeness, predictable startup, and measured responsiveness. Warm glass stays. Mystery meat state goes.

## 2. Authority, boundaries, and relationship to existing documents

This document converts the completed read-only audit into a sequenced repair specification. It does not itself authorize destructive session surgery, credential changes, broad history rewrites, publication to upstream, or release distribution.

The governing reading order remains:

1. CANONICAL_WORKTREE.md
2. AGENTS.md
3. ARCHITECTURE.md
4. this plan
5. docs/UI_ACCEPTANCE_MATRIX.md
6. docs/UI_UX_REVIEW_2026-07-31.md
7. docs/UI_STRESS_ERROR_REPAIR_HANDOFF_2026-07-31.md

The older Fable documents remain useful historical evidence:

| Document | Role after this plan |
|---|---|
| docs/FABLE_5_AUDIT_FINDINGS.md | Prior architectural evidence; do not treat old status as current proof |
| docs/FABLE_5_IMPLEMENTATION_PLAN.md | Completed and deferred historical slices |
| docs/FABLE_5_LIGHTWEIGHT_DECISIONS.md | Dependency and weight constraints that still apply |
| docs/UI_UX_REVIEW_2026-07-31.md | Earlier UI findings and settled repairs |
| docs/UI_STRESS_ERROR_REPAIR_HANDOFF_2026-07-31.md | Earlier hostile-stress closeout and regression patterns |
| GROKBUILD_SETTINGS_STARTUP_BACKEND_CPR_HANDOFF.md in the parent folder | Audit mission and raw investigation procedure; this plan owns the resulting repair design |

If a later implementation discovers contradictory current evidence, update this plan and ARCHITECTURE.md in the same change. Do not silently code around a stale premise.

## 3. Verified baseline and evidence quality

The audit began from a clean canonical worktree at commit d1238c37b246295017b203d8b0cc67cf77e22400. The installed signed app was stamped from clean ancestor f7cb31837bd48685fe5338342ef489ffb6b313e9. The installed and distribution executables matched at SHA-256 464e2cd2bdcfa7e1ba2b94a3b442ca35677e25a00a7cab8b10fd09b78f84ccd8.

The installed Grok CLI reported 0.2.118 on the stable channel with no update available. A read-only process snapshot showed one GrokBuild app, one Grok agent process, the browser MCP child, and the Computer Use MCP child. Five one-second samples showed zero idle CPU for the app and agent. That clears an idle-spin suspicion only; it does not clear launch, restore, pane-load, transcript-render, or tab-switch latency.

At the visible endpoint of the audit:

- The selected project was Grok Git on main.
- The selected local tab UUID was 0DBC08A8-C15A-420D-81E7-560A6610EE01.
- The visible and requested model was Grok 4.5.
- The saved backend ID was 019fbac7-3969-7901-ac73-da9b35869782.
- The live process arguments requested general-purpose, memory enabled, always approve, reasoning effort low, model grok-4.5, and ACP stdio.

Those receipts prove that the visible model label and current process launch agreed at that moment. They do not prove transcript continuity.

### 3.1 The continuity failure

The selected local tab contained 18 messages, including the Cubs conversation. Its saved/current backend history contained only three rows: one system row and two synthetic rows, with no real user/assistant exchange and a summary count of zero. Recent visible prompts instead appeared in backend session 019fb99b-f49e-7590-8e1d-a74f8d84082f, which held 43 chat records and also used grok-4.5.

The local tab was not a simple copy of that second backend either. Earlier prompts came from at least one other history. The transcript is therefore composite or otherwise divergent. Blindly rebinding the tab to whichever backend contains the newest matching prompt would manufacture false continuity and risk sending private follow-up context to the wrong conversation.

This is the P0 product defect:

> The app can present a locally coherent transcript while its durable backend identity points at a history that does not contain that conversation.

### 3.2 Confirmed implementation gaps

The audit also confirmed:

- SessionTranscriptRecovery does not attempt legacy matching when a non-nil backend ID exists but has no recoverable conversation.
- SessionRestorePolicy describes an MRU fallback but selects the candidate with the largest transcript via SessionMessageStore.messageCount.
- A restored saved model that is absent from the initial catalog can be ignored by ChatStore.applyTabModel.
- GrokProcess treats session/set_model success without an echoed effective model as confirmation.
- Saving a global default model writes the CLI config for future sessions, but GrokBuild can reuse a 60-second catalog cache and does not explicitly refresh or propagate the new default.
- Agents and Permissions expose Save or Apply semantics while several values are already persisted by @AppStorage.
- Browser can briefly announce Setup needed before asynchronous readiness is known.
- MCP configuration supports more CLI structure than the UI preserves, including argument boundaries, environment variables, and HTTP headers.
- Compatibility parsing expects old top-level arrays while Grok CLI 0.2.118 emits an externalCompat object with cells.
- Settings panes stay mounted after first visit, retaining high-water state and work.
- Session selection rewrites all persisted transcript blobs synchronously.
- Startup repeatedly loads the full transcript map and may scan and sort backend histories.
- Rich completed messages can repeatedly parse markdown, math, and Mermaid and create WebKit-backed views.
- Streaming scroll logic can retry while a reader has intentionally moved away from the bottom.

### 3.3 Measured audit corpus

At audit time, the profile contained:

- 24 saved layout records;
- 33 local transcript blobs totaling 128,256 bytes;
- a preferences plist of 159,260 bytes;
- 121 Grok Git backend histories totaling about 28 MB.

The installed app occupied roughly 48–74 MB early in the run and settled around 109 MB after visiting the complete Settings surface. That is high-water evidence, not proof of a leak. Computer Use accessibility round trips measured about 3.8 seconds for Skills, 2.3 seconds for Marketplace, and roughly 1.1–1.8 seconds for ordinary panes. Those numbers include automation/AX overhead and therefore require signposts before product-only conclusions.

## 4. Product invariants

Every implementation slice must preserve these invariants.

### 4.1 Identity is a chain, not a label

A tab has at least four identities:

1. Local tab UUID.
2. Workspace/project UUID and path.
3. Local transcript generation and opaque verification tag.
4. Grok backend session ID and opaque history-verification tag.

The UI may abbreviate them, but the app must retain and reconcile all four. A matching model name is not evidence that the transcript is attached to the right backend.

### 4.2 Requested is not confirmed

For model, agent, reasoning effort, permission mode, browser, Computer Use, and MCP configuration, GrokBuild must distinguish:

- inherited default;
- saved tab or project override;
- draft value in Settings;
- persisted value for future processes;
- launch request;
- live-confirmed value;
- unknown or unsupported value;
- failed application.

No green badge may collapse those states into “Ready” without a receipt appropriate to the claim.

### 4.3 Local work is never discarded to make state look clean

If local and backend transcripts diverge, preserve both. Never clear UserDefaults, remove ~/.grok/sessions, truncate a transcript, or reassign a backend ID as a generic repair. Recovery produces a new durable mapping or a user-confirmed fork; it does not erase inconvenient evidence.

### 4.4 Startup is deterministic and explainable

Cold app launch first obeys an explicit App setting:

- **Resume last work** — default;
- **Start a new tab** — use current new-session defaults without destroying or hiding saved tabs.

When Resume last work is selected, the startup selection order is:

1. Reopen the explicitly selected saved tab when it still belongs to the saved workspace and has local content or a verified backend binding.
2. Otherwise select the most recently accessed viable tab in that workspace.
3. Otherwise open a new local tab using current new-session defaults.

Transcript length is never a restore priority. If the chosen tab differs from the saved selection, a calm one-line restore reason is available in the tab details and accessibility description.

Reopening a closed window while the process remains alive preserves the current in-memory tab regardless of the cold-launch preference.

### 4.5 Accessibility state and visual state are the same state

Every status communicated through color, icon, animation, or spatial placement must have a text equivalent. Every interactive control must have a meaningful accessibility label, role, value, enabled state, and, when needed, help text. Keyboard order must follow the visual task order.

### 4.6 Lightweight remains a design constraint

Use Swift, SwiftUI, AppKit, Foundation, Security, OSLog, and existing process infrastructure. Do not add a database, analytics SDK, state-management framework, markdown engine, or third-party accessibility layer to solve problems the platform already handles.

## 5. Canonical state vocabulary

The app currently uses words such as Ready, Applied, Saved, Setup needed, and Active with inconsistent evidence behind them. Replace ad hoc strings with a small shared vocabulary.

| State | Meaning | Allowed visual treatment |
|---|---|---|
| Checking | A bounded read is running and no conclusion exists yet | Neutral progress indicator; never red |
| Draft | Local controls differ from persisted configuration | Neutral “Unsaved changes” |
| Saved | Persisted for future use, not necessarily live | Blue or secondary confirmation |
| Restart required | Saved change needs a process restart | Informational action |
| Applying | A bounded write/restart is in progress | Progress plus disabled duplicate action |
| Live | Verified against the current process or authoritative runtime | Green only with receipt |
| Partially live | Some sub-capabilities are verified; others are not | Amber and explicit count |
| Unavailable | Authoritative check says capability is absent | Red only if action is blocked |
| Failed | An attempted action failed | Error text with retry/details |
| Unknown | No current receipt, unsupported schema, or stale result | Neutral question-mark treatment |

Use sentence case. Do not use a warning color for normal loading. Do not show a success color for merely persisted preferences.

## 6. Target architecture

The repaired data path is deliberately explicit:

~~~text
Visible tab and controls
        │
        ▼
SessionPresentationState
        │
        ├── local tab UUID + workspace
        ├── transcript generation/opaque tag
        ├── requested model/agent/effort
        └── continuity state
        │
        ▼
SessionBindingCoordinator
        │
        ├── durable SessionBindingRecord
        ├── GrokLaunchReceipt
        ├── ACP session/model receipts
        └── backend history opaque tag
        │
        ▼
GrokProcess and on-disk Grok history
~~~

Settings uses the parallel contract:

~~~text
Controls → draft value → validation → persisted value
                                   ├── future sessions only
                                   └── apply/restart → live receipt
~~~

### 6.1 New or expanded domain types

Names may change during implementation, but their responsibilities must not collapse back into view-local booleans.

**SessionBindingRecord**

- local session UUID;
- workspace UUID and keyed opaque tag of the normalized workspace path;
- backend session ID, if known;
- binding generation;
- local transcript generation and versioned opaque verification tag;
- backend versioned opaque verification tag or verified-prefix tag;
- continuity status;
- date verified;
- verification source;
- previous backend ID when a recovery fork occurred.

**SessionContinuityStatus**

- localOnly;
- backendOnly;
- verifying;
- verified;
- diverged;
- compositeSuspected;
- backendMissing;
- recoveryForked;

**ModelResolutionReceipt**

- app default for new sessions;
- workspace default, if set;
- saved tab override, if set;
- requested launch model;
- last model-set request;
- live-confirmed model, if echoed or read back;
- confirmation source and time;
- status: inherited, requested, confirmed, unsupported, rejected, or unknown.

**RestoreDecision**

- selected local session UUID;
- decision reason;
- rejected candidate reasons;
- timestamp;
- whether a new tab was created;
- whether backend start is deferred.

**SettingsValueState<Value>**

- draft;
- persisted;
- applied;
- live;
- validation result;
- requiresRestart;
- last operation receipt;

These should be ordinary Sendable value types with pure resolution logic and focused tests.

### 6.2 Ownership

| Concern | Owner after repair | Existing code to evolve |
|---|---|---|
| Restore choice | SessionRestorePolicy | GrokBuild/Services/SessionRestorePolicy.swift |
| Local/backend binding | SessionBindingCoordinator or a narrowly named service | ChatStore, SessionTranscriptRecovery, GrokSessionTranscriptImporter |
| Layout metadata | SessionLayoutStore | GrokBuild/Services/SessionLayoutStore.swift |
| Transcript blobs | File-backed SessionMessageStore | GrokBuild/Services/SessionMessageStore.swift |
| Model truth | ChatStore plus GrokProcess receipt | ChatStore.applyTabModel, GrokProcess session/set_model |
| Settings status | Shared settings state and receipt views | GrokBuild/Views/SettingsView.swift plus existing settings stores |
| CLI schema normalization | GrokCLIService | listExternalCompat and MCP commands |
| Performance telemetry | OSLog signposts | ContentView, ChatStore, Settings loaders, rich rendering |

ContentView remains orchestration, not the owner of reconciliation algorithms. SettingsView remains composition, not a five-thousand-line home for every state machine.

## 7. Workstream A — P0 session continuity and safe backend binding

This workstream blocks any claim that wrong-tab or wrong-LLM behavior is fixed.

### A1. Compute transcript provenance before resuming

Before ChatStore passes a saved backend ID to GrokProcess, compare bounded opaque local tags with the exact candidate backend history. Verification tags use normalized roles, keyed message tags, and relative order. Ignore synthetic system and recovery-note rows. Never log message content.

“Stable message content hashes” here means a versioned keyed HMAC, not plain SHA-256. Generate a per-install random comparison key in Keychain and compute HMAC-SHA256 over normalization-version, role, order, and content. Never export the key or tags. If persistence is unnecessary for a comparison, keep tags in memory only. A missing/rotated key invalidates old tags and triggers re-verification; it never turns into a mismatch repair automatically.

Verification is bounded and versioned:

- parse only the exact bound backend in the normal path;
- fully stream and normalize up to 2 MB or 2,000 conversational rows off-main;
- beyond that size, continue only within a five-second cancellable verification task and classify an unfinished result as verificationIncomplete, never verified;
- record normalization and HMAC schema versions;
- do not use a last-prompt-only tag as identity evidence.

Classify the relationship:

| Relationship | Required behavior |
|---|---|
| Exact or verified prefix match | Resume the backend and mark verified |
| Empty local transcript, valid backend | Resume and import backend transcript |
| Local transcript only, no backend ID | Start a new backend lazily on first send |
| Backend missing or unreadable | Keep local transcript; offer retry or safe fork |
| Local/backend divergence | Do not send; show continuity action |
| Evidence of multiple backend histories in one local tab | Mark composite suspected; never auto-rebind |
| Backend contains only synthetic rows | Treat as no conversational continuity |

The comparison must be bounded by message count and bytes. It should run off the main actor and return a value-type result. It must not scan 121 histories on every tab restore.

### A2. Add an explicit continuity gate before send

Composer submission is permitted only when:

- the tab is local-only and a new backend can be created;
- the binding is verified;
- or the user explicitly chose a safe fork after divergence.

For diverged or composite tabs, keep the transcript fully readable and the composer text editable, but replace Send with a short recovery affordance. Preserve any drafted text.

The visible recovery card should say what is known without pretending the app knows which history is “right”:

> This tab’s saved conversation does not match its Grok backend. Your local messages are safe. Relink to a verified history, continue as a new conversation, or view details.

Actions:

- **Continue as New** creates a new backend on the next send, keeps the local transcript, records previous IDs, and adds a non-model system event outside the conversational prompt.
- **Relink** lists only candidate histories with evidence: matching turns, workspace, model, last activity, and mismatch count. It requires an explicit selection.
- **View Details** exposes redacted IDs, dates, model receipts, message counts, and verification reasons.
- **Cancel** leaves state untouched.

Do not offer “Use newest automatically.” Newest is not identity.

### A3. Repair recovery policy

Evolve GrokBuild/Services/SessionTranscriptRecovery.swift so a known backend ID with an empty or synthetic-only history is not treated as sufficient continuity. The service should accept a reconciliation result rather than merely checking whether an ID exists.

Keep legacy matching one-shot and bounded. It may suggest candidates but may not mutate a binding when:

- more than one backend has meaningful matches;
- the local transcript contains turns from multiple candidates;
- workspace evidence disagrees;
- or the match is based only on a common short prompt.

Persist recovery as an append-only relationship: old backend ID, new backend ID, reason, date, and versioned opaque local-transcript verification tag. That makes later diagnosis possible without storing raw prompts or plain content hashes in logs.

### A4. Prevent teardown and fallback from erasing durable truth

Retain SessionIdentityPersistencePolicy.shouldPersistChangedSessionID. Expand tests so:

- process teardown cannot replace a durable backend ID with nil;
- a failed resume cannot silently replace the old ID until the new fork has a receipt;
- a new backend ID is persisted atomically with its recovery relationship;
- closing a tab removes only GrokBuild’s local tab record after the existing confirmation contract, never Grok history on disk;
- a process restart caused by Settings preserves the same verified binding or visibly falls back to recovery.

### A5. P0 source and test map

Primary source:

- GrokBuild/ContentView.swift: restorePersistedSessions, selectSession, bindTabSession, ensureSessionStarted, persistSessionLayout.
- GrokBuild/Services/ChatStore.swift: prepare, start, restartProcess, resolvedResumeSessionID, persisted-message recovery.
- GrokBuild/Services/GrokProcess.swift: session load/new, session/set_model, launch and ACP receipts.
- GrokBuild/Services/SessionTranscriptRecovery.swift.
- GrokBuild/Services/GrokSessionTranscriptImporter.swift.
- GrokBuild/Services/SessionLayoutStore.swift.
- GrokBuild/Services/SessionMessageStore.swift.
- GrokBuild/Views/ChatView.swift and GrokBuild/Views/GrokChatChrome.swift for the continuity gate and details.

Tests to extend:

- Tests/GrokBuildTests/SessionPersistenceTests.swift.
- Tests/GrokBuildTests/GrokSessionReplayTests.swift.
- Tests/GrokBuildTests/GrokSessionTranscriptImporterTests.swift.
- Tests/GrokBuildTests/LifecycleAndSubprocessTests.swift.
- Tests/GrokBuildTests/ChatTranscriptLayoutTests.swift.

### A6. P0 acceptance

- A verified local/backend pair resumes and can send.
- A local-only tab starts a new backend without losing its transcript.
- A wrong, missing, empty, or synthetic-only backend cannot receive a prompt behind a green model badge.
- A known non-nil but wrong backend ID enters divergence handling rather than bypassing recovery.
- A composite transcript is detected in a deterministic fixture and cannot be auto-rebound.
- Recovery survives app quit/relaunch.
- No test or manual repair deletes a Grok history.

## 8. Workstream B — deterministic startup and honest restore

### B1. Make MRU mean MRU

In GrokBuild/Services/SessionRestorePolicy.swift, replace the transcriptCandidates.max-by-message-count fallback with the first viable candidate in the already sorted recent-session order. A 500-message tab touched last week must not outrank a 10-message tab used one minute ago.

The policy should be a pure function over an input snapshot containing all required metadata. It must not call SessionMessageStore during candidate comparison. Precompute viability and counts once.

Required restore reasons:

- savedSelectionVerified;
- savedSelectionLocalTranscript;
- workspaceMRUVerified;
- workspaceMRULocalTranscript;
- createdNewBecauseNoViableTab;
- repairedMissingWorkspace;
- refusedDivergedSelection.

Persist the RestoreDecision only as bounded diagnostic metadata. Do not create a noisy chat row.

### B2. Stop converting inheritance into an override

Current restore and selection paths can resolve record.model == nil to a workspace default before bindTabSession. ChatStore.applyTabModel then treats the resolved value as explicit, and persistSessionLayout can write it back as a per-tab model. That freezes a formerly inherited tab to whatever default happened to exist at restore time.

Preserve three separate inputs:

- savedTabModel: optional and remains nil when the tab inherits;
- workspaceDefaultModel: optional;
- appDefaultModel: required fallback.

Resolve them for launch without overwriting savedTabModel. Persist a tab override only after an explicit per-tab model action. Add the same protection for agent inheritance.

### B3. Defer expensive work until the selected tab needs it

At launch:

1. Load layout metadata once.
2. Load the selected workspace and compute RestoreDecision.
3. Show the shell, sidebar metadata, and selected-tab placeholder.
4. Load the selected transcript off-main.
5. Verify or classify its binding.
6. Start its Grok process only when continuity permits.
7. Hydrate non-selected transcripts and processes lazily.

Do not start all restored tabs. Retain the four-process LRU cap, but make process start demand-driven and visible through per-tab status.

### B4. Make restore explainable without nagging

Add a small, dismissible restore line beneath the tab chrome only when:

- GrokBuild chose a tab other than the last saved selection;
- a local-only tab is waiting for a backend;
- a binding needs attention;
- or a saved model could not be requested.

Examples:

- “Restored your most recently used tab.”
- “The last tab was unavailable, so GrokBuild opened the next recent tab.”
- “Messages restored locally; Grok will start when you send.”

VoiceOver reads the line once when it appears. It must not steal keyboard focus.

### B5. Startup acceptance

- Quit/relaunch returns to the exact explicitly selected viable tab.
- Closing/reopening the window without quitting keeps current in-memory selection.
- Start a new tab preference creates one local-only tab with current defaults while preserving saved work in the sidebar.
- Rapid A → B switch followed by quit restores B after persistence completes.
- Empty saved selection falls back to true MRU, never longest transcript.
- Missing workspace and stale backend cases choose deterministically and explain why.
- Existing inherited tabs continue following new-session defaults only where policy intends; they are not silently converted into overrides.
- Startup reaches an interactive window without waiting for all transcripts, histories, Settings panes, or model providers.

## 9. Workstream C — model, agent, effort, and process truth

### C1. Define precedence once

For a genuinely new tab:

1. Explicit project default.
2. Current CLI/app default for new sessions.
3. Built-in safe fallback only if discovery fails.

For an existing tab:

1. Explicit saved tab override.
2. Otherwise the inherited default according to the tab’s durable inheritance policy.

Never use the selected sibling tab as a default source.

The saved override is user intent, not runtime proof. Persist intent separately from the last confirmed execution state. A known rejected choice must not remain the active picker value; preserve it in the failure receipt while returning the active selection to the last confirmed value. If the app quits while a request is genuinely pending, relaunch may request that saved intent again, but the UI remains Requested until the new process confirms it.

The UI must label:

- **Default for new chats** in Settings;
- **This tab** in the workbench picker;
- **Requested** while process negotiation is pending;
- **Live** only after authoritative confirmation;
- **Unknown** when the CLI does not echo or expose effective state.

### C2. Make model confirmation honest

GrokProcess must not turn a successful session/set_model response into a confirmed model unless the response echoes an effective model or a follow-up read proves it. A successful write with no readable effective state means requested, not confirmed.

Refactor ChatStore.setModel so it no longer mutates and persists currentModel as though confirmed before ACP completes. Refactor restoreSessionSelection so loading a session does not issue a hidden second model force merely to make the UI match saved state. Every model transition must pass through the same generation-bound reducer.

If ACP provides no model read-back for this CLI version:

- show “Requested Grok 4.5”;
- retain the exact launch argument or set-model receipt;
- do not show a green “Live Grok 4.5” claim;
- file the limitation in the App/diagnostics details.

If the backend rejects the model, revert the control to the last confirmed value or present Unknown with the error. Never leave the rejected choice looking active.

### C3. Preserve unknown saved models

A saved model absent from the initial catalog remains visible as “Saved model: identifier — unavailable in current catalog.” Do not silently substitute another model. Offer:

- retry catalog;
- choose a replacement for this tab;
- continue with the saved identifier if the CLI accepts it.

The model catalog should expose source and freshness. Refresh after:

- saving the global default;
- saving provider credentials;
- adding/removing a custom model;
- CLI update;
- explicit Retry;
- a stale-cache launch mismatch.

### C4. Default propagation

The Models pane currently writes the CLI default and describes it as future-sessions-only, which is directionally correct. Complete the contract:

1. Validate and persist through the existing config repository.
2. Invalidate or refresh GrokModelCatalog.
3. Update the app’s new-session default receipt.
4. Do not mutate explicit existing-tab overrides.
5. For inherited, not-yet-started tabs, display the new inherited default.
6. For running inherited tabs, show “Restart to use default X” rather than changing the label before the process.

### C5. Agent and effort symmetry

Apply the same resolution language to agents and reasoning effort:

- global agent default;
- optional tab override;
- workspace effort default;
- launch request;
- live receipt where available.

The current Agents picker writes @AppStorage before Save Default. Replace it with a real draft or remove the redundant Save button. The preferred design is a draft with Cancel and Save Default because changing agent can affect future process launches.

### C6. Model/agent acceptance

- Three tabs with different explicit models restore their own values.
- An inherited tab remains inherited after restore and default changes.
- A model absent from the first catalog is not silently replaced.
- Requested and confirmed model states are distinguishable visually and in accessibility value.
- A failed set-model action cannot leave a false success label.
- Process launch arguments, tab receipt, and backend receipt are available in one redacted details view.

## 10. Workstream D — persistence and startup performance

### D1. Move transcript blobs out of the preferences hot path

UserDefaults is appropriate for small preferences and layout metadata, not a growing dictionary of every transcript blob. Evolve SessionMessageStore to store one atomic file per local session under the app’s Application Support directory.

Suggested shape:

~~~text
Application Support/GrokBuild/
├── Transcripts/
│   ├── <local-session-uuid>.json
│   └── ...
├── Bindings/
│   └── session-bindings.json
└── Diagnostics/
    └── last-restore.json
~~~

Requirements:

- create directories with owner-only permissions;
- write to a temporary sibling file and atomically replace;
- encode a schema version and transcript generation;
- load one requested transcript without decoding all others;
- expose metadata such as message count and modified date without parsing full message bodies;
- serialize writes through an actor or equivalent single writer;
- coalesce rapid streaming updates;
- flush at stable boundaries: accepted user send, completed assistant turn, recovery fork, tab close, app termination;
- never block tab selection on a full transcript-map rewrite.

### D2. Safe migration

Migration from the existing UserDefaults dictionary is copy-first:

1. Detect legacy transcript data.
2. Decode it once off-main.
3. Write every transcript atomically to the new store.
4. Verify count, session IDs, message counts, and in-memory keyed verification tags.
5. Write a migration-complete marker with schema version.
6. Continue retaining legacy data for at least one successfully launched release.
7. Remove legacy data only in a later, separately reviewed cleanup after rollback support is no longer needed.

If any file fails verification, leave the entire legacy dictionary intact, retain successfully written files as harmless candidates, and retry later. Never partially declare success.

### D3. Make persistence incremental

ContentView.persistSessionLayout should write:

- small layout metadata through SessionLayoutStore;
- only transcripts whose generation changed;
- only binding records whose generation changed.

Session selection should update lastAccessed and selected IDs without encoding message arrays. Make persistence completion observable for the rapid-switch-and-quit test.

### D4. Bound backend history discovery

Do not sort or parse up to 200 histories during ordinary restore. Maintain a small candidate index derived from non-secret metadata:

- backend ID;
- keyed opaque workspace tag;
- modified date;
- model;
- message count;
- bounded versioned last-user-message HMAC tag.

Refresh the index incrementally when a recovery flow actually needs it. Legacy matching is an explicit recovery operation, not startup tax.

### D5. Performance instrumentation

Use OSLog and os_signpost with redacted metadata. Required spans:

- appLaunchToWindow;
- layoutLoad;
- restoreDecision;
- selectedTranscriptLoad;
- continuityVerification;
- processSpawnToACPReady;
- firstSendToFirstChunk;
- finalChunkToSettledRender;
- tabSwitchToInteractive;
- settingsPaneLoad by pane;
- modelCatalogLoad;
- providerCredentialMetadataLoad;
- richMessageParse;
- mermaidRender;
- transcriptWrite.

Never record prompts, rendered content, secrets, headers, environment values, absolute private file paths, or raw session histories.

### D6. Initial budgets

Budgets are release gates, not universal hardware promises. Measure on the same Mac, warm and cold, with the audit corpus.

| Operation | P50 target | P95 target | Hard failure |
|---|---:|---:|---:|
| Warm app open → interactive shell | ≤ 350 ms | ≤ 700 ms | > 1.2 s |
| Selected transcript placeholder → readable text | ≤ 250 ms | ≤ 600 ms | > 1.0 s |
| Tab switch → controls interactive | ≤ 100 ms | ≤ 250 ms | > 500 ms |
| Ordinary Settings pane switch after first data load | ≤ 100 ms | ≤ 250 ms | > 500 ms |
| Skills cold load | ≤ 500 ms | ≤ 1.0 s | > 1.5 s |
| Marketplace cold load | ≤ 700 ms | ≤ 1.2 s | > 2.0 s |
| Transcript incremental write | ≤ 25 ms main-thread work | ≤ 50 ms | any full-map rewrite |
| Idle app and one idle agent | near 0% CPU | < 1% sustained | sustained spin |

Collect at least ten runs per lane after a warm-up, report sample count and hardware, and separate automation overhead from product duration.

These are provisional interaction budgets. Slice 0 may revise a number only from repeatable signpost evidence and must record the rationale before optimization begins. Additional installed gates are cold first-usable-window p95 ≤ 3 seconds, 1,000-message restore/reconciliation p95 ≤ 1 second with no interaction-path main-thread stall over one 60 Hz frame, ten-minute idle CPU below 2% per owned process, zero orphan children, and settled RSS growth below 10% after repeated navigation.

### D7. Performance acceptance

- Selecting a tab never reads and rewrites every transcript.
- Startup decodes layout once and only the selected transcript eagerly.
- Legacy backend matching does not run in the ordinary happy path.
- Settings pane memory can be reclaimed or reduced after navigation.
- No main-thread Keychain/config/process read is introduced.
- Performance evidence includes signposts and settled memory/CPU, not vibes and one lucky sample.

## 11. Workstream E — one Settings truth contract

Fourteen bespoke implementations created most of the semantic drift. Repair the shared contract first, then migrate panes.

### E1. Apply scopes

Introduce a small SettingsApplyRequest next to, not inside, the existing ConfigurationChange type. It declares:

- configuration generation;
- affected capability;
- persistence owner;
- apply scope: externalConfigOnly, futureSessions, activeTabRestart, or allEligibleLiveTabs;
- whether a process restart is required;
- whether a permission prompt or trust confirmation is required;
- redacted summary;
- pending, success, partial, or failure receipt.

Route it through SettingsView → ContentView.handleConfigurationChange → ChatStore.reloadConfiguration. A queued reload during streaming remains queued and visibly says so. The receipt is bound to the exact tab UUID, backend ID, and process generation so an old completion cannot paint a new process green.

ConfigurationChange should remain the typed model/runtime-impact signal it already is. Do not turn it into a generic bag of every Settings control.

### E2. Shared pane state

Each editable pane uses SettingsValueState rather than @AppStorage-bound controls:

1. Load persisted and applied values.
2. Initialize a separate draft.
3. Validate draft changes locally.
4. Enable Apply only when draft differs and validation passes.
5. Persist atomically on Apply.
6. Trigger only the declared scope.
7. Re-read applied state.
8. Match it against the live session receipt when applicable.
9. Offer Revert while dirty and Retry after failure.

Direct actions such as installing a plugin, granting a macOS permission, running diagnostics, or writing a memory note are not fake Apply operations. They get their own row-local progress and result.

### E3. Shared components

Add small private or internal SwiftUI components near the existing SettingsToggleRow:

- SettingsPaneStateHeader: Draft, Saved, Restart required, Live, Unknown.
- SettingsApplyBar: Revert, Apply, affected-scope text, progress, result.
- SettingsLoadStateView: checking, content, empty, stale, error with Retry.
- SettingsFormRow: adaptive label/control layout.
- SettingsReceiptDisclosure: redacted configuration generation and live process evidence.
- SettingsDestructiveActionRow: explicit consequence and confirmation.

All status components expose text through accessibilityValue and accessibilityHelp. Icons and colors reinforce, never carry, meaning.

### E4. Live session receipt

Expand the credential-free GrokLaunchReceipt or add a parallel EffectiveSessionReceipt containing:

- local tab UUID and workspace UUID;
- local process identifier for local diagnostics;
- process generation;
- durable backend ID;
- launch outcome: loaded, new, or recovery-forked;
- requested and launched model;
- requested agent and reasoning effort;
- permission and sandbox mode;
- memory, browser, and Computer Use launch state;
- MCP server names only;
- start time and receipt freshness.

Exclude prompt text, environment values, header values, URLs with credentials, allow/deny rule contents, Keychain values, and raw config.

Show a compact selectable line near the workbench model/agent controls:

> Live in this tab: Grok 4.5 · General Purpose · Low · backend …9782

If any field is merely requested, stale, or unverified, say that instead. The disclosure opens full redacted details and is reachable by keyboard.

When the CLI does not independently expose the backend’s effective model, the receipt must say “Backend model not independently exposed.” Process arguments and picker state may still prove what GrokBuild requested; neither may be promoted to backend confirmation.

## 12. Workstream F — all fourteen Settings panes

This is the pane-by-pane closure matrix. “Current” means the feature basically works; it does not waive the shared truth and accessibility contract.

### F1. Agents

**Current:** discovery and editing work; the default picker uses @AppStorage before Save Default.

**Repair:**

- make the picker a true draft;
- label it “Default agent for new tabs”;
- show existing tab overrides separately;
- preserve nil as inheritance;
- show the active tab’s requested/launched agent;
- disclose that agent changes require a new or restarted process;
- keep custom-role CRUD direct to its own config, with row-local save/error feedback;
- do not restart unrelated tabs.

**Acceptance:** closing Settings with an unsaved draft changes nothing; Save Default changes new inherited tabs; an explicit old tab override survives; VoiceOver announces default, tab override, and live state separately.

### F2. Models

**Current:** provider/credential work is already off-main; custom model management works; default propagation can be stale; optimistic model selection can look confirmed.

**Repair:**

- preserve the existing CustomModelsSettingsViewModel off-main boundary;
- refresh the catalog after config/provider/default mutations;
- show catalog source and freshness;
- distinguish default for new tabs from current-tab override;
- keep unknown saved model identifiers visible;
- display requested, launched, and confirmed states;
- bind async completion to tab, backend ID, request ID, and process generation;
- never expose Keychain values;
- maintain provider endpoint policy and locked atomic config writes.

**Acceptance:** Models becomes interactive before Keychain/catalog completion, with a neutral Checking state; no main-thread stall; failure leaves last known data marked stale; a rejected switch reverts or becomes Unknown rather than false green.

### F3. Memory

**Current:** memory toggle and browser work; the toggle mutates storage before Apply.

**Repair:**

- use a draft for the launch-affecting memory toggle;
- show future-session versus active-tab restart scope;
- keep Remember and memory-browser actions independent;
- show write destination and result without treating a saved memory note as a process receipt;
- make empty, unavailable, permission-denied, and load-error states distinct;
- never put memory contents in diagnostics.

**Acceptance:** changing the toggle without Apply cannot alter the next process; applying does not falsely relabel an already running tab; Remember is keyboard and VoiceOver usable.

### F4. Workflows

**Current:** workflow configuration and saved workflows work; config reads can be synchronous and restart impact is terse.

**Repair:**

- load TOML/config data off-main;
- preserve unrelated config and file permissions;
- label shared-config ownership;
- state “Restart active tab” or “Future sessions” before Apply;
- retain draft on write failure;
- show empty versus failed load;
- make saved-workflow row actions self-reporting.

**Acceptance:** no spinner blocks the pane shell; a config failure is actionable; a streaming tab queues restart without losing the turn.

### F5. Browser

**Current:** draft/applied storage exists and current diagnostics work. Initial readiness can flash Setup needed, and the enable badge can reflect draft rather than applied/live state.

**Repair:**

- begin with Checking until the first bounded readiness result;
- use the two-phase draft/Apply contract for every launch-affecting control, including Enabled;
- calculate the headline badge from applied settings plus readiness, not draft;
- show external-browser versus managed-browser implications;
- keep diagnostics non-mutating;
- prompt for any external action only when Apply requires it;
- suspend polling when the pane is hidden.

**Acceptance:** no false red state during load; discarding draft leaves applied state; Ready requires applied configuration and an authoritative helper/runtime check; current-tab launch receipt can still say restart required.

### F6. Computer Use

**Current:** helper and permissions are functional; Accessibility and Screen Recording status can be inspected; some controls mix immediate and deferred behavior.

**Repair:**

- use one clear Apply contract for launch settings;
- treat “Open System Settings” and permission checks as direct actions;
- request Screen Recording only when a user invokes the relevant action, never on pane entry;
- derive Ready from applied settings, helper version, and required permissions;
- show Cursor integration as a separate external-integration receipt;
- preserve the explicit close/safety contract;
- never imply Screen Recording is required when screenshots are disabled.

**Acceptance:** permission status is text-equivalent, accurate after returning from System Settings, and does not steal focus; Apply states exactly which sessions restart; disabling screenshots updates readiness correctly.

### F7. MCP Servers

**Current:** listing and basic mutations work. The UI flattens command/arguments into whitespace and cannot faithfully represent the CLI’s argument, environment, and header contract.

**Repair:**

- replace Name/Transport/Target with transport-specific structured drafts;
- for stdio: executable field, reorderable argument rows, environment key/value rows;
- for HTTP/SSE: URL, header rows, and transport-appropriate validation;
- expose user/project scope explicitly;
- preserve quoted strings and argument boundaries without shell splitting;
- use SecureField and one-way replacement for sensitive values;
- show only secret key names and redacted status after save;
- run Doctor with a bounded timeout and a redacted row-local receipt;
- serialize exactly to the verified Grok 0.2.118 CLI contract.

Secret handling is a hard preflight gate. First determine from local CLI help and version-matched primary source whether Grok supports environment interpolation, secret references, or only literal storage. Prefer Keychain-backed references only if GrokBuild can inject them without creating a non-interoperable config. If the CLI necessarily persists a literal, disclose that fact before Save, preserve mode 0600, never mirror the value into UserDefaults/logs/UI, and require explicit replacement rather than reveal. Do not invent a syntax the CLI cannot read.

**Acceptance:** round-trip fixtures preserve command, empty/space-containing arguments, URL, scope, env/header names, and transport; secret values never appear in UserDefaults, receipts, snapshots, or logs; malformed entries cannot reach the CLI.

### F8. Skills

**Current:** discovery works but produced the slowest visited pane in the audit.

**Repair:**

- make the pane shell immediately interactive;
- load and normalize inspect output off-main;
- virtualize or use lazy rows for large lists;
- distinguish no skills, failed load, and stale last-known result;
- offer Retry;
- suspend hidden-pane work;
- instrument inspect duration separately from SwiftUI render time.

**Acceptance:** cold-load budget is met or the delay is clearly attributed; keyboard search and list traversal do not rebuild the full view; no error is rendered as an empty successful list.

### F9. Plugins

**Current:** listing works and the audited installation had none enabled.

**Repair:**

- show installed, disabled, update-available, and failed states distinctly;
- put progress/error/result on the affected row;
- show source, permissions/trust implications, and data-retention behavior before install/uninstall;
- require confirmation for destructive uninstall;
- preserve selection and focus after list refresh;
- never auto-trust an unreviewed source.

**Acceptance:** cancellation leaves no misleading row state; enable/update/uninstall receipts identify the exact plugin; VoiceOver receives completion/failure announcements without being spammed by every progress tick.

### F10. Marketplace

**Current:** one xAI Official source and 15 available plugins were discovered; cold navigation was comparatively slow.

**Repair:**

- load source inventory and available plugins independently;
- show source provenance before install;
- remove any unconditional trust: true path;
- use the same trust confirmation as Plugins;
- show source removal impact;
- cache only non-sensitive catalog metadata with freshness;
- make an unavailable source an error, not “0 plugins.”

**Acceptance:** install cannot proceed without explicit provenance/trust context; stale cache is labeled; Marketplace meets its cold-load budget or remains responsive while loading.

### F11. Hooks

**Current:** discovery works; none were configured.

**Repair:**

- retain read-only inventory unless a separately designed editor is justified;
- show “No hooks configured” only after successful inspection;
- show hook source/scope and enabled status;
- expose load errors and Retry;
- do not imply that an empty inventory disabled existing hooks.

**Acceptance:** successful empty, stale, unsupported schema, and failed inspection are distinct visually and through accessibility values.

### F12. Compatibility

**Current:** Grok CLI 0.2.118 emits externalCompat with 13 cells. GrokBuild parses only legacy compat, external_compat, and compat_layers arrays, so the pane reports no detected sources while toggles can still write cells.

**Repair:**

- add a versioned decoder for the current externalCompat object and its cells;
- preserve legacy decoding for older supported CLI fixtures;
- normalize both schemas into GrokExternalCompatInfo plus capability cells;
- show actual supported capabilities behind each high-level flavor;
- expose Codex’s sessions-only limitation rather than implying full parity;
- surface unsupported schema as Unknown with a redacted diagnostic;
- do not swallow listExternalCompat errors.

**Acceptance:** fixtures for 0.2.118 and legacy schemas decode; 13 current cells appear; aggregate switches reflect partial capability state; a schema change cannot become an empty-success screen.

### F13. Permissions

**Current:** current permission, sandbox, reasoning, web, subagent, allow, and deny mappings align with live arguments. @AppStorage mutates values before Apply, Apply is always available, and stored-versus-live truth is missing.

**Repair:**

- move every launch-affecting field into a draft;
- disable Apply when clean or invalid;
- validate allow/deny rules before persistence;
- show exact redacted launch consequences;
- state whether active tab restart is required;
- show current tab’s live permission/sandbox/effort receipt;
- keep rules out of receipt/log content;
- preserve draft and selection on failure.

**Acceptance:** unsaved changes do not alter UserDefaults; applied values round-trip; the current process remains labeled with its old live receipt until restart succeeds; Always approve cannot be inferred merely from a stored picker value.

### F14. App

**Current:** installed CLI/latest CLI and build identity are visible and current; update observation is functional.

**Repair:**

- separate app update, CLI update, installed build identity, and active-session identity;
- show checking, current, update available, failed, and stale states;
- include last-check time and channel;
- add the two-option cold-launch behavior control, clearly scoped to the next full app launch;
- add System/Light/Dark appearance selection and disclose when no restart is required;
- retain provenance/source stamp and executable parity in details;
- keep update operations bounded and never freeze pane navigation;
- link to the diagnostics export and this plan’s evidence format, not raw secrets.

**Acceptance:** a failed update check cannot display “Current”; the App pane may say the binary is current while the active session receipt independently says Unknown; mounted-pane refresh remains fresh without polling churn; both cold-launch choices round-trip and never delete or reclassify saved tabs; System/Light/Dark apply consistently and existing dark-mode users do not change appearance during migration.

## 13. Workstream G — Settings information architecture and lifecycle

Keep all fourteen destinations, grouped in the existing native sidebar. Do not hide complexity through mystery submenus. Improve orientation:

- show one-line purpose text below each pane title;
- place status nearest the title;
- put primary configuration before diagnostics and destructive actions;
- keep one bottom Apply bar only for pane-wide drafts;
- use row-local actions for row-owned mutations;
- keep advanced disclosures collapsed but searchable by VoiceOver;
- retain the selected pane when the window closes and reopens.

Replace SettingsTabKeepAlive’s permanent mounting of every visited view with durable pane view models owned above the selected view. The selected view tree may unload while its draft state remains. Cheap static panes may stay cached if measurement proves a benefit, but hidden panes must not poll, observe large data sets, hold WebKit views, or retain task graphs.

At compact widths and accessibility text sizes:

- sidebar remains at a usable minimum or becomes a native toolbar/sidebar disclosure;
- forms fall from horizontal to vertical using ViewThatFits or an equivalent native layout;
- editors remain at least 44 points tall where pointer precision matters;
- no horizontal clipping hides labels, errors, or Apply;
- segmented controls may become pop-up buttons when labels no longer fit;
- MCP argument/env/header rows stack instead of crushing fields.

## 14. Workstream H — workbench coherence

### H1. Identity strip

The workbench chrome should present, in quiet priority order:

1. Project and branch.
2. Local tab title.
3. Model and agent controls.
4. Compact live-session receipt.
5. Continuity warning only when action is required.

Do not add a dashboard of badges. One receipt line and one details disclosure are enough.

### H2. Model picker

Picker items indicate:

- inherited default;
- explicit tab override;
- unavailable saved model;
- requested switch;
- confirmed live value.

Changing the picker initiates a request, not an optimistic final state. Disable only conflicting model actions, not transcript reading or draft editing.

### H3. Streaming and reader-controlled scroll

Track whether the reader is attached to the bottom. Automatic following continues only while attached. When the reader scrolls up beyond a small threshold:

- stop all forced scroll retries;
- keep streaming without moving their viewport;
- present an accessible “Jump to latest” control with unread/new-content count;
- resume following only after the user activates it or returns to the bottom.

Final rich-render settling may perform one bounded correction only when still attached.

### H4. Rich message rendering

Cache parsed markdown blocks by message ID, a process-local non-persisted content digest, width class where required, and render version. Reuse completed Mermaid and math render results. Streaming text may use a cheaper representation until stable, then transition once.

WebKit-backed content:

- is created lazily near the viewport;
- has a deterministic accessibility label and fallback text;
- respects Reduce Motion and Increase Contrast;
- is torn down when no longer needed;
- never receives raw secrets or diagnostic metadata.

### H5. Errors, loading, empty, and recovery

Every async workbench lane has four distinct presentations:

- loading with task name;
- empty with what can be done next;
- error with retry/details;
- stale content with freshness.

Never replace an existing transcript with a full-screen spinner. Keep readable work visible while backend/process actions happen.

## 15. Workstream I — accessibility completion

Accessibility is a release lane, not a final sweep.

### I1. Semantic requirements

Every interactive element must expose:

- a unique, task-oriented accessibilityLabel;
- the current accessibilityValue where state matters;
- accessibilityHelp when the consequence is not obvious;
- selected, expanded, busy, invalid, or disabled state;
- a role matching its behavior;
- a logical focus successor after mutation or deletion.

Avoid labels that repeat visible section titles without naming the action. “Button, gear” is garbage. “Open session identity details” is useful.

### I2. Status and announcements

Use accessibility announcements sparingly:

- announce terminal success or failure for an action the user initiated;
- announce continuity blocking before focus reaches Send;
- announce model switch confirmed, rejected, or still unverified;
- announce newly available “Jump to latest” once, not per chunk;
- do not announce every loading tick, streamed token, or background refresh.

Status badges expose the complete phrase in accessibilityValue: “Applied, restart required for current tab,” not merely “yellow.”

### I3. Keyboard navigation

Required keyboard-only path:

1. Move among projects and tabs.
2. Read the identity receipt.
3. Enter and exit the model/agent controls.
4. Reach transcript, attachments, composer, Send/Stop, and Jump to latest.
5. Open Settings.
6. Traverse all sidebar groups and panes.
7. Edit, Revert, Apply, Retry, and open details.
8. Close sheets, menus, and Settings with Escape.
9. Return to the same workbench control or a deterministic neighbor.

No keyboard trap is acceptable in rich content, Mermaid/WebKit content, rule editors, MCP row editors, popovers, or sheets. Return and Space activate controls according to native role. Command shortcuts must not collide with text editing.

### I4. Focus management

- Opening Settings focuses the selected pane heading or first meaningful control after the sidebar selection.
- Switching panes moves focus only when initiated from the sidebar; background refresh never steals it.
- Adding an MCP argument/env/header row focuses the new row’s first field.
- Removing a row focuses the next row, previous row, or Add control.
- After Apply, focus stays on Apply/status and reads the terminal receipt.
- A continuity warning sends focus to its heading only when it blocks a just-attempted send.
- Model confirmation never steals focus from the composer.

### I5. Visual accessibility

Verify all surfaces with:

- Increase Contrast;
- Reduce Transparency;
- Differentiate Without Color;
- Reduce Motion;
- large accessibility text;
- light and dark appearances;
- narrow and full-screen windows.

Warm-glass boundaries must remain visible with transparency reduced. Selected sidebar/tab state needs shape or label treatment beyond tint. Errors, warnings, pending, and success states require text and distinct icons. Focus rings may not be clipped by cards or masks.

The current AppDelegate forces darkAqua globally and again on the main window, so light-mode acceptance is impossible until appearance becomes real product state. Add an App setting with **System**, **Light**, and **Dark**, defaulting to System for new installs while preserving Dark for existing users through migration. Remove unconditional darkAqua forcing; apply the selected appearance consistently to app, main window, Settings, sheets, popovers, WebKit-backed rich content, and helper panels. Audit the warm-glass palette as semantic colors/materials rather than dark-only literals.

Motion:

- no indefinite decorative animation;
- progress animation respects Reduce Motion;
- pane transitions and transcript settling do not use large spatial movement when reduced;
- model/continuity changes use opacity or immediate replacement where appropriate.

### I6. Transcript accessibility

- Messages expose role, position where helpful, and content in natural reading order.
- Code blocks expose language, Copy action, and readable text.
- Tables remain navigable or have a linear text alternative.
- Links expose destination context without reading raw tracking URLs.
- Math exposes source or accessible text fallback.
- Mermaid diagrams expose a concise description and source fallback.
- Thinking/tool/result disclosures communicate expanded/collapsed state.
- Streaming text avoids re-announcing the full message on every update.

### I7. Accessibility test strategy

Automated tests should cover pure label/value reducers and layout policy. Installed-app Computer Use and VoiceOver evidence is still required because unit tests cannot prove AX tree order, focus recovery, hit targets, or rendered contrast.

Extend:

- Tests/GrokBuildTests/SettingsTabTests.swift for pane inventory, load states, grouping, and adaptive policy;
- Tests/GrokBuildTests/ChatTranscriptLayoutTests.swift for detached scrolling and Jump to latest;
- Tests/GrokBuildTests/MainWindowLayoutTests.swift for narrow/large-text fallbacks;
- AppDelegate appearance policy and App-pane tests for System/Light/Dark resolution and existing-user migration;
- Tests/GrokBuildTests/ComposerWorkflowTests.swift for focus and Send/Stop availability;
- Tests/GrokBuildTests/MarkdownBlockParserTests.swift for accessible fallback content.

## 16. Workstream J — provenance-safe transcript import

The current importer reduces backend rows to plain Message values, which erases evidence needed to decide whether assistant rows belong to the parent conversation, a worker, or a synthetic recovery event. The reconciler can intentionally preserve divergent worker text before a parent final, which is useful for display but unsafe as backend-identity proof.

### J1. Preserve source evidence

Introduce an imported intermediate representation with:

- backend session ID;
- row index/order;
- role;
- row kind;
- parent/root relationship when the 0.2.118 JSONL exposes it;
- agent/worker provenance when exposed;
- terminal/final marker when exposed;
- versioned opaque content tag;
- whether the row is synthetic;
- parser schema version.

Capture and redact one real fixture for every row shape before declaring fields authoritative. Store fixture content only under Tests with synthetic text.

### J2. Separate display merge from identity proof

Two algorithms are required:

1. **Display reconciliation** may preserve useful worker output and append a root final idempotently.
2. **Binding verification** uses only authoritative root conversation turns and cannot rely on a display-composite transcript.

Unknown or mixed-source rows are quarantined in the reconciliation result as diagnostic metadata. They are not deleted, appended to a backend, or used to suppress new ACP chunks.

### J3. Remove heuristic auto-binding from startup

uniqueSessionIDMatchingTranscript may remain as a recovery candidate finder only. It cannot automatically bind an unbound legacy tab based on one normalized final prompt, even when exactly one history matches. The result must be review-needed with evidence.

Normal startup:

- exact durable binding → verify exact history;
- no binding → remain local-only;
- failed exact binding → backendMissing or diverged;
- explicit user recovery → bounded candidate search.

### J4. Import/reconcile acceptance

- Exact known-ID fixtures reconcile a parent final once and remain idempotent.
- Worker and parent rows preserve provenance.
- Mixed/unknown provenance cannot verify a backend binding.
- One common matching prompt cannot auto-bind a tab.
- Synthetic-only histories do not count as conversational continuity.
- Raw prompt text never enters logs or signposts.

## 17. Workstream K — privacy, security, and trust boundaries

### K1. Data classification

| Data | Storage/handling |
|---|---|
| Local transcripts | Owner-only Application Support files; never logs |
| Backend histories | Remain in Grok-owned storage; read only when required |
| Backend/local IDs | Full only in local details; truncated or hashed in diagnostics |
| Provider secrets | Keychain or CLI-authoritative secure path; never UserDefaults |
| MCP env/header secrets | Follow verified CLI capability; redact everywhere |
| Non-secret settings | UserDefaults or config repository as appropriate |
| Diagnostic timings/counts | OSLog with privacy redaction |
| Recovery backups | Outside repo, directory 0700, files 0600 |

### K2. Config mutations

Retain GrokConfigRepository’s locked atomic rewrite and mode 0600. Every new config mutation must:

- preserve unrelated TOML and comments where the current repository contract promises it;
- validate before replace;
- keep a bounded rollback copy where migration is involved;
- never print the resulting file;
- test concurrent write behavior;
- return a redacted structural receipt.

### K3. Marketplace and plugin trust

No installation path may hardcode trust approval. Confirmation identifies:

- exact source;
- package/plugin name and version;
- declared capabilities when exposed;
- whether code executes locally;
- whether data survives uninstall;
- which process/session reloads.

Trust is scoped to the exact operation. A trusted xAI marketplace source does not imply every future third-party source is trusted.

### K4. Diagnostics export

If added, diagnostics export is an explicit user action and contains:

- app and CLI versions;
- build provenance;
- timing spans;
- counts and outcome codes;
- truncated or salted IDs;
- settings state names, never values that carry secrets;
- process generations and child counts;
- schema versions.

It excludes transcripts, prompt hashes that could be dictionary-attacked, file contents, raw absolute home paths, environment, rules, URLs with query/user info, and credentials. Preview the inventory before Save.

Opaque transcript verification tags are also excluded. Even keyed tags are continuity internals, not diagnostic souvenirs.

## 18. Backend CPR runbook

CPR is a targeted response to a proven continuity failure. It is not “restart it and see.”

### CPR1. Triage

Classify the patient:

| Layer | Check | Healthy means |
|---|---|---|
| Pulse | App/process responsiveness and bounded CPU | UI responds; no sustained spin |
| Airway | ACP transport and helper children | One expected process tree; messages flow |
| Circulation | Tab ↔ backend transcript continuity | Verified opaque tags and exact backend ID |
| Neurology | Model/agent/effort truth | Requested and confirmed state are not conflated |
| Memory | Local and backend persistence | Both decode and survive relaunch |

The audited patient had pulse and airway. Circulation failed. A reinstall does not repair circulation.

### CPR2. Pre-surgery checkpoint

Before any separately authorized state mutation:

1. Reconfirm canonical worktree, branch, remotes, clean/dirty state, installed stamp, executable hash, signature, and CLI version.
2. Capture the exact selected tab UUID, workspace, saved backend ID, requested/live model receipt, and process tree.
3. Invoke an app-owned durable flush of layout, transcript, and binding generations; wait for its receipt.
4. Quit the exact installed GrokBuild app through the controlled lifecycle path.
5. Prove the app and every owned Grok/browser/Computer Use child exited. If durable flush or quiescence cannot be established, stop; a live cross-artifact copy is not a rollback point.
6. Create a timestamped recovery directory outside the repository with mode 0700.
7. Copy only the exact affected artifacts:
   - ~/Library/Preferences/com.grokbuild.app.plist;
   - the affected local transcript file or legacy preference payload;
   - the exact affected binding ledger and its committed marker;
   - the affected Grok backend JSONL histories;
8. Treat ~/.grok/config.toml separately:
   - if config is outside the proven repair scope, do not copy it;
   - if config rollback is required, make an exact sensitive copy inside the 0700 recovery directory, set it to 0600, never display/export its contents, and put only its hash and mode in the redacted manifest.
9. Set all ordinary copied files to 0600.
10. Verify SHA-256, decode, session IDs, row/message counts, timestamps, and the shared flushed generation/manifest.
11. Record a redacted manifest. The private 0600 binding-ledger rollback copy may contain its opaque tags, but the manifest and any diagnostic export may not. Never copy or export the Keychain HMAC secret. If an authorized backup process intentionally strips opaque tags from the binding copy, recompute them from restored transcripts after restore and leave continuity unverified until that recomputation succeeds.

If any backup fails verification, stop. No surgery.

### CPR3. Decision tree

~~~text
Exact backend exists and fingerprints verify?
├── yes → preserve binding; no CPR
└── no
    ├── local transcript is cleanly local-only
    │   └── user chooses Continue as New → durable fork ledger
    ├── one exact, provenance-safe candidate is presented
    │   └── user explicitly Relinks → verify, then durable mapping
    ├── composite or multiple candidates
    │   └── preserve local tab; explicit fork is the safe default
    └── corrupt/unreadable artifact
        └── restore only that artifact from verified backup with authorization
~~~

### CPR4. Surgery rules

- Mutate one proven-invalid record at a time.
- Use atomic writes.
- Preserve old → new backend mapping.
- Never rewrite Grok history to resemble the local transcript.
- Never delete a “duplicate” until identity and retention are separately reviewed.
- Do not clear preferences globally.
- Do not touch unrelated tabs or workspaces.

### CPR5. Post-surgery proof

Use a unique harmless marker turn only after continuity is verified and the user has chosen the target/fork:

1. Send from the intended tab.
2. Prove the marker appears in the visible transcript.
3. Prove the exact backend JSONL received it.
4. Prove model/process receipt is bound to the same generation.
5. Quit and relaunch.
6. Prove the same tab, binding, model status, and marker return.
7. Keep the recovery directory until user acceptance.

## 19. Schema and migration plan

### M1. Versioned lifecycle snapshot

Create a v3 lifecycle schema while retaining v2 as rollback input. Suggested additions:

- TabModelIntent: inheritProjectDefault or explicit(modelID);
- TabAgentIntent: inheritGlobalDefault or explicit(agentID);
- ModelExecutionState: requested, confirmed, pending/failed, process generation;
- BackendBinding: backend ID, keyed opaque workspace tag, origin, predecessor, verification;
- lastActivationOrdinal: monotonically increasing stable MRU order;
- transcriptGeneration and storageVersion;
- fork ledger references.

Wall-clock lastAccessed remains useful for display, but lastActivationOrdinal resolves timestamp ties and avoids clock drift. Background recovery, process readiness, or LRU eviction must not increment it; only intentional tab activation does.

### M2. Migration rules

- Decode absent new fields without failure.
- A legacy model value becomes explicit only if the old record actually persisted an intentional tab selection; if intent cannot be proven, preserve it as legacyUnknown and ask for no mutation until policy is settled.
- Current v2 record.model != nil is not evidence of explicit intent because v2 persistence writes the resolved currentModel for every saved tab. Unless an independent old explicit-override receipt exists, every non-nil v2 model migrates to legacyUnknown, never explicit(modelID).
- A nil legacy model remains inheritance.
- A legacy backend ID begins unverified, not verified.
- Existing selected IDs and order are preserved.
- Migration is idempotent.
- The old encoded snapshot remains untouched until new snapshot verification and at least one successful installed-app relaunch.
- A migration failure falls back to read-only legacy presentation, not an empty workspace.

Because old persistence did not distinguish resolved defaults from explicit overrides, implementation must not fabricate certainty. Use legacyUnknown and let the user’s next explicit model action settle intent.

Use a distinct v3 storage key, such as GrokBuild.sessionLayout.v3. Never overwrite GrokBuild.sessionLayout.v2 during migration. Commit order:

1. Decode v2 without mutation.
2. Write a v3 candidate under the v3 key.
3. Read it back and verify schema version, record count, IDs, transcript generations, and a keyed integrity tag of the encoded data.
4. Write a separate v3 committed marker containing those verified values.
5. On launch, treat v3 as authoritative only when candidate and marker match exactly.
6. On any count, integrity-tag, version, or decode mismatch, keep v2 authoritative and present migration failure without creating an empty workspace.
7. Retain v2 through at least one accepted installed release and a separately verified rollback cycle.

### M3. Generation safety

Every async result that can mutate visible state carries:

- local tab UUID;
- backend ID, if any;
- process generation;
- configuration generation;
- request ID.

Discard results whose tuple no longer matches. This includes model switches, process readiness, history import, Settings apply, catalog refresh, and diagnostics. Late success from an old process is not current truth.

## 20. Implementation sequence and dependency DAG

Do not ship this as one heroic patch. Correctness, migration, Settings semantics, and storage are independently reversible slices.

~~~mermaid
flowchart TD
    A["Slice 0: evidence fixtures and signposts"] --> B["Slice 1: v3 lifecycle schema and true MRU"]
    B --> C["Slice 2: generation-bound process and model receipts"]
    C --> D["Slice 3: continuity verifier and send gate"]
    D --> E["Slice 4: provenance-safe import and recovery UI"]
    C --> F["Slice 5: shared Settings state/apply contract"]
    F --> G["Slice 6: priority launch panes"]
    F --> H["Slice 7: MCP, Compatibility, and extension panes"]
    D --> I["Slice 8: file-backed incremental transcripts"]
    I --> J["Slice 9: lazy startup, Settings lifecycle, rich-render performance"]
    E --> K["Slice 10: workbench accessibility and scroll control"]
    G --> K
    H --> K
    J --> K
    K --> L["Slice 11: installed-app matrix, soak, and release decision"]
~~~

### Slice 0 — evidence fixtures and instrumentation

**Purpose:** freeze the bug shapes and establish timing before behavior changes.

Deliver:

- synthetic fixtures representing the exact empty/synthetic backend, verified history, divergent history, and composite worker/parent history;
- redacted 0.2.118 inspect externalCompat fixture;
- MCP help/serialization fixtures for every supported transport option;
- versioned normalization/HMAC test vectors containing synthetic text only;
- signposts listed in D5;
- current baseline report with hardware, corpus size, sample count, p50/p95, CPU, RSS, and process tree.

No state mutation or UI redesign belongs here.

Exit:

- fixtures reproduce the incorrect MRU, nil-model inheritance freeze, false model confirmation, compatibility empty-success, and unsafe continuity assumption;
- logs contain no user text or secret data.

### Slice 1 — lifecycle schema and restore correctness

**Primary files:** SessionLayoutStore.swift, SessionRestorePolicy.swift, ContentView.swift, SessionPersistenceTests.swift.

Deliver:

- v3 schema;
- distinct v3 storage key, commit marker, and conservative v2 model migration;
- lastActivationOrdinal;
- explicit/inherited/legacyUnknown model and agent intent;
- true MRU pure policy;
- one-load restore inputs;
- migration and rollback decoding.
- an app-owned durable persistence flush receipt used by controlled quit and CPR.

Exit:

- no longest-transcript fallback;
- nil inheritance survives repeated restore/persist;
- every unproven non-nil v2 model becomes legacyUnknown, never explicit;
- v2 remains authoritative after any v3 candidate/marker mismatch;
- failed migration shows legacy state rather than empty data;
- rapid A → B → quit deterministically selects B.

#### Slices 0–1 implementation receipt — 2026-08-01

- Source remained on `codex/warm-glass-ui` at plan commit `ee55e48ebc2e6181226302995df56959529ee115`; the implementation is intentionally uncommitted and the installed bundle is stamped dirty against that source commit.
- Slice 0 added the pinned synthetic corpus, all fifteen redacted `com.grokbuild.app` performance lanes, and `docs/GROKBUILD_SLICE_0_BASELINE_2026-08-01.md`.
- Slice 1 added the separate v3 candidate/commit/flush keys, Keychain-keyed HMAC marker, semantic model/agent intents, structured backend binding, transcript generations, true activation-ordinal MRU, one-load restored-transcript handoff, conservative v2 fallback, and deterministic flush receipts.
- `make test`: 425 tests, 0 failures, 13.382 seconds. The focused lifecycle suite: 11 tests, 0 failures.
- Installed Computer Use proof opened Settings and returned to the selected transcript, then quit/relaunched `/Applications/GrokBuild.app` in 1.402 seconds with the transcript visible, Grok 4.5 selected, and no migration banner.
- The original 7,902-byte v2 payload remained byte-identical at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. The accepted v3 snapshot contains 24 records, all 24 unproven v2 models are `legacyUnknown`, and its authenticated commit marker plus 33-transcript flush receipt are present.
- No backend CPR, provider send, history rewrite, or new Grok/ACP child process was used. A live data-protection-Keychain attempt failed closed with `errSecMissingEntitlement`; the accepted implementation uses the standard macOS login Keychain off the main thread and caches the 32-byte key in process memory.
- Installed and packaged executables match at SHA-256 `f6115553c85d30e6e39a2a63411cd775db0cca9844db17f61d57104855b612b7`; deep/strict signing passes, quarantine is absent, and the previous exact app is recoverable at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-0-1-20260801-1744.app`.
- Slice 1 installed proof covers the saved-selection relaunch path. Rapid A → B → quit, divergence, no-viable-candidate, and intent inheritance are deterministic fixture tests; live tab switching was deliberately not used because an unverified migrated backend must not be started merely to manufacture acceptance evidence.

### Slice 2 — process and model truth

**Primary files:** GrokProcess.swift, ChatStore.swift, SessionLayoutStore.swift, ChatView.swift, ACPClientContractTests.swift.

Deliver:

- process generation;
- expanded credential-free receipt;
- requested/pending/confirmed/rejected model reducer;
- stale-callback rejection;
- non-optimistic accessibility labels and workbench details.

Exit:

- absent effective model is Unknown/requested, not confirmed;
- rejected/late callbacks cannot overwrite current state;
- explicit confirmed model and desired intent survive relaunch correctly.

#### Slice 2 implementation receipt — 2026-08-01

- Source remained on `codex/warm-glass-ui` at plan commit `ee55e48ebc2e6181226302995df56959529ee115`; Slices 0–2 remain intentionally uncommitted and the installed bundle is stamped dirty against that source commit.
- The app now owns a monotonic process generation, a credential-free launch receipt, and a persisted model receipt keyed by local tab, backend session, process generation, and request UUID. Exact identity is required before an asynchronous callback may settle state.
- Model transitions use one requested/pending/confirmed/rejected reducer. An accepted `session/set_model` response without an explicit effective-model readback stays Requested; launch/session responses can confirm only when they independently expose the effective model. CLI lookup, spawn, and ACP initialization failures close the active generation and reject any launch-model request. Restoring a tab no longer sends a hidden model RPC to cosmetically force saved state.
- `make test`: 433 tests, 0 failures, 13.648 seconds. The combined focused ACP/lifecycle run completed 34 tests with 0 failures in 0.964 seconds, including stale-generation, empty-success, explicit-readback, rejection, failed-launch settlement, saved-not-live, launch-receipt, and v3 round-trip cases.
- Installed Computer Use proof exposed the keyboard-reachable receipt menu with `Current backend model is unknown.` and `No process launch receipt for this tab.`, while the compact workbench showed `No active process` and the model selector exposed Unknown rather than Live. Settings opened in 1.663 seconds and returned to the exact transcript in 1.742 seconds; Command-Q exited in 537 ms and the final installed relaunch restored the same transcript in 1.254 seconds.
- The original 7,902-byte v2 payload remains byte-identical at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. The accepted v3 snapshot still contains 24 records and now persists 24 model-execution receipts; its authenticated marker and the 33-transcript flush receipt remain present.
- No backend CPR, provider send, migrated-backend start, or owned Grok/browser/Computer Use child was used. A real Live label was deliberately not manufactured; explicit confirmation and rejected/late callback behavior are covered by deterministic ACP fixtures.
- Installed and packaged executables match at SHA-256 `cafe63f1043da2c7453d9caf12eec88a8d2c0969194cca0962ec4cc25e5c0da1`; deep/strict signing passes under Team `DD2GCQJVB4`, quarantine is absent, and the exact pre-Slice-2 app is recoverable at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-2-20260801-1822.app`.

### Slice 3 — continuity verifier and send gate

**Primary files:** SessionTranscriptRecovery.swift, GrokSessionTranscriptImporter.swift, ChatStore.swift, ChatView.swift.

Deliver:

- bounded fingerprint comparison;
- continuity state;
- send gate;
- safe local-only process creation;
- durable fork ledger;
- divergence details.

Exit:

- verified happy path sends normally;
- mismatched/composite state cannot send to the saved backend;
- local work remains readable and durable.

#### Slice 3 implementation receipt — 2026-08-01

- Slice 3 code and governing documentation are committed on `codex/warm-glass-ui` at `e1be34b337e5e823d40daba6a59ee3fc8afdc01b`. The signed installed bundle was rebuilt from that clean commit and visibly reports `Personal • codex/warm-glass-ui @ e1be34b3`; the receipt-only documentation commit may follow it without changing build inputs.
- `GrokSessionTranscriptImporter` streams only the exact bound history through a 2 MB / 2,000-conversational-row soft bound. Oversized reads and their HMAC comparison share one five-second cancellable deadline. `SessionTranscriptRecovery` classifies exact, prefix, backend-only, missing, unreadable, incomplete, divergent, and composite-suspected relationships with separate normalization/HMAC schema versions and no raw-content diagnostics.
- `ChatStore` now verifies before `GrokProcess.start`, gates every composer delivery, preserves a verified receipt when a live tab is reselected, and refuses legacy backend-tail reconciliation until continuity permits it. Local-only tabs remain process-free until first send. Recovery/fresh-start relationships persist as append-only predecessor/successor ledger entries inside authenticated v3 state.
- `make test`: 439 tests, 0 failures, 13.721 seconds. The final continuity/lifecycle/source-contract filter completed 38 tests with 0 failures in 0.066 seconds. Fixtures cover exact/prefix/backend-only, missing/synthetic/incomplete, divergence/composite, all send-gate states, authenticated receipt/ledger round trips, and the source-order contract that no saved backend starts or sends before the gate.
- Installed Computer Use opened a real missing-backend tab with all 16 local conversational rows readable, `backendHistoryMissing` details redacted to an eight-character backend suffix, and Send accessibility-disabled. A harmless unsent draft remained editable and survived Settings in 829 ms / return in 1.203 seconds. After an 822 ms graceful quit, relaunch settled in 1.110 seconds on a safe local-only transcript with `No active process`; typing another unsent draft enabled Send without creating a process. Both acceptance-only drafts were cleared.
- No backend CPR, provider send, prompt submission, migrated-backend start, Grok ACP child, browser child, or app-owned Computer Use helper ran. The installed app had zero owned children and sampled 0.0% CPU across three one-second samples. Verified-happy-path send permission is deterministic fixture proof only, preserving the no-provider-send boundary.
- The original v2 payload remains byte-identical at 7,902 bytes and SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. Authenticated v3 remains schema 3 with 24 records, a committed marker and flush receipt; the installed run durably recorded one `backendMissing` continuity receipt. The live fork ledger remains empty because acceptance did not create a backend or fork; authenticated ledger persistence and suffix selection are fixture-proven.
- Installed and packaged executables match at SHA-256 `970557b2f3b2393a575ce5fead7b44de5b186f90d1603c50b931d9209a28f848`; deep/strict signing passes under Team `DD2GCQJVB4`, quarantine is absent, and the exact pre-Slice-3 clean Slice 2 app is recoverable at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-3-20260801-1857.app`.
- Slice 4 was separately authorized after this receipt. Slice 3 itself remains the fail-closed boundary; candidate review, **Continue as New**, and **Relink** are owned by the following slice.

### Slice 4 — provenance-safe import and recovery UI

Deliver:

- imported row provenance model;
- root-final versus worker separation;
- explicit candidate review;
- Continue as New and Relink flows;
- idempotent exact-binding reconciliation.

Exit:

- no heuristic auto-binding at startup;
- one common final prompt is insufficient proof;
- recovery choice persists and passes marker relaunch.

#### Slice 4 implementation receipt — 2026-08-01

- Slice 4 code and governing documentation are committed on `codex/warm-glass-ui` at `760281c3d136ffe14ac911206b3a5bb79e140610`. The signed installed bundle was rebuilt from that clean code-bearing commit and visibly reports `Personal • codex/warm-glass-ui @ 760281c3`; this acceptance receipt is documentation-only.
- The importer now retains backend/session/row provenance and separates display rows from root-authoritative identity rows. Known worker output remains displayable; unknown or explicitly non-final assistant rows are quarantined and cannot verify a binding.
- Ordinary startup still reads only the exact saved backend. Candidate discovery is an explicit, bounded review action with redacted evidence; a shared prompt or prompt-only prefix remains review-only. Relink re-reads and re-verifies the exact chosen history before saving it.
- Continue as New clears the active binding without starting a process, authenticates a pending predecessor intent in v3, and records its successor/fork entry only when a later real send creates the backend. Relink records an explicit recovery ledger entry without launching a backend.
- Exact-binding reconciliation uses worker-inclusive display rows and root-only identity rows, remains idempotent across repeated restore, and never rewrites Grok history.
- `make test`: 448 tests, 0 failures, 13.427 seconds. The focused importer, authenticated-lifecycle, and ACP source-contract suites completed 31, 14, and 24 tests respectively—69 total—with 0 failures. Fixtures cover root/worker/unknown provenance, common-prompt review-only behavior, exact candidate re-verification, Continue as New relaunch state, Relink ledger state, and idempotent exact-binding display reconciliation.
- Installed Computer Use opened a real missing-backend state with its local transcript readable, Send blocked, and keyboard-reachable **Continue as New** / **Relink…** controls. Relink opened a read-only review sheet and reported no provenance-safe candidate; no mapping changed. The temporary acceptance-only local tab was closed, returning authenticated v3 to its original 24 records.
- Settings → App visibly reported `Personal • codex/warm-glass-ui @ 760281c3` and the personal GitHub repository. Settings → Session returned to the intact blocked transcript. Graceful quit succeeded, and relaunch selected a safe local-only transcript with `No active process`; pending-choice marker relaunch is covered by the authenticated v3 fixture without mutating a real user binding.
- Acceptance used no backend CPR, provider prompt/send, migrated-backend start, Grok ACP child, browser child, or app-owned Computer Use helper. The installed app had zero owned children and sampled 0.0% CPU across three one-second samples.
- The v2 payload remains byte-identical at 7,902 bytes and SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. Authenticated v3 remains schema 3 with 24 records, committed marker, flush receipt, empty live fork ledger, and no live pending recovery choice.
- Installed and packaged executables match at SHA-256 `d46319b537e40a54fd0de3773dfd58dbd8e205bdef699c03f9182879f34e2039`; deep/strict signing passes under Team `DD2GCQJVB4`, quarantine is absent, the immediate pre-Slice-4 app is recoverable at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-4-20260801-192858.app`, and the named pre-Slice-3 rollback remains at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-3-20260801-1857.app`.
- Slice 5 was explicitly authorized after this receipt. Its code and automated acceptance are recorded below; the Slice 4 receipt and boundaries remain unchanged.

### Slice 5 — shared Settings state/apply contract

**Primary files:** ConfigurationChange.swift, a narrowly scoped new Settings state model, SettingsView.swift, ContentView.swift, ChatStore.swift.

Deliver:

- SettingsApplyRequest;
- shared load/status/apply components;
- applied/live session receipt;
- hidden-pane task cancellation;
- adaptive form row.

Exit:

- one fixture pane demonstrates Draft → Saved → Restart required → Live;
- queued restart is bound to exact tab/generation;
- no @AppStorage-backed control claims a draft.

#### Slice 5 implementation receipt — 2026-08-01

- Slice 5 code and governing documentation are committed on `codex/warm-glass-ui` at `734e5050b5b49203d90e2ac9bc36245fdf725b09`. The signed installed bundle was rebuilt from that clean code-bearing commit and visibly reports `Personal • codex/warm-glass-ui @ 734e5050`; this acceptance receipt is documentation-only.
- `SettingsValueState` separates draft, persisted, applied, and live values. `SettingsApplyRequest` declares capability, persistence owner, scope, restart/trust requirements, exact tab/backend/process target, and a redacted receipt. The Memory fixture writes UserDefaults only on explicit Apply and uses the shared checking/status/apply/receipt/adaptive-row components.
- Only the selected Settings pane mounts. Switching away cancels its view-owned `.task`, while the parent-owned Memory draft survives the round trip. Accessibility text sizes force vertical form rows; narrow widths fall back through `ViewThatFits`.
- General, model, and Settings reloads share one `RuntimeConfigurationReloadQueue`. Streaming requests drain once after ordered turn completion, exact newer tab/backend/generation receipts alone become success, disclosed recovery forks remain partial, and a mismatched receipt fails without painting Live.
- The process LRU snapshots tab IDs, re-resolves after asynchronous shutdown, and never adopts a backend receipt unless tab, durable backend, and active process generation all match. A mismatch is still stopped safely while the prior persisted identity is retained.
- Focused Settings/runtime/lifecycle verification completed 19 tests with 0 failures in 1.838 seconds. `make test` completed 457 tests with 0 failures in 14.137 seconds. A synthetic fake ACP process proves that two Apply requests queued during streaming share exactly one reconnect and preserve exact identity; the full Draft → Saved → Restart required → Live state chain, partial fork, stale receipt, and LRU mismatch are deterministic provider-send-free fixtures.
- Installed Computer Use opened Settings → App and verified the personal `734e5050` receipt. Memory loaded Saved/on, moved to Draft/off, retained that draft across App → Memory while the hidden pane unmounted, then Revert restored Saved/on without persistence. Explicit Apply saved off and disclosed configuration generation 1 with the exact local tab plus `backend none; process none`; the pane stayed Saved rather than claiming Live.
- Graceful quit/relaunch proved the applied off value. The original on value was then restored through the same explicit Apply boundary and proved after another clean relaunch. No provider send, backend CPR, Grok ACP child, browser child, app-owned Computer Use helper, new binding, or recovery fork ran; the settled app had zero owned children and sampled 0.0% CPU across three one-second samples.
- v2 remains byte-identical at 7,902 bytes and SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. Authenticated v3 remains schema 3 with 24 records, committed marker, flush receipt, empty live fork ledger, and no pending recovery intent.
- Installed and packaged executables match at SHA-256 `b9e65137fa311fb763c81f00f478b71ae4761f47512e6ff966dbaaa3f815c996`; deep/strict signing passes under Team `DD2GCQJVB4`, quarantine is absent, and the immediate pre-Slice-5 app is recoverable at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-5-20260801-195738.app`. The named pre-Slice-4 and pre-Slice-3 rollback bundles remain intact.

### Slice 6 — priority launch panes

Migrate Agents, Models, Permissions, Memory, Browser, and Computer Use as one semantic campaign, delivered in reviewable commits.

Exit:

- each pane distinguishes draft, persisted, applied, and current-tab live;
- all launch-impact changes state restart scope;
- permission prompts happen only after explicit actions;
- catalog/provider loading remains off-main.

#### Slice 6 implementation receipt — 2026-08-01

- Code is committed at `1856cca4a77cd5ff39bffa23f337714bdd82357d` on `codex/warm-glass-ui`. The final receipt commit is documentation-only, so the signed installed bundle remains a clean source ancestor under the mandatory preflight rule.
- Agents, Models, Permissions, Memory, Browser, and Computer Use now receive parent-owned `SettingsValueState` drafts. The migrated controls no longer use `@AppStorage` as mutable view state; only explicit Apply persists launch-impact settings. Agents and Models declare future-session scope, while Permissions, Memory, Browser, and Computer Use state their current-live-tab restart scope.
- Provider/config/catalog work remains in the existing detached background loader and checks cancellation after loading. Hidden panes cancel their view-owned tasks; the parent-owned Agent default draft was visibly retained through an App-pane round trip and then reverted without persistence.
- Browser diagnostics declare themselves read-only and operate from applied settings. Computer Use no longer requests Screen Recording when a switch changes: macOS permission requests require the explicit request buttons. Provider connection tests, browser diagnostics, helper tests, permission prompts, and settings Apply actions were deliberately not invoked during acceptance.
- `swift test --filter 'SettingsTabTests|LifecycleAndSubprocessTests|BrowserIntegrationTests|ComputerUseIntegrationTests|AgentsAndCapabilitiesTests|CustomModelTests'` completed **125 tests with 0 failures** in 2.223 seconds; `make test` completed **460 tests with 0 failures** in 14.715 seconds.
- The exact installed `/Applications/GrokBuild.app` visibly showed `Personal • codex/warm-glass-ui @ 1856cca4` after a graceful quit/relaunch. Its executable matches `dist` at SHA-256 `5371d17205359756d52b56af352631c100c9ce3e77e1d024732d4d4efe95058e`; deep/strict signing passes, quarantine is absent, and the immediate recoverable predecessor is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-6-20260801-2025.app`. No provider send, connection test, backend, browser process, helper test, or owned child was started.

### Slice 7 — MCP, Compatibility, and extensions

Migrate MCP Servers, Workflows, Skills, Plugins, Marketplace, Hooks, Compatibility, and App.

Exit:

- MCP round trips structured data and respects the verified secret-storage contract;
- current externalCompat cells decode;
- no empty-success swallowing;
- plugin/marketplace trust is explicit;
- long-running operations are row-local and cancellable where safe.

#### Slice 7 implementation receipt — 2026-08-01

- Code is committed at `99a7b1dfa68fe51eeee7d4e37dc3759feba1beb0` on `codex/warm-glass-ui`. The final receipt commit is documentation-only, so the signed installed bundle remains a clean source ancestor under the mandatory preflight rule.
- MCP Servers now uses a parent-owned structured draft with explicit stdio/http/sse transport and user/project scope, exact ordered argument rows, environment/header secret fields, current 0.2.118 CLI serialization, literal-storage disclosure, redacted inventory/diagnostics, bounded Doctor work, row-local receipts, and destructive remove confirmation. Secret values never enter retained inventory or receipts.
- Workflows, Compatibility, and App use parent-owned `SettingsValueState` drafts and explicit Apply scopes. Workflow and Compatibility Live copy admits that it is inferred only from an exact newer app-launched process receipt. Compatibility writes supported cells atomically and strictly decodes the current 13-cell `externalCompat.cells` schema while retaining legacy-array compatibility; Codex remains sessions-only. App update scheduling is external-config-only, and installed/update identity is separate from active-session identity.
- Skills, Hooks, Plugins, and Marketplace use retained `SettingsInventoryState` snapshots with checking/empty/stale/error/retry truth. Plugin and Marketplace mutations require explicit trust, provenance remains visible, destructive operations confirm, and safe hidden-pane/row-local tasks cancel through `BoundedProcess`. Independent Marketplace source/plugin loads cannot erase one another's successful result.
- `swift test --filter 'SettingsExtensionContractTests|SettingsTabTests|CompatConfigTests|WorkflowRunTests|SessionLifecycleTests|SubprocessHygieneTests'` completed **58 tests with 0 failures** in 4.659 seconds; `make test` completed **470 tests with 0 failures** in 14.391 seconds.
- The signed installed app visibly exercised all eight Slice 7 panes without a provider send or mutation. A non-secret MCP draft survived App → MCP and Revert restored the clean fields. Hooks reported a successful empty result, Compatibility displayed six Cursor plus six Claude plus one Codex session cell, Marketplace displayed the xAI Official source and separate unchecked trust gates, and App displayed `Personal • codex/warm-glass-ui @ 99a7b1df` independently from an Unknown/no-process session receipt.
- Exact `/Applications/GrokBuild.app` quit/relaunch passed. The bundle stamps clean commit `99a7b1dfa68fe51eeee7d4e37dc3759feba1beb0`; dist/install executables both SHA-256 `215472a9bd56dbe3f06c7a922e47d1b432f6922e3f7d26198e04ef795278af7f`; deep/strict signing passes under Team `DD2GCQJVB4`; quarantine is absent. `~/.grok/config.toml` stayed mode `0600`, 1,852 bytes, SHA-256 `54986189bf364f6abe7a06876425b576f9b02466177b181d4921640d4a62bce4`; v2 stayed 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. The settled app had zero owned children and sampled 0.0% CPU three times. Immediate rollback is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-7-20260801-2102.app`.

### Slice 8 — incremental transcript storage

**Primary files:** SessionMessageStore.swift, ContentView.swift, ChatStore.swift, migration tests.

Deliver:

- file-backed per-tab transcripts;
- serialized atomic writer;
- dirty-generation writes;
- verified copy-first migration;
- metadata-only counts.

Exit:

- selecting a tab produces no full-map rewrite;
- 1,000-message fixture meets budget;
- rollback can still read the old snapshot;
- permissions are owner-only.

#### Slice 8 implementation receipt — 2026-08-01

- Code is committed at `68de2a9d5b774fc98fd5c126247fcd834d316c65` on `codex/warm-glass-ui`. The final receipt commit is documentation-only, so the signed installed bundle remains a clean source ancestor under the mandatory preflight rule.
- `SessionMessageStore` now owns one file-backed transcript and one metadata sidecar per local tab. Its dedicated serial queue, sibling-temp plus rename writer, owner-only permissions, and monotonic dirty generation avoid whole-map rewrites; unchanged generations are skipped. Session layout restores counts from authenticated metadata, while only the selected tab hydrates its message body.
- Legacy `GrokBuild.sessionMessages.v1` migration is copy-first and verified: every candidate transcript is decoded and checked before a keyed marker is committed. Any failure leaves the entire v1 dictionary and no marker intact. The 33 retained v1 transcripts remain 128,256 bytes at SHA-256 `9aabac37d6ffe066d5b9853ea02c6223f4f73c32ee02fdebf462c39ec93d85c5`.
- `swift test --filter SessionPersistenceTests` completed **47 tests with 0 failures** in 0.105 seconds; `make test` completed **475 tests with 0 failures** in 15.113 seconds. The 1,000-message dirty-generation fixture completed within its 0.25-second budget.
- Installed-app migration created 33 transcript bodies, 33 metadata sidecars, and one migration marker (67 files total). The transcript directory is mode `0700`; every file is mode `0600`. `~/.grok/config.toml` stayed mode `0600`, 1,852 bytes, SHA-256 `54986189bf364f6abe7a06876425b576f9b02466177b181d4921640d4a62bce4`; the v2 rollback payload stayed 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`.
- Exact `/Applications/GrokBuild.app` visibly restored the local `GPT-CENTRAL-RESUME-BASE-0731` and follow-up messages, displayed the safe continuity boundary, and kept Send disabled. Command-Q followed by an exact relaunch restored the same local history. Selecting another saved tab left the complete transcript-tree digest unchanged at `b2c7c44d313f6e42ba60b650b51cc524502e5e63cbda31b672873a919e9e3346`; no provider send, backend resume, helper, browser, or `grok agent` child ran. Settled CPU sampled 0.0% three times.
- The installed executable SHA-256 is `5908269a804b9af80421cdf8a476317fd4d3c52afa2b6f7bf48307000afb3d21`; deep/strict signing passes under Team `DD2GCQJVB4`, and quarantine is absent. Gatekeeper assessment remains rejected because this development-signed build is not notarized; that is not represented as release/notarization proof. Immediate rollback is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-8-20260801-2119.app`; the pre-Slice-7 rollback remains intact.

### Slice 9 — lazy lifecycle and rich-render performance

Deliver:

- selected-tab-only eager hydration;
- off-main history/config parsing;
- pane view-model retention without view-tree retention;
- parsed-rich-content cache;
- WebKit lifecycle bounds;
- signpost regression tests where practical.

Exit:

- startup and Settings budgets pass;
- hidden panes perform no recurring work;
- settled RSS is bounded across repeated Settings sweeps.

#### Slice 9 implementation receipt — 2026-08-01

- Code is committed at `3b5e1988ef79d8fb0d6b80bfbbcb84259b9399c1` on `codex/warm-glass-ui`; the signed installed bundle is stamped with that clean source commit. Selected-tab-only body hydration, off-main metadata/config parsing, retained Models state, bounded rich-content caching, and visible-only WebKit sizing/teardown were implemented without changing the authenticated v3 lifecycle or continuity contracts.
- `make test` completed **479 tests with 0 failures** in 14.166 seconds. Focused suites were green: `SettingsTabTests` 14, `SliceNinePerformanceTests` 4, `SessionPersistenceTests` 47, `MarkdownBlockParserTests` 11, and `SessionLifecycleV3Tests` 14, all with 0 failures. One earlier order-sensitive full-suite attempt reported three migration assertions; the succeeding full-suite runs passed without a source change.
- The installed `/Applications/GrokBuild.app` and `dist/GrokBuild.app` executables both hash to `002ccb8a32f852e64895228afd445aed2f4c7a7cd2d5519d34dc86980d8d529d`; deep/strict signing passes under Team `DD2GCQJVB4`, quarantine is absent, and Gatekeeper remains non-release proof because this Apple Development build is not notarized.
- Computer Use acceptance restored `GPT-CENTRAL-RESUME-BASE-0731` plus `GPT-CENTRAL-RESUME-FOLLOWUP-0731`, showed the local continuity boundary, and kept Send disabled. Models → Memory → Models retained the three-provider/three-custom-model inventory. Three complete fourteen-pane Settings sweeps passed with no Apply, connection test, provider send, backend resume, browser/helper action, or `grok agent` child.
- Warm Settings sweeps sampled 0.0% CPU and 83,120–89,152 KB RSS; the exact relaunch sampled 0.0% CPU and settled at 57,088–70,576 KB RSS. Command-Q left no GrokBuild, helper, or agent child. Config remained mode `0600`, 1,852 bytes, SHA-256 `54986189bf364f6abe7a06876425b576f9b02466177b181d4921640d4a62bce4`; the 67-file transcript tree remained digest `b2c7c44d313f6e42ba60b650b51cc524502e5e63cbda31b672873a919e9e3346`; v2 remains 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`.
- The immediate pre-Slice-9 rollback is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-9-20260801-215323.app`, stamped with the preserved Slice 8 commit `68de2a9d5b774fc98fd5c126247fcd834d316c65`; the named pre-Slice-8 and older rollback bundles remain intact. The app-owned update/last-flush receipt advanced during normal read-only launch/quit, but no Settings Apply or user transcript/config mutation was performed.

### Slice 10 — accessibility and scroll control

Deliver:

- detached-scroll state and Jump to latest;
- complete labels/values/help/focus order;
- System/Light/Dark appearance policy and semantic warm-glass palette;
- adaptive pane layouts;
- Reduce Motion/Transparency and contrast fixes;
- rich-content fallbacks;
- VoiceOver terminal announcements.

Exit:

- keyboard-only and VoiceOver scenarios pass in the installed app;
- no color-only, motion-only, or hover-only state remains;
- focus survives add/remove/apply/error flows.

#### Slice 10 implementation checkpoint — installed acceptance complete

- `ChatTranscriptScrollPolicy` now tracks bottom attachment from scroll geometry. Stream revisions and bounded rich-layout retries stop when a reader detaches; unread content is summarized once and the accessible **Jump to latest** action explicitly resumes following.
- Workbench, transcript, composer, Settings navigation, thinking/tool disclosures, code blocks, tables, equations, and diagrams expose task-oriented labels, values, hints, roles, and focus sections. Terminal connection failure, continuity blocking, model-switch rejection, completed turns, Jump to latest, and code copy use sparse VoiceOver announcements without token/loading spam.
- App appearance is now a real System/Light/Dark UserDefaults setting. Existing installs migrate to Dark once to preserve the established Slice 9 surface; new installs default to System. Dynamic palette tokens, contrast-aware borders, reduced transparency, reduced motion, adaptive composer rows, and large-text Settings rows are native SwiftUI/AppKit behavior.
- Mermaid and LaTeX retain selectable source fallbacks when WebKit or its CDN renderer is unavailable. Rich cache identity is bumped and web sizing includes appearance/reduced-motion/contrast presentation state; WebKit remains visible-only and explicitly dismantled.
- Focused tests cover detached scrolling/unread labels, appearance draft persistence, linear table descriptions, and rich fallback text. `make test` completed **482 tests with 0 failures** in 14.473 seconds; focused `SettingsTabTests` completed **16 tests with 0 failures**.
- The clean signed install at `/Applications/GrokBuild.app` stamps `22e95f31d9986d89129164477f5026fafd792174`; `dist` and installed executables match at SHA-256 `05114763add8d07f5fc390e2ff57d139b0f984d009126f663dcefc1d0d136d8d`. Deep/strict signing passes under Team `DD2GCQJVB4`, quarantine is absent, and Gatekeeper rejects only because this Apple Development build is not notarized.
- Installed Computer Use acceptance exercised the fixed appearance accessibility action through Dark apply, Light apply, and Dark restore without a crash. The only diagnostic report is the preserved pre-fix segmented-picker report at `/Users/jimmyschmitz/Library/Logs/DiagnosticReports/GrokBuild-2026-08-01-223824.ips`.
- Exact quit/relaunch restored `GPT-CENTRAL-RESUME-BASE-0731`, `GPT-CENTRAL-RESUME-FOLLOWUP-0731`, the local continuity boundary, empty composer, and disabled Send. Config, 67-file transcript storage, and v2 rollback bytes retained their recorded digests; no provider, backend, or authenticated v3 continuity action ran. Recoverable Slice 9 and Slice 10 checkpoints are recorded in `CANONICAL_WORKTREE.md`.

### Slice 11 — installed-app acceptance and release decision

Deliver:

- full test results;
- installed signed bundle receipts;
- three-tab/three-model lifecycle matrix;
- Settings round trips;
- continuity recovery marker;
- accessibility evidence;
- performance and soak report;
- rollback proof.

No merge or release follows automatically. Publication and release remain explicit operations under repository rules.

#### Slice 11 checkpoint — installed acceptance complete

- All fourteen Settings panes completed a fresh accessibility-tree round trip in the signed
  installed Slice 10 app. No Apply, provider connection, permission prompt, extension
  mutation, or provider send ran.
- Three saved tabs covered Grok 4.5, `deepseek/deepseek-v4-flash-0731`, and a temporary
  `gpt-5.6-terra` selection. The temporary selection was restored to Grok 4.5 before quit;
  exact relaunch recovered the saved DeepSeek tab and local-only continuity boundary.
- The ten-minute idle soak collected 61 samples: maximum CPU 0.0%, RSS bounded from
  22,096–114,544 KB, and zero owned children. Config and the 67-file transcript tree kept
  their Slice 10 digests.
- Signed rollback `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-12-20260801-232458.app`
  passed deep/strict verification before Slice 12 work began.
- The order-sensitive migration warning was promoted to a release blocker. Slice 12 now
  canonicalizes the keyed migration fingerprint and tolerates only sub-millisecond `Date`
  representation drift; three consecutive 489-test runs pass.

### Slice 12 — Grok and provider authentication

Deliver:

- visible Grok CLI sign-in state and exact `grok login --oauth` handoff without token custody;
- OpenRouter S256 OAuth plus paste-key setup, exact loopback callback enforcement,
  cancellation, local disconnect, and explicit remote-key management;
- device-only Keychain storage and non-secret credential provenance;
- explicit connection/auth/catalog contracts for every official provider preset;
- no secret-bearing logs, receipts, UserDefaults values, or source fixtures;
- focused provider tests, full-suite stability, signed installed acceptance, and rollback proof.

## 21. Automated verification matrix

### V1. Restore and persistence

Extend Tests/GrokBuildTests/SessionPersistenceTests.swift:

- saved viable selection wins;
- cold-launch new-tab policy bypasses restore selection without mutating saved records;
- saved empty selection does not outrank viable MRU;
- first qualified MRU wins regardless of transcript size;
- ordinal ties resolve deterministically;
- rapid selection persists before quit;
- workspace switch and re-entry preserve per-workspace selection;
- more than four tabs preserve metadata while process LRU evicts only runtime;
- nil/inherited model stays nil through repeated cycles;
- legacyUnknown does not become explicit;
- explicit model/agent values round-trip;
- nonempty backend ID cannot be erased by teardown;
- fork mapping is atomic and reversible;
- v2 → v3 migration is idempotent and failure-closed.

### V2. ACP and process generation

Extend Tests/GrokBuildTests/ACPClientContractTests.swift and Tests/GrokBuildTests/LifecycleAndSubprocessTests.swift:

- launch receipt contains allowed fields and redacts forbidden fields;
- model request success with explicit effective model confirms;
- success without effective model stays Unknown/requested;
- explicit rejection preserves last confirmed state;
- timeout terminates pending state;
- old-generation success is discarded;
- wrong-tab, wrong-backend, duplicate, and out-of-order responses are discarded;
- reconnect/new-session-required produces an honest fork receipt;
- settings reload during streaming queues and coalesces;
- cancellation leaves no child process;
- per-tab process LRU never crosses receipt identity.

### V3. Transcript provenance and recovery

Extend Tests/GrokBuildTests/GrokSessionTranscriptImporterTests.swift and Tests/GrokBuildTests/GrokSessionReplayTests.swift:

- exact known backend imports root turns;
- synthetic-only history classifies empty;
- worker output remains provenance-tagged;
- root final is appended once;
- mixed provenance cannot verify binding;
- local verified prefix succeeds;
- local/backend divergence blocks;
- composite fixture classifies compositeSuspected;
- missing binding remains localOnly;
- candidate finder returns evidence without mutation;
- Continue as New records predecessor;
- Relink requires explicit candidate and re-verification.

### V4. Settings

Extend Tests/GrokBuildTests/SettingsTabTests.swift:

- all fourteen panes exist exactly once and retain grouping;
- every pane declares editable/read-only/direct-action behavior;
- every async pane has checking/content/empty/error/stale policy;
- adaptive row policy chooses vertical layout at constrained width/large text;
- hidden panes cancel or suspend work;
- shared state badge strings map to distinct accessibility values.

Extend pane-specific suites:

- BrowserIntegrationTests.swift: draft/applied/live, no false Setup needed, restart queue, readiness.
- ComputerUseIntegrationTests.swift: draft/apply, permission timing, screenshot-dependent readiness, helper receipt.
- CustomModelTests.swift: cache invalidation, unknown saved model, provider failure/stale data, redaction.
- CompatConfigTests.swift: 0.2.118 externalCompat object, 13 cells, legacy schemas, partial aggregate, error.
- MemoryStoreTests.swift: toggle semantics separate from note writes and content never logged.
- WorkflowRunTests.swift and configuration tests: failure preservation and reload scope.
- new or focused MCP editor tests: argument boundaries, env/header names, scope, malformed input, secret redaction.

### V5. Storage and security

- atomic replace survives injected interruption;
- concurrent writes serialize;
- unchanged sessions are not rewritten;
- file and directory modes are correct;
- migration count/digest mismatch leaves legacy data untouched;
- config mutation preserves unrelated content and 0600;
- Keychain secrets never serialize to UserDefaults;
- transcript comparison tags are versioned/keyed, invalidate safely after key loss, and never enter exported diagnostics;
- diagnostics contain no prompt, transcript, environment, header, rule, credential, or secret URL data;
- plugin/marketplace install cannot bypass trust confirmation.

### V6. Rendering and scroll

Extend Tests/GrokBuildTests/ChatTranscriptLayoutTests.swift and Tests/GrokBuildTests/MarkdownBlockParserTests.swift:

- attached reader follows streaming;
- detached reader never receives forced scroll;
- Jump to latest count and action work;
- final settle performs at most one correction while attached;
- parsed-cache key changes on content/render-version changes;
- math/Mermaid failure provides accessible fallback;
- 1,000-message fixture stays within memory and interaction budgets.

### V7. Required command

Every code-bearing slice runs:

~~~bash
make test
~~~

Report the actual executed test count and failures. The historical 413/0 baseline is evidence, not a reusable claim.

## 22. Installed-app Computer Use acceptance

Per .cursor/rules/docs-and-tests.mdc, every code-bearing slice also requires the running app. Unit tests cannot bless lifecycle truth.

### U1. Artifact preflight

Before UI acceptance:

- build and install through the repository’s current documented flow;
- verify /Applications/GrokBuild.app is the process actually launched;
- record bundle channel, source repository, branch, source commit, and dirty stamp;
- verify installed/distribution executable SHA-256 parity;
- verify expected helper presence;
- verify deep/strict code signing and quarantine status;
- record CLI version and update receipt;
- prove the stamped commit is the intended canonical branch ancestor when HEAD moved.

### U2. Three-tab, three-model matrix

Create controlled tabs A, B, and C with distinct:

- local tab UUID;
- title marker;
- explicit model or inheritance state;
- agent/effort where relevant;
- backend ID;
- transcript marker.

Run:

1. Quit with A selected; relaunch.
2. Close window without quitting; reopen.
3. Switch A → B and immediately quit; relaunch.
4. Change B model; observe pending → confirmed or Unknown; quit/relaunch.
5. Change default; reopen existing explicit tab.
6. Change default; create a genuinely new tab.
7. Change global agent; compare inherited and explicit tabs.
8. Apply a restarting Settings change during idle.
9. Queue one during streaming.
10. Restore a local-only tab.
11. Restore a stale/wrong backend fixture.
12. Exceed four live tabs and return to the evicted tab.

For each row capture:

| Layer | Evidence |
|---|---|
| Visible | project, tab title, model/agent/effort, continuity state |
| Local | tab UUID, model/agent intent, activation ordinal |
| Persistence | saved layout and transcript generation |
| Process | process generation, launch receipt, requested values |
| Backend | exact ID, verified relationship, actual history marker |
| Relaunch | same intended state and honest receipts |

### U3. Settings round trips

Visit all fourteen panes. For editable panes:

- make a harmless draft;
- prove leaving/reopening preserves or discards according to explicit policy;
- Revert;
- Apply a bounded non-secret change when safe;
- verify persisted and live scope;
- quit/relaunch;
- verify round trip;
- restore the original value through the same UI.

For read-only panes, prove successful empty versus failed load. For direct-action panes, use only reversible or test-safe actions.

### U4. Accessibility

Capture AX tree and screenshots at the exact affected states:

- sidebar and session identity;
- model pending/confirmed/failed;
- continuity warning and actions;
- detached scroll and Jump to latest;
- each shared Settings state;
- narrow Settings layout;
- long transcript with heading, list, table, link, code, math, and Mermaid.

Run VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency, Differentiate Without Color, Reduce Motion, large text, light mode, and dark mode. Record failures by control and state, not “accessibility looks good.”

### U5. Performance and soak

- at least five cold and ten warm measurements for startup;
- ten tab switches across short and 1,000-message transcripts;
- five cold loads for Skills, Marketplace, Models, and App;
- streaming first-chunk and settled-render timing with a local fixture separated from provider latency;
- ten-minute idle soak after the full Settings sweep;
- repeated open/close Settings and tab churn to assess settled RSS;
- process tree at start and end;
- no orphan helper or Grok child.

Automation timing must identify snapshot/AX overhead separately from app signposts.

## 23. Rollout and rollback

### R1. Development rollout

- Land one slice per focused commit or tightly related commit series.
- Keep fixtures synthetic and deterministic.
- Run migration tests before exercising a real profile.
- First installed-app acceptance uses a copy of test state, not the only user state.
- Enable v3 dual-read and new-write only after v2 rollback decoding is green.
- Keep old transcript preferences untouched during the first file-store release.
- Record the exact commit and app stamp for every acceptance packet.

Avoid a permanent matrix of hidden production feature flags. A development-only switch may compare old/new restore decisions, but the shipped app should have one state authority.

### R2. Release order

Correctness order is mandatory:

1. Restore intent and model inheritance.
2. Generation-bound runtime receipts.
3. Continuity gate.
4. Recovery/provenance.
5. Settings truth.
6. Storage and performance.
7. accessibility/polish.
8. installed acceptance.

Do not ship file migration while backend binding is still ambiguous. That would make two stores easier to misdiagnose, which is impressively unhelpful.

### R3. Rollback by layer

| Failure | Rollback |
|---|---|
| UI/accessibility regression | Install prior known-good bundle; state format remains readable |
| Settings apply regression | Stop writes, restore exact config backup if a proven mutation occurred |
| v3 lifecycle decode failure | Fall back to read-only v2 snapshot; retain v3 artifact for diagnosis |
| Transcript migration failure | Read legacy UserDefaults; leave verified files unused |
| Process/model receipt failure | Display Unknown and block false confirmation; do not rewrite saved model |
| Continuity false positive | Block send, restore prior binding record, preserve both transcripts |
| CPR failure | Restore only the exact mutated artifact from verified recovery directory |

Rollback is bundle-first and state-preserving. Use the existing stage-then-atomic-swap installation path. Reinstalling is never a reason to delete preferences or histories.

### R4. Hard stops

Stop packaging or release when:

- any visible model/backend state lacks its declared receipt;
- a migration mismatch occurs;
- a test fixture auto-binds a composite or unknown transcript;
- secrets appear in logs, diagnostics, UserDefaults, screenshots, or test output;
- a Settings pane reports empty after an inspection error;
- keyboard focus is trapped or lost after a primary action;
- hidden panes or idle children show sustained work;
- installed artifact identity does not match the evidence packet;
- the worktree contains unrelated user changes that cannot be isolated.

## 24. Documentation obligations during implementation

Each code-bearing slice updates:

- ARCHITECTURE.md for new lifecycle types, state flow, persistence schema, notifications, and source map;
- README.md for visible model/continuity/Settings behavior when user-facing;
- BUILDING.md and scripts/README.md if packaging, signing, install, or evidence commands change;
- .cursor/skills/grokbuild-grok-cli/SKILL.md and the CLI integration rule if Grok CLI semantics change;
- .cursor/skills/grokbuild-dev/SKILL.md for new tests, fixtures, or profiling commands;
- docs/UI_ACCEPTANCE_MATRIX.md with new continuity, model-truth, Settings, and accessibility cases;
- this plan’s status and actual receipts.

Do not mark a slice complete from code alone. Record:

- commit;
- tests executed and count;
- installed bundle stamp;
- Computer Use state tested;
- performance delta;
- known limitations;
- rollback artifact.

## 25. Audit-hole traceability ledger

| Audit hole | Repair owner | Proof |
|---|---|---|
| Local tab points to unrelated/synthetic backend | A, J, CPR | Divergent/composite fixture blocks send; explicit fork/relink marker relaunch |
| Known non-nil backend bypasses useful recovery | A3 | Empty/synthetic known-ID test enters review instead of success |
| Local transcript is composite | A2, J | Provenance fixture; no auto-binding; local work preserved |
| “MRU” chooses longest transcript | B1 | Large-old versus small-recent deterministic test |
| Saved selection behavior feels arbitrary | B1, B4 | RestoreDecision reason visible and AX-readable |
| Inherited model frozen as explicit override | B2, M1 | Nil intent survives repeated restore/persist |
| Saved model absent from initial catalog is ignored | C3 | Unknown model stays visible and actionable |
| set_model success looks confirmed without effective value | C2 | Missing-meta ACP fixture remains Unknown/requested |
| Default model cache/propagation is stale | C4 | Save invalidates catalog; new/existing tab matrix |
| Process receipt cannot prove tab/backend/model identity | E4, C2 | Generation-bound credential-free receipt |
| Agents Save mutates before Save | F1 | Close-unsaved test leaves storage unchanged |
| Permissions Apply mutates before Apply and is always enabled | F13 | Draft/clean/invalid/applied/live tests |
| Memory toggle mutates before Apply | F3 | Draft versus active-process proof |
| Browser briefly shows false Setup needed | F5 | Checking-first installed capture |
| Browser badge uses draft rather than applied/live | F5 | Draft/applied/live status tests |
| Computer Use mixes immediate/deferred semantics | F6 | Explicit direct actions and Apply scope |
| MCP editor destroys argument boundaries | F7 | Structured round-trip fixtures |
| MCP env/header/secret gap | F7, K | Version-matched CLI contract and redaction tests |
| Skills pane is slow | F8, D5 | Cold-load signpost budget |
| Marketplace pane is slow and trust is too implicit | F10, K3 | Load budget and provenance confirmation |
| Compatibility parses stale schema and shows empty success | F12 | 0.2.118 externalCompat 13-cell fixture |
| Hooks/Skills errors can resemble empty | F8, F11 | Empty/error/stale state tests |
| App/current-session receipts blur together | F14, E4 | Separate installed, CLI, and live-session states |
| Visited Settings panes remain mounted | Section 13, Slice 9 | Hidden-pane activity and RSS sweep |
| Tab selection rewrites all transcript data | D1–D3 | Incremental-write instrumentation |
| Startup repeatedly decodes transcript map | D1, B3 | One selected transcript eager load |
| Legacy recovery scans many histories | D4, J3 | No ordinary-start scan; explicit bounded recovery |
| Rich messages repeatedly parse/create WebKit | H4 | Cache counters and long-transcript budget |
| Streaming scroll fights the reader | H3, I3 | Detached reader and Jump to latest tests |
| One idle CPU sample is insufficient | D5–D7, U5 | Repeated spans and ten-minute soak |
| Generic restart/reinstall could destroy evidence | Section 18 | Verified checkpoint and targeted CPR runbook |
| Live CPR copy could be a torn cross-artifact snapshot | CPR2 | Durable flush, controlled quit, zero owned children, shared-generation manifest |
| Legacy non-nil model could be misclassified explicit | M2 | All unproven v2 values migrate to legacyUnknown under a separate v3 key |
| Plain prompt hashes create sensitive derivatives | A1, K4 | Keychain-keyed versioned HMAC or memory-only comparison; no export |
| App forces darkAqua while acceptance asks for light mode | F14, I5 | System/Light/Dark implementation and existing-user migration |
| Visual state can outrun accessibility state | Section 15 | AX tree, keyboard, VoiceOver, visual settings matrix |

Any new audit finding gets a row here before implementation is declared complete.

## 26. Release evidence packet

Use this exact structure for the final repair closeout.

### Identity

| Receipt | Value |
|---|---|
| Worktree | |
| Branch | |
| Commit | |
| Personal remote branch SHA | |
| Worktree status | |
| Installed app path | /Applications/GrokBuild.app |
| Bundle source stamp | |
| Installed/dist executable SHA-256 | |
| Signature/quarantine | |
| Grok CLI version/channel | |

### Automated verification

| Suite/command | Count | Result | Duration |
|---|---:|---|---:|
| make test | | | |
| Migration fixtures | | | |
| ACP/process fixtures | | | |
| Performance fixtures | | | |

### Lifecycle matrix

| Scenario | UI tab/model | Persisted intent | Process receipt | Backend ID/history | Relaunch | Result |
|---|---|---|---|---|---|---|
| A selected quit/relaunch | | | | | | |
| A → B immediate quit | | | | | | |
| Existing tab after default change | | | | | | |
| New tab after default change | | | | | | |
| Settings restart | | | | | | |
| Local-only fork | | | | | | |
| Composite fixture | | | | | | |
| LRU eviction/return | | | | | | |

### Settings matrix

| Pane | Load/empty/error | Draft | Applied | Live receipt | Keyboard/AX | Result |
|---|---|---|---|---|---|---|
| Agents | | | | | | |
| Models | | | | | | |
| Memory | | | | | | |
| Workflows | | | | | | |
| Browser | | | | | | |
| Computer Use | | | | | | |
| MCP Servers | | | | | | |
| Skills | | | | | | |
| Plugins | | | | | | |
| Marketplace | | | | | | |
| Hooks | | | | | | |
| Compatibility | | | | | | |
| Permissions | | | | | | |
| App | | | | | | |

### Performance

| Lane | Corpus/runs | Before p50/p95 | After p50/p95 | Budget | Result |
|---|---|---|---|---|---|
| Cold first usable window | | | | ≤ 3 s p95 | |
| Warm first usable window | | | | ≤ 700 ms p95 | |
| Correct receipt after window | | | | ≤ 1.5 s p95 | |
| Tab switch | | | | ≤ 250 ms p95 | |
| Skills cold | | | | ≤ 1.0 s p95 | |
| Marketplace cold | | | | ≤ 1.2 s p95 | |
| 1,000-message restore | | | | ≤ 1.0 s p95 | |
| Idle ten-minute CPU/RSS | | | | bounded | |

### Accessibility

| Mode | Surface | Evidence | Result |
|---|---|---|---|
| Keyboard only | Workbench + all Settings panes | | |
| VoiceOver | Identity/model/continuity/Settings | | |
| Increase Contrast | Warm-glass boundaries/status | | |
| Reduce Transparency | Workbench/Settings | | |
| Differentiate Without Color | All status states | | |
| Reduce Motion | Loading/streaming/transitions | | |
| Large text + narrow window | Forms, MCP, permissions, composer | | |

### Recovery and rollback

- Recovery directory and manifest verified:
- Old → new backend mapping:
- Unique marker:
- Relaunch proof:
- Known-good rollback bundle:
- State rollback tested:
- Recovery artifacts retained until:

### Remaining limitations

List authoritative fields the Grok CLI does not expose. “Backend model not independently exposed” is an acceptable limitation. Pretending the picker proved it is not.

## 27. Definition of done

GrokBuild is coherent when all of the following are true:

- The selected tab, local transcript, backend history, process generation, and model state form one auditable chain.
- Composite or divergent continuity fails closed without losing local work.
- Startup chooses the saved viable tab or true MRU deterministically and explains fallbacks.
- Inherited defaults remain inherited; explicit tab choices remain explicit.
- Requested model and confirmed model cannot be confused.
- All fourteen Settings panes share honest draft/saved/applied/live semantics.
- MCP and Compatibility match the current 0.2.118 CLI schema.
- Settings, transcript persistence, and rich rendering meet measured budgets without new heavy dependencies.
- The workbench respects reader-controlled scrolling.
- Keyboard, VoiceOver, contrast, transparency, motion, large-text, and compact-window acceptance pass.
- Full tests pass with the current count.
- The signed installed app, not a development process or source-only build, passes the lifecycle, Settings, accessibility, performance, and soak matrix.
- Rollback is verified and preserves user data.
- ARCHITECTURE.md, user docs, tests, and acceptance records match the shipped behavior.

## 28. Explicit non-goals

This repair does not:

- add a second agent runtime, daemon, database, web framework, or telemetry vendor;
- decide which language model is “smartest” from conversational style;
- rewrite or deduplicate Grok backend histories;
- auto-delete old tabs, transcripts, preferences, plugins, or recovery backups;
- make all Settings changes hot-reloadable;
- expose credentials for convenience;
- replace native macOS interaction with a custom design system;
- merge, release, or publish to upstream without separate authority.

The product promise after this work is modest and valuable: GrokBuild tells the truth about the work in front of you, lets every user operate it, stays out of the way when healthy, and becomes extremely careful when continuity is not.

## 29. Post-merge provider truth closure — 2026-08-02

PR #1 was merged, installed from `main`, and then subjected to the separately authorized provider-send matrix. That matrix found one release blocker the send-free Slices 11–12 could not expose: a tab selected as OpenAI launched with the requested flag but ACP retained Grok 4.5, producing one wrong-provider billable call. Backend history and usage, not the picker, established the truth.

Repair commit `9304b7a1fe64ec13c27164bde12f0b6d33d0c8ba` now makes every explicit startup selection pass a generation-bound pre-send gate: reassert through `session/set_model`, require effective-model readback, and fail closed on missing or mismatched identity. Custom TOML selectors accept only their declared provider-facing model as an alternate readback. Focused ACP tests passed 27/27 and the full suite passed 493/493.

Installed billable acceptance passed direct OpenAI, Kimi, OpenRouter, and Grok routes. The subsequently authorized OpenRouter S256 OAuth flow completed through the system browser and device-only Keychain, after which DeepSeek V4 Flash, Gemini 2.5 Flash, and GPT-4.1 Mini each passed a separate one-call marker test with matching live/backend model identity and usage. This intentionally added two OpenRouter model entries and advanced normal transcript/session state; it did not remove prior sessions, direct-provider entries, authenticated v3 authority, or rollback bundles. Secrets and response bodies remain excluded from the repository and receipts.

PR #2 merged the repair as `eea6c9868154a38ab1f4c8ebe6263a2e7b8a5e6a`. The rebuilt, signed, installed `main` bundle reports that exact clean receipt, matches `dist` at executable SHA-256 `cdd16ecda766a2d9497b9db7d6733ad91bf52cc998b4add32f7bb04d9cdfeb6f`, and retains the OAuth-backed three-model Settings state. Deep/strict verification passes, quarantine is absent, and five settled Models-pane samples remained at 0.0% CPU with no owned child. The signed pre-merged-main repair bundle and all earlier named rollbacks remain recoverable.

The final exploratory switch test also identified a bounded non-release-blocking interoperability defect. A fresh session switched GPT-4.1 Mini → Terra → Grok successfully when its history contained only plain messages. In the user's sports session, Terra first completed a web-search turn with tool calls/results; after switching that same session to Grok, the next prompt failed `Invalid params` before any Grok usage or final answer. The live route receipt was correct, so this is cross-provider tool-history incompatibility rather than OAuth failure, silent fallback, or wrong selection. The operational rule is to start a new session before changing provider/model after a web or tool turn until safe history translation or isolation is implemented.
