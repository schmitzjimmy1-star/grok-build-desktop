---
title: GrokBuild frontend and backend parity repair slices
status: ready for scoped execution
audited: 2026-08-02
---

# GrokBuild frontend and backend parity repair slices

> Historical 2026-08-02 execution map. Live chrome is **Run inspector**;
> open work lives in `docs/OUTSTANDING.md`.

## Purpose

This document is the execution map for making GrokBuild's native frontend tell
the truth about what the Grok CLI backend is actually doing. It is intentionally
limited to parity, receipts, lifecycle state, error presentation, and installed
acceptance. It does not authorize a cosmetic redesign, another agent runtime,
provider work, publication, or cleanup of retained user data.

The observed failure is not that Grok failed to do the work. The backend
completed the work, two subagents finished, the parent produced a final answer,
and a Markdown artifact was written. The frontend continued to show three
workers running, no changed files, and a live backend with a
`noBackendBinding` continuity reason. The repair must make one authoritative
event produce one coherent visible state.

## Canonical identity — hard stop before every slice

### Maintained application

| Identity layer | Verified value |
|---|---|
| GitHub repository | `https://github.com/schmitzjimmy1-star/grok-build-desktop` |
| GitHub visibility/default branch | Public / `main` |
| Local worktree | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Maintained remote | `personal` → `https://github.com/schmitzjimmy1-star/grok-build-desktop.git` |
| Preserved upstream | `origin` → `https://github.com/rimusz/grok-build-desktop.git` |
| Local/GitHub `main` at audit | `7ead3abfaa8f3fc5e08c69976b4eb64252b0594b` |
| Installed application | `/Applications/GrokBuild.app` |
| Bundle identifier/version | `com.grokbuild.app` / `0.1.20` |
| Installed source stamp | personal / `main` / `7ead3abfaa8f3fc5e08c69976b4eb64252b0594b` / dirty |
| Installed repository stamp | `https://github.com/schmitzjimmy1-star/grok-build-desktop` |
| Installed/dist executable SHA-256 | `75118092a3f086589ca3a694b3516b5a9826d9d797e951df79066f4e7aab96eb` |

