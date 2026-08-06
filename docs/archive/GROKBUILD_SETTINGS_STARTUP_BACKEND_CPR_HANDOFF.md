# GrokBuild Settings, startup identity, performance, and backend CPR handoff

**Prepared:** 2026-08-01

**Purpose:** standalone prompt for a fresh Codex session

**Operating posture:** diagnose before changing; preserve sessions and user work; use the installed app as acceptance truth

## Mission

Audit the maintained GrokBuild app after the Grok CLI `0.2.118` update and determine:

1. Which current Grok capabilities/settings are missing, stale, mislabeled, duplicated, or exposed in the wrong place.
2. Why app launch and ordinary navigation feel slower than they should.
3. Why reopening GrokBuild can land on the same or an unexpected tab and present the wrong LLM for the work Jimmy intended to resume.
4. Whether the live Grok backend is merely restoring according to current policy, is receiving the wrong client state, or needs bounded CPR.
5. Which UI/UX changes would make GrokBuild feel fast, calm, native, and trustworthy as a project workbench.

Treat this as a product-state and lifecycle audit, not a decorative chatbot reskin. Project/session identity, the actual launched model, backend session continuity, applied settings, tool readiness, receipts, and durable transcripts outrank cosmetic chrome.

## Jimmy's reported symptoms

- The app feels **a tad slow**.
- On open, GrokBuild may return to **the same tab or some other restored state that does not feel intentional**.
- The visible/resumed session may not be running **the LLM Jimmy expects**.
- Settings may be behind the latest Grok update or may not clearly distinguish what is configured, applied, inherited, session-specific, or actually live.
- A backend health check and possibly controlled CPR may be needed.

Do not explain these away as user confusion. First reconcile the visible tab, saved layout, live process launch receipt, backend session, and on-disk transcript.

## Canonical identity — hard stop

Only this application line is active:

| Identity | Canonical value |
|---|---|
| Worktree | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Jimmy repository | `https://github.com/schmitzjimmy1-star/grok-build-desktop` (`personal`) |
| Preserved upstream | `https://github.com/rimusz/grok-build-desktop` (`origin`) |
| Branch | `codex/warm-glass-ui` |
| Installed app | `/Applications/GrokBuild.app` |
| Draft PR | `https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/1` |

The retired `/Users/jimmyschmitz/Documents/Grok Builf` / `jimmmy-Jim/Grok-Build-GUI` repository is historical evidence only. Do not build, install, continue, or publish it.

Before any diagnosis, read in order:

1. `CANONICAL_WORKTREE.md`
2. `AGENTS.md`
3. `ARCHITECTURE.md`
4. `docs/UI_ACCEPTANCE_MATRIX.md`
5. `docs/UI_UX_REVIEW_2026-07-31.md`
6. `GROKBUILD_REPO_STATUS.md` in the parent project folder

## Current verified baseline

At handoff creation:

| Receipt | Value |
|---|---|
| Local branch/remote | `codex/warm-glass-ui...personal/codex/warm-glass-ui` |
| Local and personal remote HEAD | `d1238c37b246295017b203d8b0cc67cf77e22400` |
| Worktree | Clean |
| Installed build channel | `personal` |
| Installed source repository | `https://github.com/schmitzjimmy1-star/grok-build-desktop` |
| Installed source branch | `codex/warm-glass-ui` |
| Installed source commit | `f7cb31837bd48685fe5338342ef489ffb6b313e9` |
| Installed source dirty | `false` |
| Installed/dist executable SHA-256 | `464e2cd2bdcfa7e1ba2b94a3b442ca35677e25a00a7cab8b10fd09b78f84ccd8` |
| Grok CLI | `grok 0.2.118 (1e1687c1cf6a) [stable]` |
| Update check | Installed `0.2.118`; latest `0.2.118`; no update available; stable channel |
| Prior full suite | 413 tests, 0 failures — historical baseline, rerun before packaging any repair |

One live read-only process snapshot showed:

```text
/Applications/GrokBuild.app/Contents/MacOS/GrokBuild
└─ grok --agent general-purpose --experimental-memory --always-approve \
        --reasoning-effort low --model grok-4.5 stdio
   ├─ grokbuild-browser-mcp
   └─ GrokBuildComputerUseMCP
```

The processes were idle at `0.0%` CPU in that single snapshot. This is not a performance clearance; it only says there was no sustained idle spin at that instant. The actual launched model was `grok-4.5`. Reconcile that with the visible model control and saved tab model before calling it correct or wrong.

The previous installed acceptance ended with Settings at Always approve, Sandbox Default, web enabled, subagents enabled, Browser Tools Ready, Computer Use Ready, Accessibility granted, and Screen Recording disabled. Treat that as prior evidence, not current truth; verify it again.

## Authority and safety

This handoff authorizes **read-only diagnosis and an evidence-backed repair proposal**. It does not by itself authorize code/config edits, reinstalling, clearing preferences, deleting sessions, publishing, committing, pushing, merging, or changing credentials. If Jimmy begins the receiving task with **full send** or separately authorizes repair, implement and verify the smallest coherent fix.

Always:

- Preserve the dirty tree if it has changed since this handoff; never reset, checkout, clean, or stash Jimmy's work.
- Never print provider credentials, Keychain values, unrestricted environment dumps, or the full Grok config.
- Back up exact preference/config files before any authorized state surgery.
- Never delete `~/.grok/sessions`, local transcripts, layout records, or Grok memory as a troubleshooting shortcut.
- Use Computer Use against the exact installed path and re-query the accessibility tree before every action and after UI changes.
- Separate model behavior from product behavior.

## Phase 1 — identity and live-state preflight

Run and retain concise, non-secret receipts:

```bash
cd '/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop'
pwd
git status --short --branch
git remote -v
git rev-parse HEAD

/usr/libexec/PlistBuddy -c 'Print :GrokBuildBuildChannel' \
  /Applications/GrokBuild.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :GrokBuildSourceRepository' \
  /Applications/GrokBuild.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :GrokBuildSourceBranch' \
  /Applications/GrokBuild.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :GrokBuildSourceCommit' \
  /Applications/GrokBuild.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :GrokBuildSourceDirty' \
  /Applications/GrokBuild.app/Contents/Info.plist

shasum -a 256 \
  dist/GrokBuild.app/Contents/MacOS/GrokBuild \
  /Applications/GrokBuild.app/Contents/MacOS/GrokBuild

/Users/jimmyschmitz/.grok/bin/grok --version
/Users/jimmyschmitz/.grok/bin/grok update --check --json
```

Stop if identity or executable parity no longer matches. If HEAD is later than the installed stamped commit, prove ancestry and that product/build paths are unchanged before treating the artifact as current.

## Phase 2 — Settings parity against the current Grok CLI

Do not start from Settings labels. Start from the CLI's current first-party contract:

- `grok --help`
- `grok agent --help`
- relevant subcommand `--help`
- a redacted `grok inspect --json`
- `grok models`
- `grok update --check --json`
- current xAI Grok Build documentation and `xai-org/grok-build` source for the exact installed CLI version when local help is insufficient

Use primary sources only. Never assume that a new CLI feature belongs in Settings; decide whether it belongs in Settings, per-session chrome, a command menu, a status receipt, or nowhere in GrokBuild.

Audit the fourteen current Settings destinations:

1. Agents
2. Models
3. Permissions
4. Memory
5. Workflows
6. Browser
7. Computer Use
8. MCP Servers
9. Skills
10. Plugins
11. Marketplace
12. Compatibility
13. Hooks
14. App

Build this matrix before proposing UI changes:

| CLI capability/config | CLI truth/source | Current GrokBuild surface | Stored value | Applied/live value | Restart required? | Status |
|---|---|---|---|---|---|---|
| Example | command/help/config key | Settings tab or session control | redacted receipt | live process/ACP receipt | yes/no | current, missing, stale, misleading, duplicate |

Explicitly test:

- Draft versus applied Browser and Computer Use values.
- Settings values versus the live `GrokLaunchReceipt` after restart.
- Defaults for **new sessions** versus overrides attached to an existing tab.
- Per-tab model and agent versus per-project reasoning effort.
- Global/default model versus the model actually passed to `grok agent stdio`.
- Update receipt refresh while the App pane remains mounted.
- Slow Keychain/provider loading in Models; no synchronous credential work on the main actor.
- Whether a capability exists in the CLI but is absent, stale, or confusing in GrokBuild.
- Whether Settings offers controls the CLI ignores or whose effect is not visible.

Do not dump `~/.grok/config.toml`. Extract only the names and non-secret keys needed to prove a mismatch.

## Phase 3 — wrong-tab / wrong-LLM launch investigation

The current architecture intentionally restores a selected or recent populated tab, and models are per tab. That policy may be implemented incorrectly, may be correct but poorly communicated, or may no longer match Jimmy's desired launch behavior. Prove which.

For three controlled sessions using different models, record this complete chain:

| Layer | Required receipt |
|---|---|
| Visible UI | selected project, tab title, model control, agent pill, effort |
| Local tab | stable tab UUID |
| Saved layout | selected session UUID, workspace ID, saved model, agent, last accessed |
| ChatStore | `currentModel`, effective agent, project effort, durable Grok session ID |
| Process | launch receipt and redacted process arguments |
| Backend | exact Grok session ID and exact history path |
| Restore | selected tab/model immediately after quit and relaunch |