GitHub confirms PRs
[#1](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/1),
[#2](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/2), and
[#3](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/3) are merged.
PR #3 produced the current `main` commit `7ead3ab`.

The installed and `dist` executables match each other, and their bundle receipt
points to the correct worktree/repository/branch/commit. However,
`GrokBuildSourceDirty = true`. The exact installed binary therefore includes
uncommitted local work and cannot be reproduced from GitHub `main` alone. Every
slice must preserve and inventory that dirty work before editing.

### Retired application — do not touch

GitHub also confirms `https://github.com/jimmmy-Jim/Grok-Build-GUI` exists. It
is a private, retired historical repository. Its old local line is
`/Users/jimmyschmitz/Documents/Grok Builf`, and its product was named
`Grok Build.app`. It is not the installed `/Applications/GrokBuild.app` and is
not an implementation target for any slice below.

### Stop conditions

Stop before mutation if any of these are false:

1. `pwd` is the canonical worktree above.
2. `personal` is Jimmy's maintained repository and `origin` remains upstream.
3. The active branch/HEAD is reconciled with `personal/main`.
4. `/Applications/GrokBuild.app` stamps the personal repository and
   `com.grokbuild.app`.
5. Existing dirty files have been recorded and remain present.
6. The retired GUI has not been built, copied, opened as a source root, or used
   for implementation evidence.

## Live parity fixture that owns acceptance

The 2026-08-02 Chicago evidence run is the first real fixture. Its backend
session is:

`019fc389-b16a-7053-b79e-33017125294b`

Durable backend truth:

| Receipt | Backend truth |
|---|---|
| Parent turn | Completed after about 306 seconds |
| Subagents | Exactly 2 spawned; exactly 2 completed |
| Education worker | Completed; about 149 seconds; 45 tool calls |
| Geography worker | Completed; about 173 seconds; 35 tool calls |
| Tool failures | 5 `web_fetch` calls failed; the turn continued through alternate source paths |
| Artifact | `/Users/jimmyschmitz/Documents/Grok Git/evidence-packet-1893-columbian-exposition.md` written successfully |
| Usage | 1,276,441 total tokens; 15 model calls |
| Parent outcome | `turn_completed`, stop reason `end_turn` |

Incorrect visible state after completion:

- `3 workers running`
- `No file changes in review`
- two named worker lanes plus one unnamed `Subagent`
- live backend suffix `7125294b` alongside continuity reason
  `noBackendBinding`
- `5 failed` without a settled/run-level explanation
- reasoning chunks concatenated into an unreadable paragraph stream

The raw fixture must be copied into a secret-safe deterministic test fixture.
Do not make tests read the mutable live `~/.grok` tree.

## Ownership rule

Grok CLI remains the runtime and event authority. GrokBuild may normalize,
correlate, persist minimal public receipts, and render them. It must not invent
a second worker scheduler, infer success from assistant prose, or silently
rewrite backend history. When the backend does not emit enough evidence, the UI
must say `Unknown` or `Not reported`, not manufacture certainty.

## Three-sentence handoff for the next session

Work only in `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`, re-run `CANONICAL_WORKTREE.md` preflight, and preserve every existing dirty path before editing. Begin with Slice 0 by producing the trimmed, secret-safe activity-parity fixture from backend session `019fc389-b16a-7053-b79e-33017125294b`; do not change runtime behavior until the fixture deterministically proves two spawned workers, two completed workers, five failed tool calls, one written artifact, and one completed parent turn. Stop after Slice 0 tests and receipts are complete, then leave the exact three-sentence Slice 0 handoff below for the session authorized to begin Slice 1.

## Slice 0 — freeze identity and the real event fixture

### Objective

Create a reproducible, secret-safe baseline before changing behavior.

### Changes

- Preserve the existing dirty worktree exactly.
- Add a trimmed fixture containing the parent session updates required for:
  `spawn_subagent`, `subagent_spawned`, `subagent_finished`,
  `get_command_or_subagent_output`, failed and successful tool updates,
  artifact write, plan completion, usage, and `turn_completed`.
- Retain IDs, statuses, timestamps, counts, paths, and redacted errors.
- Remove source bodies, hidden reasoning, credentials, auth prefixes, and
  oversized subagent result bodies from the fixture.
- Record the pre-slice installed bundle hash and dirty-source inventory.

### Files

- `Tests/GrokBuildTests/Fixtures/ActivityParity/`
- `Tests/GrokBuildTests/ActivityParityFixtureTests.swift`
- `docs/FRONTEND_BACKEND_PARITY_REPAIR_SLICES_2026-08-02.md`
- `docs/UI_ACCEPTANCE_MATRIX.md`

### Gate

The fixture proves 2 spawned, 2 completed, 5 failed tool calls, 1 written
artifact, 1 completed parent turn, and the exact usage receipt without reading
live user state.

### Slice 0 receipt — 2026-08-02

Canonical preflight passed before editing: the worktree, local `main`,
`personal/main`, and the installed source stamp all resolved to
`7ead3abfaa8f3fc5e08c69976b4eb64252b0594b`; the installed bundle identifier is
`com.grokbuild.app`, and the `dist`/installed executables both hash to
`75118092a3f086589ca3a694b3516b5a9826d9d797e951df79066f4e7aab96eb`.
The 19-path pre-edit dirty baseline was copied without checkout, stash, or
cleanup to `.git/codex-preservation/slice0-20260802-preedit/dirty-worktree.tgz`;
the archive contains all 19 paths and hashes to
`047f378b57bf41c6056490332845364b89cb8660029cfd068a0bbb7127a8f99f`.

```text
27be0afd1a9603a6931aa37fc07c4e2d052f32c8bdafef06179b3b6453b5b31e  ARCHITECTURE.md
13b953a257da35bb59f89c1be0ed4c05723661ee34d4121a505ec691f0a6738c  GrokBuild/ContentView.swift
32bd0e66545d89213d8be4d893973d3842b7dc3d20b5b184ca417032d00f9179  GrokBuild/Services/BackgroundTaskStore.swift
dde9832603d01c44788cbdaff3f1d1ceb4ced0bd9af9d426298d8167b2e4c2ae  GrokBuild/Services/ChatStore.swift
cc6931fbc49e3d61da72be5a295791cfd62b0404cd05a214473efd32f29cee0d  GrokBuild/Services/GrokProcess.swift
dbc143582ed6464610031b4014bd09cbfd9b87b1b56f778125d75f86cb902436  GrokBuild/Views/ChatView.swift
01de31fd439f69e31fbe657ef5128a10f2b0651db85c6457a30e851c6dea1cde  README.md
71501a0701fec8b7d297839fab0e3b9c6e4c3a9e9f062a6b04f5ffe369443afd  Tests/GrokBuildTests/ACPClientContractTests.swift
c193f916a93a0bc552f66b076c5bb9aa5d055e4aca01380ecd95a5d5151cfcbb  Tests/GrokBuildTests/BackgroundTaskTests.swift
d9c634e3f4b24ae868f4831fa714daf67a357832a936fbdb6a82f56337e31d52  Tests/GrokBuildTests/LifecycleAndSubprocessTests.swift
978a39fa440f90ce1d4270a925de9866640549a03b25ad6117ae6e8ba7a09f99  GrokBuild/Models/TranscriptTextPresentation.swift
82f6692ef66840247ac5573fa80f7fa8d075c30d681951e041a324903b291513  GrokBuild/Services/MCPReadinessPolicy.swift
9e601fd43ff5dc968b3073ea4f5c6291d85019b012d560bbb4bddb479f540295  GrokBuild/Views/ActivitySidebar.swift
5979ca1db14dabcd2c469a0e72e920afaaa44972d0f755f29d44c49791da4182  Tests/GrokBuildTests/ActivitySidebarTests.swift
2daa03fd574914c9eab6188976a0257298e5d3804b8a8e9cbbd0cb5e8cc30818  Tests/GrokBuildTests/MCPReadinessTests.swift
fc144d76fd4eccc5af3c9abf428826c6ffa739c181c8207379443016af9785bc  docs/AGENTIC_WORKBENCH_MCP_MULTIPHASE_HANDOFF.md
e5e28926e3611328874d06c33e9533ca7533626175d04d950b19e889cfe35e33  docs/AGENTIC_WORKBENCH_PHASE0_RECEIPT_2026-08-02.md
4e970915ac41387ed38d96f2c8cf3ae3e77d894c3f3f3cecc0d1455f20fa5855  docs/FRONTEND_BACKEND_PARITY_REPAIR_SLICES_2026-08-02.md
1947a5d6eb5db20724111c32e75ae81e43f245cb37b985b8440b61c58bfd3845  docs/TOOL_USE_AND_MULTI_TURN_CONTRACT.md
```

The 100-envelope source `updates.jsonl` for backend
`019fc389-b16a-7053-b79e-33017125294b` hashed to
`f72405dc8008a5034b1462ba5ab22e216ffa7f25cb4d1e00d2f71523f6834c09`
at extraction. The repository test resource is a 30-envelope redacted subset:
`chicago-evidence-run-redacted.jsonl` hashes to
`ced3ea7010daacab967858912d8b01d6c21245175b332ec26ae4aafb3498c801`,
and its manifest hashes to
`62ea97929885bc5987d3ed8981605ec3bb741a6ff386a4f5023c15ca1e9b623b`.
It retains event, session, prompt, child, and tool-call IDs; statuses and
timestamps; worker durations/counts; the artifact path; redacted error classes;
and the exact 1,276,441-token/15-model-call receipt, while excluding live-state
paths, credentials/auth prefixes, reasoning text, source bodies, and large
worker results.

Focused `ActivityParityFixtureTests` passed 2/2, and the canonical full
`make test` passed 508 tests with 0 failures in 18.872 seconds. `git diff
--check` passed. No runtime source, app bundle, installed app, provider,
session, configuration, or user artifact was changed by Slice 0.

### Three-sentence handoff to Slice 1

Slice 0 is complete only when the canonical identity and dirty baseline are preserved and the redacted fixture proves the exact backend counts without reading live `~/.grok` state. In the next session, implement Slice 1 only by routing typed `subagent_spawned` and `subagent_finished` events through `GrokProcess` into `ChatStore` with backend, process-generation, and child identity intact. Do not alter worker presentation yet; finish with focused ACP/lifecycle fixture tests proving both terminal events arrive once and stale-generation events cannot mutate the active session.

## Slice 1 — normalize ACP run and subagent lifecycle events

### Objective

Ensure every authoritative backend lifecycle event reaches `ChatStore` with
its identity intact.

### Current defect

`GrokProcess.routeUpdate` handles `tool_call` and `tool_call_update` but drops
`subagent_spawned` and `subagent_finished` through the default branch. The
frontend therefore sees worker creation tools but never receives authoritative
worker completion.

### Changes

- Add typed ACP events for subagent spawn and terminal lifecycle updates.
- Preserve parent backend ID, child session/subagent ID, status, duration,
  turns, tool-call count, token count, and redacted error.
- Bind events to the current backend/session and process generation.
- Reject late events from a replaced process generation.
- Keep result bodies out of the worker receipt; retain only a safe preview or
  reference if the UI needs it.

### Files

- `GrokBuild/Services/GrokProcess.swift`
- `GrokBuild/Services/ChatStore.swift`
- `Tests/GrokBuildTests/ACPClientContractTests.swift`
- `Tests/GrokBuildTests/LifecycleAndSubprocessTests.swift`
- new focused `ActivityParityFixtureTests.swift`

### Gate

The fixture emits two terminal worker events into `ChatStore`; neither is
dropped, duplicated, or attached to the wrong session.

### Slice 1 receipt — 2026-08-02

`GrokProcess` now normalizes `_x.ai/session/update` `subagent_spawned` and
`subagent_finished` updates into typed events carrying the local tab, parent
backend, captured process generation, backend event ID, and child identity.
Terminal receipts preserve status, duration, turns, tool-call count, token
count, and a bounded redacted error while excluding worker result bodies.
Every stdout reader is generation-bound at launch, and `ChatStore` independently
requires an exact tab/backend/active-generation match before exact-once lifecycle
deduplication and storage. Worker presentation was not changed.

The redacted Chicago fixture passed through a live fake ACP process into
`ChatStore`: two spawned events and the two authoritative terminal events arrived
once each; replaying both terminal envelopes did not duplicate them, and injecting
the same envelopes with the prior generation produced no mutation. Focused ACP,
fixture, and session-lifecycle coverage passed **38 tests, 0 failures**. The full
`make test` gate passed **512 tests, 0 failures** in 19.468 seconds, and `git diff
--check` passed.

The signed release-development bundle built and launched from canonical
`.build/GrokBuild.app`. Fresh Computer Use inspection showed the restored evidence
packet, empty composer, continuity guard, and Activity sidebar coherently; the
drawer reported no active workers/subagents and no presentation changes were
introduced. No provider prompt, billable call, user-file write, installed-app
replacement, publication, or Slice 2 worker correlation occurred.

### Three-sentence handoff to Slice 2

Slice 1 is complete only when both authoritative worker terminal events reach `ChatStore` exactly once and the fixture remains secret-safe. In the next session, implement Slice 2 only by making `spawn_subagent` the sole worker-creation path, correlating spawn-call IDs with child IDs, and treating wait/kill calls as updates to existing work. Stop after tests prove exactly two completed workers, no unnamed third worker, and truthful `unknown` or `orphaned` handling when terminal evidence is absent.

## Slice 2 — correlate workers without creating ghosts

### Objective

Render exactly the workers the backend created and their real terminal states.

### Current defect

`BackgroundToolParsing.activityKind` classifies any tool name containing
`subagent` as a subagent. This turns `get_command_or_subagent_output` into a
third unnamed worker. Spawn tool-call IDs and backend child IDs are also not
reconciled into one durable identity.

### Changes

- Only `spawn_subagent` creates a worker activity.
- `subagent_spawned` binds the spawn call ID to the child/subagent ID.
- `subagent_finished` updates that existing worker to `completed`, `failed`, or
  `cancelled`.
- `get_command_or_subagent_output` becomes a wait/collection receipt attached
  to existing workers; it never creates one.
- `kill_command_or_subagent` updates the targeted worker or command.
- Add explicit `orphaned` and `unknown` presentation for late/missing terminal
  evidence.
- At parent `turn_completed`, do not blindly declare workers successful. Any
  still-active worker becomes explicitly unresolved (`Unknown` without child
  identity or `Orphaned` with a known child) unless a terminal receipt arrives
  within the bounded event-drain barrier.

### Files

- `GrokBuild/Services/BackgroundTaskStore.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Views/ActivitySidebar.swift`
- `Tests/GrokBuildTests/BackgroundTaskTests.swift`
- `Tests/GrokBuildTests/ActivitySidebarTests.swift`
- `Tests/GrokBuildTests/ActivityParityFixtureTests.swift`

### Gate

The live fixture renders exactly two workers, both completed, with their real
durations/tool counts. The unnamed third worker is impossible in tests.

### Slice 2 receipt — 2026-08-02

`BackgroundTaskTracker` now admits a worker only from the exact
`spawn_subagent` tool name. It keeps the spawn tool-call ID as the stable row
identity, binds the backend child ID from the spawn receipt, and applies
duration, turn, tool-count, token-count, status, and bounded error fields only
from the typed `subagent_finished` receipt. `get_command_or_subagent_output`
records a collection receipt on matching existing workers; it cannot create a
row. `kill_command_or_subagent` updates only matching existing activities.

At the ordered parent `turn_completed` barrier, active workers without terminal
evidence become explicit `Unknown` when child identity is absent or `Orphaned`
when the child is known. A late same-generation terminal receipt can settle an
orphaned row; an unmatched lifecycle receipt is retained for later correlation
and never becomes a ghost worker. The Activity drawer now renders all correlated
worker rows, including terminal metadata and truthful unresolved states, rather
than only active workers.

The redacted Chicago fixture was routed through the live fake ACP process and
`ChatStore`: exactly two worker rows resolved, both `completed`, with child IDs,
spawn-call IDs, durations `149254`/`173148` ms, tool counts `45`/`35`, and one
wait receipt each. Focused worker/sidebar/fixture coverage passed **19 tests, 0
failures**; the full `make test` gate passed **517 tests, 0 failures** in
19.646 seconds, and `git diff --check` passed.

The canonical installed app was rebuilt and installed from the dirty
`codex/activity-parity-slice-0` worktree at source commit
`a9bc1845ec07b40301874f66cfb7ac6a84e15965`; the personal repository stamp and
`com.grokbuild.app` identity match, and `dist`/installed executable SHA-256 is
`8b82415e6d9bc4d52ac947df0c0423dec1d6ca82906e267897ba9a51b41f64de`. Deep
codesign verification passed. After quitting the pre-install process and
relaunching, Computer Use showed the refreshed `Subagents` drawer, preserved
the restored transcript and empty composer, and reported no workers for the
existing restored session. The populated worker proof remained fixture-only to
avoid a provider prompt or billable call. Rollback: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-2-20260802-1403.app`.

### Three-sentence handoff to Slice 3

Slice 2 is complete only when the live fixture resolves to two terminal workers with no ghost activity and no success inferred from parent prose. In the next session, implement Slice 3 only by separating authoritative run artifacts from Git review state and triggering a bounded Git refresh after successful writes and turn settlement. Stop after tests show the evidence packet under `Run artifacts`, Git status under `Files in review`, and pre-existing dirty files kept distinct from the current run.

## Slice 3 — separate run artifacts from Git review state

### Objective

Show what the run created while keeping Git review truth honest.

### Current defect

`ContentView` refreshes project diffs during session changes and explicit diff
actions, not after a write tool or settled turn. The evidence packet exists and
Git reports it as untracked, while the drawer says no changes. Also, `Files in
review` is not the same thing as `Artifacts created this run`.

### Changes

- Capture safe artifact paths from authoritative write/edit tool receipts.
- Add a `Run artifacts` section showing created/updated artifact paths and
  terminal write status.
- Keep `Files in review` driven by `GitService.changedFiles`; do not claim every
  filesystem write is a review diff.
- Trigger one debounced Git refresh after a successful write/edit and after
  `turn_completed`; do not add a permanent polling watcher.
- Show out-of-workspace artifacts explicitly as external artifacts rather than
  dropping them.
- Preserve paths as text and offer Finder/reveal only through an explicit user
  action.

### Files

- `GrokBuild/ContentView.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Views/ActivitySidebar.swift`
- `GrokBuild/Services/GitService.swift` only if existing status output cannot
  represent untracked paths correctly
- `Tests/GrokBuildTests/ActivitySidebarTests.swift`
- new artifact/Git refresh contract tests

### Gate

After the fixture's write event, the drawer shows the evidence packet as a run
artifact. After the bounded refresh, Git review state agrees with `git status`
without conflating pre-existing dirty files with this run's output.

### Slice 3 receipt — 2026-08-02

`ChatStore` now retains a candidate artifact path only from the exact write/edit
tool call, promotes it into `runArtifacts` only after that call reports a
successful terminal status, and clears current-run evidence at the next turn
boundary. Relative paths resolve within the active workspace; paths outside it
remain visible and are labeled `External artifact`. The Activity drawer renders
this authority under `Run artifacts` before the separate `Files in review`
section, and Finder reveal remains an explicit button action.

Git review state remains owned by `GitService.changedFiles`. A successful
write/edit and the ordered `turn_completed` barrier each increment an
event-driven refresh revision; `ContentView` cancels/coalesces nearby requests
through one 250 ms task and validates the active store/workspace before reading
Git. No timer, permanent watcher, filesystem polling loop, or invented write
evidence was added. The deterministic temp-repository contract proves a
pre-existing tracked modification and the current untracked output both remain
in Git review while only the exact current write appears in run artifacts.

Focused artifact/fixture/presentation coverage passed **12 tests, 0 failures**;
the full `make test` gate passed **519 tests, 0 failures** in 19.862 seconds, and
`git diff --check` passed. The dirty canonical branch and every earlier path
remain preserved; no commit, push, PR, publication, cleanup, or provider call
occurred.

The dirty canonical app was rebuilt and installed from
`codex/activity-parity-slice-0` at
`a9bc1845ec07b40301874f66cfb7ac6a84e15965`. Installed and `dist` executable
SHA-256 both equal
`9929c7c8c3e45046a9740ffea8c03b699b011a3d21c05a8cfef7dc19671b22bf`, and
deep/strict signing passed. After an explicit quit/relaunch, Computer Use showed
`Run artifacts — No successful writes reported for this run` separately before
`Files in review — No changed files observed yet`, with the restored transcript,
empty composer, disabled Send, no workers, and no owned child process. Populated
artifact/Git proof remains deterministic-fixture-only to preserve the no-provider
boundary. Three settled one-second samples were 0.0% CPU at 114,144 KB RSS.
Rollback remains
`/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-2-final-preinstall-20260802-1411.app`.

### Three-sentence handoff to Slice 4

Slice 3 is complete only when run artifacts and Git review files are separately truthful and no filesystem polling or invented write evidence was added. In the next session, implement Slice 4 only by reconciling fresh, restored, verified, forked, missing, and divergent backend bindings through the existing continuity authority. Stop after deterministic tests prove a non-empty live backend can never coexist with `noBackendBinding` and a fresh backend is labeled bound rather than falsely verified.

## Slice 4 — reconcile live backend and continuity receipts

### Objective

Make the continuity card describe the current relationship between local
messages and the actual backend.

### Current defect

After `process.sessionId` becomes authoritative, `savedGrokSessionID` and
`continuityBackendID` update, but a prior `.localOnly / noBackendBinding`
receipt can remain. The UI then says both `Live backend …` and
`noBackendBinding`.

### Changes

- Add an explicit fresh-backend binding transition after successful
  `session/new`.
- Distinguish:
  - local-only, no backend created;
  - fresh backend bound, no prior history to compare;
  - restored backend verifying;
  - verified prefix/full match;
  - recovery fork;
  - missing/divergent/blocked.
- Update message counts after settlement from the same normalized authority
  used by continuity verification.
- Never label a fresh backend `verified` against nonexistent prior history;
  label it `New backend bound` or the equivalent truthful state.
- Persist the new binding receipt with tab ID, backend ID, process generation,
  and verification reason.

### Files

- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Services/SessionTranscriptRecovery.swift`
- `GrokBuild/Services/SessionLayoutStore.swift` if the receipt schema changes
- `GrokBuild/Views/ActivitySidebar.swift`
- `Tests/GrokBuildTests/SessionLifecycleV3Tests.swift`
- `Tests/GrokBuildTests/ActivityParityFixtureTests.swift`

### Gate

No UI state may contain a non-empty live backend ID and the reason
`noBackendBinding`. Fresh, restored, forked, and blocked cases all have separate
deterministic tests.

### Slice 4 receipt — 2026-08-02

`SessionContinuityReceipt` now distinguishes `backendBound / freshBackendBound`
from verified history and persists the local tab UUID, backend ID, and process
generation alongside the verification reason. The single post-ACP binding
boundary stamps fresh, restored, and recovery-fork receipts; re-selecting an
LRU-retained live process adopts that exact binding instead of restoring a stale
layout receipt. The ordered `turn_completed` barrier refreshes local/backend
counts through `SessionTranscriptRecovery`'s root-conversation normalization,
and the existing Process receipt disclosure exposes the continuity headline,
redacted backend, generation, counts, prefix, and reason without adding new
permanent chrome.

Deterministic fake-ACP coverage proves a fresh backend is `New backend bound`,
never verified, survives same-tab rebinding without `noBackendBinding`, updates
its normalized counts after settlement, and records a generation-bound explicit
fresh-session fork. Restored exact history remains verified across a coalesced
runtime reconnect; missing and divergent histories remain blocked; Continue as
New persists its predecessor intent without starting a backend; authenticated
v3 round-trips the new identity fields while legacy receipts decode them as
absent. Focused continuity/persistence coverage passed **56 tests, 0 failures**;
the final full `make test` gate passed **521 tests, 0 failures** in 20.741
seconds, and `git diff --check` passed.

Before editing, all 20 dirty paths were preserved at
`.git/codex-preservation/slice4-20260802-preedit/dirty-worktree.tgz` with SHA-256
`26569de2eff644fed1b705baf067489540564da68cacf842fc7315dd6926701b`.
The dirty canonical app was rebuilt and installed from
`codex/activity-parity-slice-0` at
`a9bc1845ec07b40301874f66cfb7ac6a84e15965`; the personal repository stamp and
`com.grokbuild.app` identity match, deep/strict signing passes, and the final
`dist`/installed executable SHA-256 is
`a57a453da905b18d003a4024d81aa31fd73891cd3d4e5445d1e63ad929c44e73`.
After an exact quit/relaunch, Computer Use verified the preserved transcript,
empty composer, disabled Send, a fresh local-only tab whose Process receipt says
`Backend none · generation none · reason noBackendBinding`, and no contradictory
live backend. No provider prompt, billable call, settings/config change, commit,
push, PR, publication, cleanup, or Slice 5 tool-failure work occurred. Three
settled one-second samples were 0.0% CPU at 122,336–122,352 KB RSS with no owned
child process. Rollback:
`/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-4-20260802-1453.app`.

### Three-sentence handoff to Slice 5

Slice 4 is complete only when every continuity label agrees with the current backend ID, provenance, message counts, and verification reason across restore and relaunch. In the next session, implement Slice 5 only by normalizing tool terminal states and presenting individual failures alongside the settled parent-turn outcome without inventing recovery. Stop after the fixture shows five failed fetches with safe details, a completed parent turn, and `Recovered` only where an explicit correlation receipt proves it.

## Slice 5 — settle tool failures without pretending they succeeded

### Objective

Make error state actionable and distinguish individual failure from overall run
outcome.

### Current defect

The transcript summary says `5 failed` even though the parent turn completed
and used alternate source paths. Failed tool details are useful, but successful
tool details sometimes expose raw JSON while the run-level summary supplies no
resolution context.

### Changes

- Normalize terminal tool status to `succeeded`, `failed`, `cancelled`,
  `stale`, or `unknown`.
- Preserve the non-secret backend error message and tool target.
- Show both counts: `5 tool calls failed` and `Turn completed`.
- Use `Recovered` only when an explicit retry/correlation receipt proves it;
  never infer recovery merely because a final answer exists.
- Correlate exact retries when backend call metadata supplies a parent/retry ID.
- Render known payloads as concise fields; put raw secret-safe JSON behind a
  diagnostic disclosure, not in the normal detail row.
- Surface unresolved failures in the final Run Summary with their next action.

### Files

- `GrokBuild/Services/GrokProcess.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Views/ChatView.swift`
- `GrokBuild/Views/GrokChatChrome.swift`
- `GrokBuild/Services/GrokProcess.swift` (`ToolCall` model and ACP parser owner)
- `Tests/GrokBuildTests/ACPClientContractTests.swift`
- new tool settlement/presentation tests

### Gate

The fixture displays five failed fetches, the exact safe error on disclosure,
and a completed parent turn. It does not call the failures recovered without a
correlation receipt and does not imply the entire run failed.

### Slice 5 receipt — 2026-08-02

`ToolCallTerminalStatus` now normalizes backend terminal evidence to
`succeeded`, `failed`, `cancelled`, `stale`, or `unknown`; `ChatStore` settles
each observed call at the ordered parent `turn_completed` barrier and records
the separate `Turn completed` outcome. The native tool group now shows the
exact count (`5 tool calls failed`) beside a final **Run summary** and a safe
next step; each failed `web_fetch` keeps its redacted public target and error in
the normal disclosure, with bounded redacted JSON only under **Diagnostic
payload**. A failed call receives `Failed · Recovered` only when a distinct
successful call carries an explicit backend `retryOf`/parent-call correlation;
the fixture carries no such metadata, so all five remain failed.

Focused ACP plus activity-parity coverage passed **36 tests, 0 failures**; the
final `make test` gate passed **524 tests, 0 failures**, and
`git diff --check` passed. The deterministic bundled fixture still proves two
completed workers, one completed write, five failed fetches with safe details,
and one completed parent turn, while explicit parser and settlement fixtures
cover status normalization plus the positive and negative retry-correlation
cases.

The dirty canonical app was rebuilt and installed from
`codex/activity-parity-slice-0` at
`a9bc1845ec07b40301874f66cfb7ac6a84e15965`; its personal source stamp remains
explicitly dirty, and the final `dist`/installed executable SHA-256 is
`db44052d0969c11ea4d9426acda177323849a6115a65b7a1dc59b6892e72b3dc` with
deep/strict signing verified. Exact quit/relaunch Computer Use acceptance
preserved the existing transcript, empty disabled composer, local-only
continuity (`Backend none`), no active session process, and the Activity drawer
without any invented tool outcome; after settling, the app was 0.0% CPU at
86,912 KB RSS with no owned child. No provider, catalog fetch, credential or
configuration change, cleanup, commit, push, PR, merge, or publication was
performed. Existing rollback evidence remains untouched; new signed rollback
bundles are
`/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-5-20260802-1507.app` and
`/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-5-run-summary-20260802-1511.app`.

### Three-sentence handoff to Slice 6

Slice 5 is complete only when failed, retried, cancelled, stale, and successful tool calls remain individually truthful while the run-level outcome is separately visible. In the next session, implement Slice 6 only as presentation-safe reasoning-summary formatting that preserves backend-emitted text, adds readable boundaries, and never stores or exports hidden chain-of-thought. Stop after fixture and accessibility tests prove every summary stage appears once, in order, with bounded expansion and no fused chunk boundaries.

## Slice 6 — make reasoning summaries readable and bounded

### Objective

Present the backend-provided reasoning summary as useful progress, not a fused
wall of text.

### Current defect

Distinct `agent_thought_chunk` updates are appended directly. The installed UI
shows boundaries such as `geograp...I'll use` and
`validation.web_fetch failed`, making separate stages look like corrupted prose.

### Changes

- Preserve explicit whitespace from each chunk.
- When distinct thought updates have no boundary, insert a presentation-only
  paragraph boundary; do not alter stored/backend text.
- Keep reasoning collapsed by default after completion.
- Render a small sequence of public summary stages: plan, current action,
  fallback/error, synthesis, completion.
- Do not persist or export hidden chain-of-thought. Only render the summary text
  the backend intentionally emitted through ACP.
- Bound extremely long summaries and provide selectable expansion.

### Files

- `GrokBuild/Models/TranscriptTextPresentation.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Views/GrokChatChrome.swift`
- `Tests/GrokBuildTests/ActivitySidebarTests.swift` or a dedicated transcript
  presentation suite

### Gate

The fixture's thought chunks render as separate readable stages with no missing
or duplicated text, and accessibility reads the stages in order.

### Slice 6 receipt — 2026-08-02

`ChatStore` now retains only the ordered, ephemeral public summary chunks that
ACP intentionally emits for the active turn. `ReasoningSummaryPresentation`
preserves explicit whitespace, joins token-sized deltas only when whitespace or
punctuation proves continuation, and inserts a presentation-only stage boundary
between otherwise fused word-like updates. Compact display is limited to five
stages/4,000 characters; selectable expansion is limited to twenty
stages/12,000 characters. Each rendered stage has an ordered accessibility
label/value, settlement collapses the disclosure, and the raw public summary
chunks remain absent from `Message`, layout, transcript, recovery, and export
state. GrokBuild does not request, reconstruct, retain, or export hidden
chain-of-thought.

The secret-safe five-update fixture renders Plan, Current action, Fallback or
error, Synthesis, and Completion exactly once and in order, retains every
source string byte-for-byte after transport normalization, and adds the missing
blank-line boundary only in the presentation projection. A second regression
fixture covers the live Grok shape: fourteen token-sized deltas such as `The`,
` user`, punctuation, and newline tokens become one readable stage rather than
fourteen one-word rows. Focused `ReasoningSummaryPresentationTests` passed
**8 tests, 0 failures**; the final full `make test` passed **532 tests, 0
failures** in 21.423 seconds, and `git diff --check` passed. The fixture,
presentation owner, and focused test SHA-256 values are respectively
`2c72d502ee071359348781575458c8775ea0a6014728bd630359559c845bf964`,
`b1ba6d00a9cf12c896b71fead34b5c86c215de2f487cd350520b49ec2c864124`,
and `7035f2b3a71f29e8929c32accc73bbce98e63f8f171c0fa2f1c538f1299d065e`.

Before editing, all 24 dirty paths were preserved at
`.git/codex-preservation/slice6-20260802-preedit/dirty-worktree.tgz`, SHA-256
`8dc43332445a68dba472096f3b99a553672ee5782ea308addb9ec72af0a0d6e4`;
no checkout, stash, cleanup, commit, push, PR, merge, or publication occurred.
The final installed and `dist` executable SHA-256 is
`a8f5a462a6e4f39e902679210c824f71a7f2877ac9bb187eebac06c8860a3eec`.
Both bundles pass deep/strict signing, quarantine is absent, and the installed
App pane visibly reports canonical personal branch
`codex/activity-parity-slice-0` at dirty source commit
`a9bc1845ec07b40301874f66cfb7ac6a84e15965`. Signed recoverable Slice 6
predecessors are
`/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-6-20260802-1525.app`
(executable SHA-256
`db44052d0969c11ea4d9426acda177323849a6115a65b7a1dc59b6892e72b3dc`)
and
`/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-6-token-grouping-20260802-1537.app`
(executable SHA-256
`2621b19f27b442ed249e360729488c2a67c6327c4861a77a2a9d297e8e1c8298`);
the two signed Slice 5 bundles and older rollback evidence remain untouched.

Installed Computer Use acceptance used four fresh one-turn sessions and records
every call, including the live failure that improved the implementation:

| Test | Model / backend | Conservative tracked tokens | Visible result | Settled receipt |
|---|---|---:|---|---|
| Initial compact-summary check | `gpt-5.6-terra` / `019fc429-e8a7-7b91-949e-d5b6cec46022` | 10,996 (10,953 prompt + 28 completion + 15 reasoning; 0 cached) | `GB_SLICE6_TERRA_OK`; one ordered accessible summary stage | Pass; live model confirmed, generation 1, completed and collapsed |
| Token-delta discovery | `grok-4.5` / `019fc42b-c8a9-7032-8284-0ede8a2c87f9` | 15,128 (14,871 prompt + 153 completion + 104 reasoning; 128 cached) | `GB_SLICE6_GROK_OK`; thirteen token-sized one-word rows | **Failed presentation acceptance**; caused the explicit-boundary grouping repair |
| Corrected token grouping | `grok-4.5` / `019fc434-34fa-7f33-9c0b-81bbbbecfaa9` | 15,756 (14,873 prompt + 463 completion + 420 reasoning; 2,560 cached) | `GB_SLICE6_GROK_FIXED_OK`; the token stream appears once as one readable accessible stage | Pass; live model confirmed, generation 1, backend suffix `bbecfaa9`, completed and collapsed |
| Corrected cross-provider check | `gpt-5.6-terra` / `019fc435-413e-70d0-a6eb-d42583fd1d4d` | 10,979 (10,941 prompt + 26 completion + 12 reasoning; 7,521 cached) | `GB_SLICE6_TERRA_FIXED_OK`; one ordered accessible stage | Pass; live model confirmed, generation 1, backend suffix `83fd1d4d`, completed and collapsed |

Slice 6 used **52,859 / 300,000** authorized tracked provider tokens across four
model calls; cached prompt tokens observed separately were 10,209. Exact
quit/relaunch restored the user/final transcript but no thinking disclosure,
proving the public summary projection was not persisted. Startup catalog work
then settled to three consecutive 0.0% CPU samples at 112,752–112,816 KB RSS
with zero owned child processes.

At the user's follow-up request, Models settings now shows the non-secret
`Shows thinking blocks` sidecar hint enabled for `gpt-5.6-terra`,
`gpt-5.6-luna`, and `deepseek-deepseek-v4-flash-0731`; Terra was already on,
while Luna and DeepSeek changed from off to on. OpenAI and OpenRouter catalog
refreshes reported 125 and 337 available models, respectively, without a
completion call. No credential was read, replaced, or exposed, and
`~/.grok/config.toml` remains owner-only mode `0600`, 2,190 bytes, byte-for-byte
unchanged at SHA-256
`d2005a9fde0b8ed79753437fd8aa9124b6b0f58c5ab18acfeb010bfb90bc9034`;
its private rollback copy is
`/Users/jimmyschmitz/.Trash/grok-config-pre-slice6-thinking-20260802-1532.toml`.
The sidecar rollback is explicit: keep Terra on and set only Luna and DeepSeek
back off. No other model/provider/configuration field changed.

### Three-sentence handoff to Slice 7

Slice 6 is complete only when backend-provided reasoning summaries are readable, bounded, accessible, and unchanged at the durable source layer. In the next session, implement Slice 7 only by deriving one `RunEvidenceSnapshot` from the settled lifecycle, worker, tool, artifact, Git, continuity, process, and usage authorities already built. Stop after tests produce one snapshot reporting two completed workers, five failed tools, one artifact, fifteen model calls, 1,276,441 tokens, and zero active workers while SwiftUI contains no competing lifecycle logic.

## Slice 7 — build one run-evidence projection for the sidebar

### Objective

Give the user a compact answer to: what is happening, who owns it, what failed,
what changed, and what remains?

### Changes

- Add a single deterministic `RunEvidenceSnapshot` projection owned by
  `ChatStore`, derived from existing ACP/session/Git state.
- Include:
  - goal or user request summary;
  - ordered plan and current step;
  - workers and terminal outcomes;
  - tool success/failure counts;
  - run artifacts and Git review files as separate lists;
  - live model/process/MCP receipt;
  - usage totals from `turn_completed`;
  - outcome, unresolved errors, and next action;
  - restored/local/live provenance.
- The SwiftUI drawer renders the projection and owns no competing lifecycle
  logic.
- Bind every snapshot to tab ID, backend ID, process generation, turn/request
  ID, and settlement state.
- Reset or archive the prior snapshot when a new turn begins; never blend two
  runs into one worker count.

### Files

- new `GrokBuild/Models/RunEvidenceSnapshot.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Views/ActivitySidebar.swift`
- `GrokBuild/Views/ChatView.swift`
- `GrokBuild/ContentView.swift`
- new `RunEvidenceSnapshotTests.swift`
- `Tests/GrokBuildTests/ActivityParityFixtureTests.swift`

### Gate

One snapshot generated from the live fixture reports: 2/2 workers completed,
5 failed tools, 1 completed turn, 1 artifact, 15 model calls, 1,276,441 tokens,
and zero active workers. SwiftUI only formats this result.

### Slice 7 receipt — 2026-08-02

`RunEvidenceSnapshot` is an ephemeral, settled-only `ChatStore` projection bound
to the exact local tab, workspace, backend, process generation, and ACP
`prompt_id`. It derives the final plan, correlated worker receipts, settled tool
counts, run artifacts, process/model/MCP receipt, continuity provenance, final
usage, outcome, errors, and next action from the existing authorities. It is
cleared at the next turn boundary and is not stored in the transcript, layout,
or diagnostics. `ContentView` retains ownership of the bounded Git query and
may only attach its result to a matching snapshot; it cannot create or settle a
run. `ActivitySidebar` receives the snapshot value and formats it without a
`ChatStore` lifecycle, worker, tool, or continuity branch.

The redacted Chicago fixture now produces one settled snapshot with **two
completed workers**, **zero active workers**, **five failed tools**, **one
artifact**, **one completed parent turn**, **15 model calls**, and
**1,276,441 total tokens**. The full `make test` suite passed **534 tests, 0
failures**. Rebuilding with `make run` and opening the native Activity drawer
without sending a prompt exposed the accessible empty settled state, **No
settled run evidence**. Installed acceptance remains the separate Slice 9 gate.

### Three-sentence handoff to Slice 8

Slice 7 is complete only when the Activity sidebar renders one deterministic run-evidence projection bound to the exact tab, backend, process generation, turn, and request. In the next session, implement Slice 8 only within the stated ownership boundary: redact GrokBuild diagnostics locally, document or patch the Grok CLI logger separately, and compact parent worker receipts without deleting user logs. Stop after synthetic secret tests prove credential prefixes cannot reach UI, exports, receipts, or test output and all existing logs remain preserved pending separate cleanup authorization.

## Slice 8 — secret-safe backend logging and receipt compaction

### Objective

Stop backend diagnostics from retaining unnecessary credential breadcrumbs or
duplicating large worker results.

### Ownership boundary

`~/.grok/logs/unified.jsonl` is produced by the Grok CLI, not by SwiftUI. The
audit found thousands of `key_prefix`, refresh-token-prefix, or related auth
prefix fields. Their removal belongs upstream in the CLI logger. GrokBuild must
still protect any diagnostics it reads or exports.

### Changes

#### Grok CLI/backend owner

- Remove auth, access-token, refresh-token, and credential prefixes entirely
  from ordinary logs.
- Keep auth mode, source, expiry state, and success/failure only.
- Add bounded rotation/retention for unified logs.
- Store full subagent output once in the child session; parent completion
  receipts retain ID, status, duration, counts, safe preview, and content hash
  or reference.

#### GrokBuild owner

- Redact known secret-like fields before displaying or exporting diagnostics.
- Never show credential prefixes in the Activity sidebar or receipt Markdown.
- Warn when diagnostic files exceed a bounded size; do not delete them
  automatically.
- Treat upstream log cleanup as a separate repository/version gate rather than
  patching the retired GUI or hiding fields only in SwiftUI.

### Files

- GrokBuild diagnostics/export owner, located before implementation with `rg`
- `GrokBuild/Services/GrokProcess.swift` only for inbound receipt compaction or
  redaction
- secret-redaction tests using synthetic values
- a separate upstream Grok CLI issue/patch location, not this retired repo

### Gate

Synthetic auth prefixes never appear in exported diagnostics, UI, test output,
or receipts. Existing user logs are preserved until separately authorized for
cleanup.

### Implementation receipt — 2026-08-02

- `GrokMCPRedactor` removes authorization headers, bearer values, and JSON
  `key_prefix`, `access_token`, and `refresh_token` values before GrokBuild
  exposes backend diagnostics.
- `GrokProcess` applies that redactor to tool/lifecycle diagnostic text and
  bounds the retained value to 2,000 characters. Worker result bodies remain
  owned by their child sessions; the parent projection carries identities,
  terminal state, duration, turns, tool/token counts, and bounded safe error
  text only.
- Synthetic fixture and settings-extension tests assert that recognizable
  credential material cannot reach Activity, receipt text, or redacted
  diagnostics.
- GrokBuild neither reads nor rewrites `~/.grok/logs/unified.jsonl` as part of
  settlement. The installed acceptance gate records the file's initial byte
  count and SHA-256 and verifies that the same prefix survives the live run;
  normal append/rotation remains the Grok CLI's native ownership boundary.
- No existing Grok session, transcript, configuration, or log was deleted or
  rewritten to make this slice pass.

### Three-sentence handoff to Slice 9

Slice 8 is complete only when GrokBuild's diagnostic surfaces are secret-safe, oversized receipts are bounded, and upstream CLI ownership is not disguised as a SwiftUI fix. In the next session, implement Slice 9 only by running the complete automated gate, rebuilding and installing the canonical dirty worktree, and driving the exact installed parity scenario with Computer Use under current authorization limits. Do not publish or spend provider tokens without separate authority; stop with installed/dist identity, worker, tool, artifact, usage, continuity, relaunch, CPU, and orphan-process receipts.

## Slice 9 — installed parity acceptance and release gate

### Objective

Prove the repaired installed app, not merely unit-test the projection.

### Automated gate

- Run focused fixture, ACP, worker, continuity, artifact, tool-settlement,
  transcript-presentation, and snapshot tests.
- Run full `make test`.
- Run `git diff --check`.
- Confirm no test reads credentials or mutable live sessions.

### Installed Computer Use gate

1. Re-run canonical identity preflight.
2. Build/install the exact preserved worktree.
3. Confirm installed/dist executable parity and source stamp.
4. Run one fresh, bounded multi-agent fixture or explicitly authorized provider
   session.
5. Observe workers while running.
6. Observe both terminal worker receipts before the parent final.
7. Confirm zero active workers after completion.
8. Confirm tool failures and parent outcome are simultaneously legible.
9. Confirm the created artifact and Git review state appear in the correct
   sections.
10. Confirm continuity and live backend receipts do not contradict each other.
11. Quit/relaunch and verify restored evidence is labeled restored, not live.
12. Confirm settled CPU/process state and no orphaned helper owned by the run.

### Publication gate

No commit, push, PR, merge, tag, notarization, or release is authorized by this
document alone. If publication is later authorized, create a short-lived
`codex/*` branch, stage only intended paths, and use the maintained personal
repository. Never publish to the retired GUI or replace `origin`.

### Gate

Acceptance is complete only when the installed frontend and durable backend
agree on worker count/status, tool outcomes, artifact paths, usage, continuity,
model/process identity, and terminal turn outcome after quit/relaunch.

### Implementation receipt — 2026-08-02

- Live wire capture against Grok CLI `0.2.118` proved that the authoritative
  `response_completed` and `turn_completed` lifecycle frames arrive as
  `_x.ai/session_notification`. The CLI's persisted `updates.jsonl` uses the
  normalized `_x.ai/session/update` spelling. `GrokProcess` now accepts both
  native spellings plus standard `session/update`, while retaining exact tab,
  backend-session, process-generation, and prompt ownership checks.
- A completion watchdog can now report only
  `turnCompletionReceiptMissing`. It cannot mint `turnCompleted`, usage, or
  settled continuity. A receipt rejected at the `ChatStore` identity boundary
  fails immediately, and a broken generation is torn down instead of leaving a
  wedged Stop control or orphaned Grok child.
- The installed final run completed **two** read-only workers with exact child
  identities, **zero** active workers, **5 succeeded / 1 failed** parent tools,
  **275,078 tokens / 13 model calls**, and artifact
  `/tmp/grokbuild-main-acp-final2-0802.txt`. The deliberate bare
  `/usr/bin/test -e /tmp/grokbuild-intentionally-missing-final2-0802` receipt
  surfaced as failed from terminal `exit_code = 127` even though ACP's outer
  tool status was `completed`; the successful single-redirection command
  surfaced the external artifact separately from Git review state.
- Activity reported **Turn completed**, **Process Settled**, **Fresh backend
  bound**, both MCP servers **Ready**, both workers **Completed**, and one
  unresolved tool failure. Quit removed the app and its owned Grok stdio child;
  relaunch restored the complete transcript and marker
  `GB_MAIN_ACP_BRIDGE_FINAL2_OK_0802` while correctly withholding the ephemeral
  settled-run projection and live-backend claim.
- `make test` passed **539 tests with 0 failures**. The signed installed and
  `dist` executables are byte-identical at SHA-256
  `7c75a72e6272525015e12a00aee1d5208b6756eb573fbabec51257463ef706f1`;
  the installed stamp is personal repository, branch
  `codex/activity-parity-slice-0`, commit
  `a9bc1845ec07b40301874f66cfb7ac6a84e15965`, dirty worktree preserved.
- GrokBuild did not use `~/.grok/logs/unified.jsonl` as settlement authority and
  contains no source path that reads, truncates, or rewrites it. The initial
  byte-prefix preservation check did **not** survive the provider exercise:
  Grok CLI's own `xai-grok-telemetry/src/unified_log.rs` performed its native
  bounded trim/rewrite on the same inode. That upstream logger behavior is
  recorded as a failed prefix gate rather than concealed; no Grok session,
  transcript, config, or log was edited by GrokBuild to make the run pass.

### Three-sentence handoff after Slice 9

Slice 9 is complete only when the installed app and durable backend agree after quit/relaunch on every parity field and the final bundle identity matches the canonical worktree receipt. The following session should perform a read-only release review of the intended diff, retained dirty work, full test receipt, installed evidence, security redactions, and unresolved upstream CLI items before deciding whether publication is warranted. No commit, push, PR, merge, tag, notarization, release, cleanup, or provider spend is implied; request the exact next authorization and preserve all rollback and user state.

## Slice dependency order

```text
Slice 0 identity/fixture
  → Slice 1 lifecycle events
  → Slice 2 worker correlation
  → Slice 3 artifact/Git truth
  → Slice 4 continuity truth
  → Slice 5 tool settlement
  → Slice 6 reasoning presentation
  → Slice 7 run-evidence projection
  → Slice 8 log hygiene boundary
  → Slice 9 installed acceptance
```

Slices 3–6 may be implemented independently after Slices 0–2, but Slice 7 must
consume their settled state models rather than creating parallel logic.

## Explicit non-goals

- No work in `jimmmy-Jim/Grok-Build-GUI` or `/Users/jimmyschmitz/Documents/Grok Builf`.
- No replacement of Grok CLI with an embedded Agents SDK.
- No generic file watcher, cleanup daemon, or second task database.
- No inference of worker success from assistant prose.
- No claim that a completed parent automatically recovered every failed tool.
- No automatic deletion of logs, sessions, caches, artifacts, or rollback apps.
- No provider/model billable probe without a current explicit authorization.
- No GitHub publication without explicit publication scope.

## Definition of parity

Frontend/backend parity is achieved when the following mapping is deterministic:

| Backend evidence | Required frontend state |
|---|---|
| `subagent_spawned` | one worker with exact child identity |
| `subagent_finished: completed` | same worker terminally completed |
| wait/collect tool | receipt on existing worker, never a new worker |
| failed tool update | failed call with safe error and unresolved/retry truth |
| successful write | run artifact; Git review refreshed separately |
| fresh `session/new` ID | fresh backend bound, never `noBackendBinding` |
| restored verified history | verified/restored provenance |
| `turn_completed` usage | settled outcome and exact usage totals |
| later event from old generation | ignored or visibly orphaned, never merged |

Anything less is a pretty dashboard narrating fan fiction.