Test these cases independently:

1. Quit with session A selected; relaunch.
2. Close the window without quitting; reopen from the Dock.
3. Switch A → B immediately before quitting; relaunch.
4. Change B's model and wait idle; quit/relaunch.
5. Change the project default model, then reopen an existing tab.
6. Change the project default model, then create a genuinely new tab.
7. Change the global/default agent and compare untouched versus overridden tabs.
8. Relaunch after Settings applies a process-restarting change.
9. Relaunch when the saved selected tab is empty, missing a backend, or lacks a restorable transcript.
10. Relaunch with more sessions than the four-process LRU cap.

Primary code path:

- `GrokBuild/ContentView.swift`
  - `restorePersistedSessions`
  - `selectSession`
  - `ensureSessionStarted`
  - `bindTabSession`
  - `syncTabModelToLiveProcessIfNeeded`
  - `persistSessionLayout`
- `GrokBuild/Services/SessionLayoutStore.swift`
  - `SavedSessionRecord`
  - selected-session and last-accessed persistence
- `GrokBuild/Services/ChatStore.swift`
  - `prepare`, `start`, `restartProcess`, `resolvedResumeSessionID`
  - per-tab model/agent binding and project-effort resolution
- `GrokBuild/Services/GrokProcess.swift`
  - launch receipt, session load/new, `session/set_model`
- `GrokBuild/Services/GrokModelCatalog.swift`
- `GrokBuild/Services/SessionMessageStore.swift`
- `GrokBuild/Services/SessionTranscriptRecovery.swift`

Likely questions to answer—not assumptions to patch:

- Is `selectedSessionID` actually persisted before shutdown?
- Does launch select the saved tab, MRU populated tab, or first tab, and is that decision visible?
- Does a saved per-tab model override the user's newer default by design?
- Can an absent saved model inherit from the wrong workspace or sibling tab?
- Can `session/set_model` fail while the composer still appears to show the requested model?
- Does a stale backend fallback create a new session using an unintended model?
- Is the correct model passed at process start but later replaced by ACP state?
- Is the UI simply reopening a valid old tab whose model is correct for that tab but surprising to Jimmy?

The fix must make three concepts unmistakable: **default for new sessions**, **saved choice for this tab**, and **effective model in the live backend**.

## Phase 4 — performance investigation

Break “slow” into measured lanes:

| Lane | Measure |
|---|---|
| Cold launch | process start → first usable window |
| Restore | window visible → correct tab/transcript rendered |
| Backend startup | process spawn → ACP ready |
| First turn | send accepted → first visible chunk |
| Streaming | chunk cadence, scroll stability, main-thread occupancy |
| Settling | final chunk → stable rich transcript and idle CPU |
| Settings navigation | click → pane interactive, especially Models/App/Plugins |
| Tab switch | click → correct transcript/model control interactive |
| Idle | sustained CPU/memory and orphan helper count |

Inspect, with evidence:

- Main-thread synchronous disk reads, JSON decoding, Keychain access, CLI discovery, update checks, config parsing, and backend-history import.
- `ContentView` invalidation breadth while streaming and restoring.
- Keep-alive Settings panes that continue expensive work while hidden.
- Repeated process restarts or capability refreshes after one Settings change.
- Rich Markdown/WebKit reconstruction and autoscroll retry cost on long transcripts.
- LRU churn and duplicate Grok/helper processes.
- Whether update checks or `grok inspect` block first paint.

Use the signed installed release build for user-perceived timing. Debug builds and unit tests are diagnostic aids, not performance acceptance. Capture a short Activity Monitor/Instruments or `sample` receipt only when it answers a specific stall; do not leave giant traces in the repo.

Performance acceptance should include cold launch, warm reopen, Settings round trip, a long restored transcript, one streaming turn, settled idle, and at least ten minutes without sustained core pinning.

## Phase 5 — bounded backend CPR

CPR is escalation, not the opening move.

### Pulse

- Confirm exactly one installed GrokBuild process.
- Map each live Grok child to one visible tab and durable backend ID.
- Check for orphaned `grok`, browser MCP, Computer Use MCP, and `agent-desktop` children.
- Capture redacted launch arguments and CPU/memory.

### Airway

- Confirm CLI version/update status and authentication without printing tokens.
- Confirm `grok models` and a minimal one-shot CLI command work outside the app.
- Validate only the structural portions of `~/.grok/config.toml`; never print credentials.
- Confirm the workspace path exists and matches the encoded backend-history directory.

### Circulation

- Follow one short marker turn end-to-end: visible tab → local message store → ACP events → exact backend history → restored UI.
- Confirm prompt completion, final synthesis, model identity, tool receipts, and durable session ID agree.
- Confirm a Settings reload resumes the same backend or visibly discloses a lossless fork.

### Controlled restart

If the pulse/airway/circulation receipts justify it:

1. Save all live transcripts and layout state.
2. Quit the exact installed app.
3. Prove its Grok/helper children exit.
4. Relaunch `/Applications/GrokBuild.app`.
5. Verify selected tab, visible model, live launch receipt, backend ID, and transcript before sending.
6. Send one unique marker and verify it immediately and after another relaunch.

Do not delete preferences or sessions. If one saved record is corrupt and repair is authorized, first copy the exact preference plist and affected backend/local transcript files to a timestamped recovery directory; change only the proven-invalid record and document the mapping.

Reinstall only if the installed signature, provenance stamp, helper executability, or dist/install hash is invalid. A reinstall is not a cure for incorrect persisted session selection.

## Phase 6 — UI/UX feel

Target feeling: **fast native project cockpit, not ornate chatbot**.

Evaluate:

- Does launch immediately tell Jimmy which project/session/model is being restored?
- Can he distinguish current-tab model from default-for-new-sessions without reading documentation?
- Does the model control show requested, switching, failed, and live-confirmed states honestly?
- Are process-restarting Settings changes labeled before Apply?
- Are draft and applied capability values visibly different when they diverge?
- Is there a concise live backend receipt available without opening a developer log?
- Does Settings explain inheritance: global → project → tab → live process?
- Are empty/loading/error states calm, specific, and actionable?
- Does a restored long transcript appear promptly without jumping, blanking, or stealing focus?
- Can Jimmy intentionally choose “resume last work” versus “new session with default model”?
- Are controls native-sized, keyboard reachable, and accessible without bloating the chrome?

Prefer removing ambiguity over adding decoration. A small line such as “Restoring **Session B** with **GPT 5.6 Terra**” can be more valuable than another card, gradient, or icon.

## Automated coverage expected if repair is authorized

Add deterministic tests for:

- Selected-session persistence across quit/relaunch.
- Restore policy with populated, empty, missing, and stale-backend tabs.
- Per-tab model versus project/global default precedence.
- Live model-switch success, failure, and “new session required” truthfulness.
- Model/agent preservation across idle and queued Settings reloads.
- No sibling-tab model leakage.
- No selected-session overwrite from teardown's transient `nil`.
- Settings draft/applied divergence and restart behavior.
- Settings tab completeness against an explicit current capability inventory.
- Off-main loading for slow providers/Keychain/config/inspection work.
- No regression to transcript settlement, bottom-follow, Stop, LRU eviction, or session recovery.

Run focused suites during development and the complete `make test` suite before packaging. Report the exact count and failures; historical counts are not current proof.

## Installed-app acceptance if repair is authorized

Use the exact installed path and prove:

1. Cold launch reaches an interactive, correctly identified restored session promptly.
2. Warm reopen preserves the exact selected tab without respawning unnecessary backends.
3. Three tabs with three models restore with no cross-tab leakage.
4. A new tab uses the documented new-session default.
5. The visible model equals the live launch/ACP receipt and backend result.
6. Settings inventory matches the supported CLI surface, with intentional omissions documented.
7. Draft/applied settings and restart requirements are obvious.
8. Settings navigation, tab switching, streaming, rich settling, and idle show no sustained UI stall or core pin.
9. One bounded backend CPR cycle, if actually needed, preserves every transcript and durable session ID or explicitly records a lossless fork.
10. A unique repaired marker remains visible above the composer after Settings and quit/relaunch.

Keep the final UI on the verified transcript with the marker visible.

## Deliverable

Lead with the truth, not the activity log. Report:

- Root cause of the wrong-tab/wrong-LLM behavior, including the full UI → saved state → process → backend chain.
- Measured performance bottlenecks and their user-visible impact.
- Settings parity matrix: current, missing, stale, misleading, duplicate, and intentionally omitted.
- Backend health and whether CPR was required.
- UI/UX recommendations ranked P0/P1/P2, with the smallest coherent repair slice.
- If authorized and implemented: exact files changed, focused/full tests, rebuilt/installed hash, signing/quarantine, live acceptance, and rollback path.
- Remaining product defects versus model/provider behavior.
- Confirmation of anything staged, committed, pushed, published, deleted, or reconfigured. The expected answer is “nothing” unless Jimmy separately authorized it.
