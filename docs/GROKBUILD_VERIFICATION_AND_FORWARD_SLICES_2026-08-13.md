# GrokBuild agentic-performance verification and forward slices — 2026-08-13

Status: **Slices 0–6 complete after the final closeout receipt merges; Slice 7 is next for a new session only.**

This plan follows the canonical identity and Gates A–H in
[`CANONICAL_WORKTREE.md`](../CANONICAL_WORKTREE.md) and
[`docs/OUTSTANDING.md`](OUTSTANDING.md). Jimmy has authorized billable prompt
acceptance for future slices and has no spending cap. That freedom should be used
to test the workbench where it is supposed to matter: subagent coordination,
long-horizon task continuity, ordered and parallel multi-tool work, recovery from
partial failure, Stop behavior, and trustworthy run evidence—not to spray tokens at
decorative one-turn demos. Each packet still needs a frozen prompt, exact
route/model, unique marker, retry boundary, actual-usage receipt, exact test-thread
cleanup, and process-zero closeout. The ceilings below are anomaly circuit breakers,
not budget caps; a healthy, intentionally long run may continue when its checkpoint
records why.

## Review verdict

The maintained line is in unusually strong shape. The local tree, personal fork,
installed app, signing identity, and packaged binary all agree at the reviewed
baseline. The full suite passes. The latest Cursor work is coherent with the
thin-wrapper architecture and materially improves lifecycle truth.

The next work should not be another broad polish campaign. It should make GrokBuild
a better cockpit for serious agentic work: prove that parent/child coordination is
stable under reordered events, keep long-horizon and scheduled work alive on
purpose, make complex multi-tool runs inspectable after the fact, and compare model
behavior on repeatable workloads without pretending that token count equals quality.
The publication gate still comes first because expensive agentic proof without an
independent merge gate is just artisanal optimism.

### Re-derived baseline

| Authority | Reviewed value |
|---|---|
| Canonical checkout | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Personal repository | `schmitzjimmy1-star/grok-build-desktop` (`personal`) |
| Preserved upstream | `rimusz/grok-build-desktop` (`origin`) |
| Branch / HEAD | clean `main` at `8c8cfb0bc5d099423da62857b1e06ee62aeab91b` |
| Remote parity | `main == personal/main`, `+0/-0` |
| Installed app | `/Applications/GrokBuild.app` |
| Installed receipt | `main`, source `8c8cfb0`, `dirty=false`, `com.grokbuild.app` |
| Signing | Apple Development, Team `DD2GCQJVB4` |
| Dist / installed executable | matching SHA-256 `8de6f7c505581a32790646aa809150603a8c7afa123843ff7edc336a60cbbf83` |
| Automated tests | `make test`: **802 passed, 0 failed** in 31.7 s |
| Latest GitHub work | PR #65 and PR #66 merged into `main` |

### Findings

#### P1 — the remote PR gate exists on disk but does not run

`.github/workflows/pr.yml` declares test-and-build checks, but GitHub reports no
workflow runs for PR #65 head `89efdd8`, PR #66 head `b26b9b6`, or any other run
in the fork. The combined commit statuses are empty and `main` is not protected.
Local `make test` is green, but today a PR can merge without independent GitHub
execution.

This is the only clear release-process defect found in the current baseline.

#### P1 — scheduled work has an underpowered lifetime contract

`ContentView.enforceConnectionCap()` protects the four most-recent sessions and
any session currently `.busy`, but it does not protect a connected session merely
because `ChatStore.scheduledTasks` contains an active `/loop`. The documented
behavior is truthful—schedules run only while that session process is alive—but a
quiet recurring task can therefore lose its runtime through ordinary LRU eviction.
The product needs an explicit retention policy and visible ownership, not a footnote.

#### P2 — subagent correlation is truthful but not permutation-complete

The new `BackgroundTaskTracker` correctly separates spawn-tool rows,
`subagent_spawned`, `subagent_finished`, unreadable child ledgers, and unbound
spawn receipts. The tests cover the normal tool → spawned → finished order,
description binding, missing receipts, Stop, and turn clearing.

The reducer has two one-way reconciliation triggers that deserve hostile tests:

- a `subagent_finished` receipt arriving before its matching
  `subagent_spawned` receipt can remain in `pendingFinishedEvents` after the spawn
  later binds by description;
- a `subagent_spawned` receipt arriving before a late spawn-tool row whose child ID
  is still null is not re-bound merely because that late row now supplies the exact
  title/description match.

Those are protocol-ordering risks, not confirmed live failures. They should be
settled with table-driven permutation tests before more lifecycle features land.

#### P2 — the README hero image is stale product evidence

`docs/images/grokbuild-app.png` entered history on 2026-07-24 and shows the old
pre-facelift shell: permanent chips and status controls, no current command rail,
no Ask/Build/Review empty state, no Run inspector, no Session dashboard, and the
old composer. The prose beneath it describes the current interface, so the first
thing a reader sees contradicts the product.

#### P2 — the remaining architecture bottleneck is coordination density

The Settings split succeeded, but the largest owners are still substantial:

| File | Current size |
|---|---:|
| `GrokBuild/Services/ChatStore.swift` | 5,421 lines |
| `GrokBuild/Views/ChatView.swift` | 3,569 lines |
| `GrokBuild/Services/GrokProcess.swift` | 2,915 lines |
| `GrokBuild/ContentView.swift` | 2,036 lines |

The suite is broad, but roughly one hundred test assertions inspect source text or
file contents. Those are useful architecture tripwires; they are not substitutes
for reducer and service behavior tests. Future extraction should move pure policy
out first and replace the most brittle string pins as it goes.

## Agentic-performance scorecard

Every billable acceptance packet should answer the same questions so later slices
produce comparable evidence instead of a scrapbook of impressive anecdotes.

| Dimension | Required evidence |
|---|---|
| Subagent coordination | Parent and child identities, spawn/finish ordering, child tool ledgers, terminal state, unresolved bindings, and no cross-turn leakage |
| Long-horizon continuity | Multiple turns or scheduled checkpoints on one backend, relaunch/restore truth, context continuity, and explicit process/runtime ownership |
| Multi-tool execution | Planned versus observed tool order, parallel groups where intended, per-tool result detail, retry count, artifacts, and partial-failure behavior |
| Recovery and control | Stop during a child/tool call, permission denial, one injected tool failure, resumability, exact cleanup, and process zero |
| Model/route performance | Exact effective model and route, time to first chunk when measurable, provider duration, tokens/calls/cost, completion outcome, and workload class |
| Evidence quality | Live versus historical labels, generation/backend binding, redaction, deterministic export, and no invented provider or worker claims |

Do not optimize for maximum child count, maximum tool count, or the prettiest final
answer. Optimize for correct decomposition, useful concurrency, bounded recovery,
continuity across checkpoints, and receipts that explain what the system actually did.

## Checkpoint and handoff contract

Each slice has four checkpoints: **baseline**, **focused implementation**,
**signed-installed acceptance**, and **merged-main closeout**. A documentation-only
or GitHub-configuration slice may mark a checkpoint not applicable, but it may not
silently skip the closeout.

At the end of **every checkpoint update in the working thread**, the agent must write
exactly three plain-prose sentences that can be copied into a fresh session without
editing:

1. Sentence one states the canonical repo, branch/commit, slice, completed checkpoint,
   and exact verified result.
2. Sentence two states live app/backend/process state, billable usage, created test
   thread IDs, cleanup status, and any unresolved risk; use `none` explicitly rather
   than omitting a field.
3. Sentence three gives one next authorized action plus the hard stop, including the
   files or systems that must not be touched.

The three sentences are a handoff, not a victory lap: no bullets, no fourth sentence,
no vague “continue testing,” and no claim of completion before merged-main identity,
installed proof, cleanup, and process zero agree. If work stops mid-checkpoint, the
same three sentences must say **incomplete**, identify the last settled receipt, and
name the exact restart point.

## Slice sequence

The recommended order is 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7. Each slice gets one
bounded branch and one personal-fork PR. Do not push to `origin`, combine slices,
or add a GrokBuild-side agent runtime, proxy, or provider fallback.

## Slice 0 — make GitHub PR checks real

**Purpose:** turn the existing workflow from decorative YAML into an enforced
independent gate.

### Scope

- Determine why Actions has zero runs in the personal fork: repository Actions
  policy, fork workflow approval, permissions, or event configuration.
- Trigger `PR Checks` on a disposable documentation-only PR and prove the exact
  head SHA receives one completed `Test and Build App` job.
- Pin the required check on `main` through branch protection or a repository
  ruleset.
- Keep `release.yml` manual. Do not publish a release, rotate secrets, or touch
  notarization credentials.
- Add a compact check/run receipt to `.github/workflows/README.md`.

### Acceptance

- One PR-head workflow run exists and passes `make test`, `make app`, and bundled
  `agent-desktop version`.
- A red or pending required check blocks merge; a green exact-head check permits it.
- The branch rule applies to Jimmy's personal `main`, not upstream `origin/main`.
- No billable model prompt is needed. Ceiling: **0 tokens**.
- The merged-main closeout ends with the mandatory three-sentence handoff and names
  the exact required check and successful run URL for the next session.

## Slice 1 — permutation-proof and benchmark subagent coordination

**Purpose:** make worker truth independent of benign ACP event reordering, then prove
that useful two-child work remains attributable, controllable, and inspectable over a
multi-turn parent run.

### Scope

- Extract a small typed correlation reducer from `BackgroundTaskTracker` if that
  makes the state machine easier to prove; do not create a second lifecycle owner.
- Reconcile pending spawn and finish receipts whenever either the tool row, spawn
  event, or finish event supplies a newly usable identity.
- Preserve the current rules: no invented worker row, no prose-as-authority, no
  fake completion, exact tab/backend/generation ownership, and no cross-turn leak.
- Add a table-driven permutation suite covering all six orderings of tool,
  spawned, and finished events, plus duplicate, ambiguous-description, missing-ID,
  wrong-generation, Stop, and next-turn-clear variants.
- Record coordination metrics per parent turn: requested/spawned/finished child
  count, maximum useful concurrency, child tool-call count, unresolved identities,
  Stop-to-settle time, and parent/child usage when the backend exposes it.
- Treat these as observations, not a scoreboard. More children are not better when
  one child or a direct tool call would do the job.

### Billable acceptance

Run one native Grok 4.6 packet in which a parent decomposes a real repository question
between exactly two children, each child uses at least one different read-only tool,
and the parent synthesizes both results across a second turn. Capture live and settled
worker rows, child IDs, terminal receipts, child tool ledgers, parent tool separation,
concurrency, artifacts, and usage. Then run one Stop-mid-child packet where the child
is allowed to finish during the teardown window, followed by a fresh-turn continuity
check that must not inherit stale worker state.

Suggested anomaly ceiling: **500k actual tokens**. No automatic retry; at most two
children; no OpenRouter lane unless the reducer behavior differs after native proof.

### Exit

All permutations produce one stable worker identity and the right terminal or
explicit unresolved state. The parent can complete a multi-turn synthesis without
losing child attribution, and Stop settles truthfully without ghost workers or
cross-turn leakage. The exact test threads are deleted, Gate G ends at process zero,
and the checkpoint update ends with the mandatory three-sentence handoff.

### Slice 1 acceptance receipt — 2026-08-14

- **Code and deterministic proof:** the single-owner reducer, optional durable
  coordination receipt, and Run-details presentation are frozen at code commit
  `3e4fd2575276a4437881de6bfe3938821eeb1bdf` on
  `codex/slice-1-subagent-coordination` in PR #69. The table-driven suite covers
  all six tool/spawn/finish orders plus duplicate replay, ambiguity, missing
  identity, generation ownership, Stop, and next-turn clearing. Focused tests
  passed 85/85 and `make ship` passed 807/807 with installed stamp equal to that
  code commit, `dirty=false`, dist/install binary parity, Team `DD2GCQJVB4`, a
  strict deep signature, no quarantine, and both bundled helpers present.
- **Two-child native Grok 4.6 packet:** parent
  `019ffeb7-3a49-7a00-aa20-78c54af04512` used marker
  `GB-S1-COORD-20260814T002000Z`; child A
  `019ffeb7-618a-7a80-9e91-7d1fbe8ec42a` used one Read receipt, and child B
  `019ffeb7-618c-7110-9fd6-90bd858e5a53` used one terminal receipt. Live UI
  showed both children concurrently and then one running/one done. Settlement
  reported `2 requested • 2 spawned • 2 finished • max 2 concurrent`, two child
  tool calls, 93,178 parent tokens, 24,675 child tokens, seven model calls,
  provider API time 27.7 seconds, provider-reported cost $1.53, zero failures,
  and no artifacts. The second-turn marker
  `GB-S1-COORD-T2-20260814T002100Z` stayed on the same parent, repeated both
  child IDs and the exact 777-line result, used zero tools/children, and reported
  18,615 parent tokens plus $0.11 provider-reported cost.
- **Stop and continuity packet:** parent
  `019ffeb8-719e-7d03-bd68-260081051573`, marker
  `GB-S1-STOP-20260814T002200Z`, spawned exact child
  `019ffeb8-894e-7222-8056-e9b5fe9fc30e`. User Stop settled the app receipt in
  462 ms as `1 requested • 1 spawned • 0 finished • max 1 concurrent`, with the
  worker explicitly orphaned/no-final-report and usage unavailable rather than
  invented. The backend later recorded that child `cancelled` after 7,669 ms
  with zero reported tool calls/tokens; no retry was sent. The next marker
  `GB-S1-STOP-CONT-20260814T002300Z` continued as new backend
  `019ffeb9-150f-76a3-9a16-f3163bebbc6b`, generation 2, and settled as Recovery
  fork with `0 requested • 0 spawned • 0 finished • max 0 concurrent`, zero
  tools, 16,047 parent tokens, and $0.27 provider-reported cost. Thus no prior
  worker leaked into the fresh turn; reported costs across accepted turns total
  $1.91, and the separately reported token fields remain below the 500k anomaly
  ceiling without guessing whether parent totals already aggregate child usage.
- **Cleanup and closeout:** GrokBuild closed both exact local test tasks; CLI
  searches for all three markers return zero, and all six ledgered IDs are absent
  from the live session root. The CLI did not index the three child directories
  independently, so their handle-free residual directories were moved intact to
  recoverable Trash at
  `/Users/jimmyschmitz/.Trash/GrokBuild-Slice1-child-residue.198mJ0`; historical
  prompt-history entries were not rewritten. Two post-quit process samples found
  no GrokBuild, helper, `agent-desktop`, or `grok agent` process. No OpenRouter,
  provider/configuration/credential/release/upstream change, automatic retry, or
  Slice 2 work occurred.

## Slice 2 — give long-horizon and scheduled tasks an explicit runtime lease

**Purpose:** make recurring and long-horizon work durable enough to trust without
pretending the CLI can execute after its owning process is gone.

### Product contract

- A session with an active schedule is visibly **runtime pinned** and excluded from
  ordinary idle LRU eviction.
- The Session dashboard and Tasks menu explain why the process is retained and when
  the schedule last produced an authoritative receipt.
- If protected busy/pinned sessions exceed the normal cap of four, show a truthful
  soft-cap warning. Never silently cancel a schedule or evict its process.
- Closing the session, cancelling the schedule, quitting the app, or an exact process
  failure releases the lease with explicit copy. No launch daemon or hidden daemon.
- Restored metadata must not claim a lease until the exact schedule inventory is
  re-observed from the live backend.
- A long-horizon run displays its owning session, backend, process generation, last
  settled checkpoint, next scheduled checkpoint when applicable, and whether it is
  safe to close, Stop, or resume.
- Multi-turn continuity is proved from authoritative backend/session identity; a
  similar-looking transcript after relaunch is not continuity proof.

### Implementation shape

- Add a pure `SessionRuntimeRetentionPolicy` consumed by
  `ContentView.enforceConnectionCap()`.
- Feed it exact connection state, selected/MRU identity, and authoritative active
  schedule inventory.
- Add behavior tests for four ordinary sessions plus pinned schedules, multiple busy
  sessions, cancellation, close, quit, restore, and a stale cached schedule.

### Billable acceptance

Create one disposable `/loop` with a unique marker that performs a small read-only
multi-tool repository check at three checkpoints, then open enough minimal native
no-tool sessions to cross the normal four-process cap. Prove the scheduled session
keeps the same authoritative ownership, survives ordinary session switching, emits
all three checkpoint markers, and exposes any tool failure without silently skipping
the remaining horizon. Cancel that exact schedule, prove the lease releases, then
close/delete only the ledgered sessions.

Suggested anomaly ceiling: **600k actual tokens**. The cost is secondary here; exact
schedule cleanup and process ownership are the hard gates. Every checkpoint update,
including an overnight or resumed checkpoint, ends with the mandatory three-sentence
handoff so a new session can continue without reconstructing state from vibes.

### Slice 2 acceptance receipt — 2026-08-14

- **Code and deterministic proof:** the generation-bound inventory receipt and
  runtime lease, protected-outside-ordinary MRU policy, mounted Tasks menu, Session
  dashboard ownership rows, and soft-cap warning are frozen at code commit
  `21f293bf67cb6af2f293b884b20f380948f3ad24` on
  `codex/grokbuild-audit-s2-runtime-lease`. Focused retention/scheduler/dashboard
  coverage passed 23/23 and `make ship` passed 817/817 with installed stamp equal to
  that clean commit, dist/install binary parity, Team `DD2GCQJVB4`, strict deep
  signature verification, no quarantine, and bundled-helper packaging. Installed
  acceptance first caught and fixed two candidate defects: the Tasks menu builder
  was not mounted, then a selected protected schedule consumed one of the four
  ordinary MRU slots. The final pure-policy regression proves the selected pinned
  runtime remains outside all four ordinary slots.
- **Schedule continuity and truthful UI:** disposable native Grok 4.6 loop parent
  `019ffee2-88b0-78e2-bef6-8d2ed6ceeadb`, task `019ffee29ff1`, and marker
  `GB-S2-LEASE-20260814T0106` retained backend ownership at process generation 1.
  Four detached checkpoint children—`019ffee2-9ff2-7320-9f81-14a0ce813a90`,
  `019ffee3-8a54-78c2-877f-03d8715c6725`,
  `019ffee4-74b5-7352-945e-8eeec9a863ca`, and
  `019ffee5-5f17-7f70-ae7b-b1c842255688`—each used the bounded Read plus
  `git rev-parse --short HEAD` path and independently returned
  `GB-S2-LEASE-20260814T0106 GrokBuild 0f9622b`. The fourth checkpoint exceeded the
  frozen three-checkpoint target while the MRU defect was being isolated; it was
  recorded rather than hidden, and the exact task was then cancelled. Relaunching
  the earlier cancelled-loop tab showed `runtime not pinned` and explicitly said
  cached/restored metadata could not mint a lease without live re-observation.
- **Exact corrected cap proof:** final no-fire parent
  `019ffeeb-7090-7ce1-9e56-f764e7ecb53c` created exact task `019ffeeb8180` at a
  one-hour cadence with `fire_immediately=false`. The Tasks menu reported that
  backend at generation 1; four ordinary live runtimes plus the protected schedule
  produced five exact Grok child processes beneath GrokBuild PID 54608, while the
  Session dashboard reported `Runtime soft cap exceeded by 1` and kept the pinned
  row visible. Cancelling that task immediately changed the menu to
  `runtime not pinned` and the OS tree to four Grok children, proving lease release
  without a daemon or hidden continuation.
- **Failure and child lifecycle:** parent
  `019ffeef-4935-7802-8c12-9177cb58763b` attempted one deliberately missing Read,
  preserved the visible failure without retry, spawned exact child
  `019ffeef-682a-7571-88a0-eee44e24e7fc`, waited once, and still settled with marker
  `GB-S2-FAIL-CHILD-20260814T0121` plus child result `# GrokBuild Desktop App`.
  Unified Grok receipts report 747,964 actual prompt-plus-completion tokens across
  46 model calls for the full exploratory acceptance sequence, 147,964 above the
  suggested 600k anomaly ceiling because the two installed defects required fresh
  signed-build reruns and the loop emitted one extra checkpoint. Every inference
  recorded `attempts: 1`; there was no automatic provider retry and no further
  billable send after the overrun was calculated.
- **Cleanup and closeout:** both schedules were cancelled before teardown. GrokBuild
  closed every exact Slice 2 local tab, leaving zero matching local transcripts and
  deleting all root backend sessions. The Grok CLI does not index detached children
  for `sessions delete`, so the six verified child-session directories were removed
  directly and irrecoverably; only the shared historical `prompt_history.jsonl`
  audit entries remain untouched. Two post-quit samples found no GrokBuild, helper,
  `agent-desktop`, or Grok process. No OpenRouter, provider/configuration/credential,
  release, upstream-origin, automatic-retry, Slice 3, or unrelated system change
  occurred.

## Slice 3 — add durable agentic Run history and redacted evidence export

**Purpose:** turn complex multi-turn, multi-tool, and multi-agent receipts into
something users can revisit and share instead of confining them to one turn's
inspector.

### Product contract

- Add **Run history** to the Session dashboard, derived from persisted
  `AssistantTurnCheckpoint` data already attached to assistant messages.
- Show outcome, model/route, tool and worker counts, usage, artifacts, unresolved
  evidence, and timestamp with the same truth labels as the Run inspector.
- Group checkpoints into one long-horizon run without flattening turn boundaries;
  show parent/child topology, tool sequence and parallel groups, retries, Stop/resume
  boundaries, and the last authoritative continuation point.
- Add explicit **Copy redacted Markdown receipt** and **Export redacted JSON** actions.
- Export only already-redacted, typed receipt fields. Exclude prompts, response bodies,
  credentials, raw environment values, and private chain-of-thought.
- A historical checkpoint is labeled historical; it never becomes current Live state.

### Verification

- Round-trip old and new transcript fixtures, including legacy messages without a
  checkpoint, a failed tool, a user Stop, an unreadable child ledger, and an external
  artifact label.
- Confirm export is deterministic, bounded, and contains no `sk-`, bearer token,
  Keychain material, raw MCP environment, or transcript prose.
- Installed acceptance uses one native three-turn packet with ordered tools, one
  parallel two-child phase, one injected tool failure with bounded recovery, and one
  Stop/resume boundary; then quit/relaunch, inspect Run history, and compare Markdown/
  JSON exports.

Suggested anomaly ceiling: **400k actual tokens**.

## Slice 4 — observed agentic model-performance ledger

**Purpose:** help Jimmy choose models for actual agentic workloads using local evidence
without inventing quality scores or adding automatic routing.

### Product contract

- Record bounded, local-only per-model observations from authoritative completion
  receipts: first-chunk latency when measured, provider API duration, total/input/
  output/cached/reasoning tokens, calls, cost, outcome, and tool/worker presence.
- Classify the workload as no-tool, ordered multi-tool, parallel multi-tool,
  two-child coordination, long-horizon continuation, or recovery. Never compare
  unlike workload classes as if they were one benchmark.
- Surface a compact **Observed on this Mac** section in the model menu or Settings →
  Models: sample count, median/range for measured fields, completion and recovery
  rates, unresolved-worker rate, and last observed route.
- Separate native xAI, direct OpenAI-compatible, local, pinned OpenRouter, and
  `openrouter/auto`. Downstream OpenRouter serving identity remains unproven.
- Never auto-select a model, declare one "best," compare unlike workloads as quality,
  or manufacture `$0` for missing prices.
- Provide **Clear local observations** with an exact confirmation and no effect on
  provider credentials, Grok history, or transcripts.

### Billable acceptance

Use frozen same-workload matrices on fresh sessions. Each lane runs an ordered
three-tool task, a parallel two-child synthesis, and a three-turn continuation with
one recoverable tool failure; the simple no-tool marker is retained only as a route
and latency control.

| Lane | Packet |
|---|---|
| Native | Grok 4.6: control marker plus the full agentic workload matrix |
| Direct | `gpt-5.6-luna`: identical prompts, tools, recovery boundary, and turn count |
| Brokered | pinned `openai/gpt-4.1-mini`: identical matrix; downstream provider remains unproven |

Inspect live route receipts, settled usage, child/tool correctness, time to settle,
recovery behavior, continuity, ledger aggregation, relaunch persistence, and clear
behavior. Human-review the final synthesis against a frozen evidence key, but store
no fake scalar “quality” score. Suggested anomaly ceiling: **1.5m actual tokens**;
this is a stuck-run breaker, not a spend limit.

## Slice 5 — build a first-class agentic acceptance harness

**Purpose:** make expensive product proof repeatable, reviewable, and much less
dependent on heroic manual note-taking.

### Scope

- Add a versioned acceptance-manifest schema under `scripts/acceptance/` for exact
  marker, model, route, effort, prompt, allowed/required/forbidden tools, ordered and
  parallel tool groups, child topology, turn/checkpoint count, retry and recovery
  boundaries, expected receipt classes, continuation rules, and anomaly ceiling.
- Provide a preflight that verifies installed stamp/signing/hash, CLI version,
  configured model availability, process zero, and clean test-thread ledger before
  enabling Send.
- Capture structured receipts and generate a Markdown closeout packet with the
  three-sentence checkpoint handoff already rendered for the agent to post verbatim.
  The harness may assist with exact test-session cleanup but must stop rather than
  guess an ID.
- Require an explicit `--billable` flag even though this campaign is authorized.
  Dry-run is the default and prints the frozen plan without credentials or response
  bodies.
- Do not bypass the installed UI, fake ACP authority, auto-approve permissions, or
  kill broad process patterns.

### Acceptance

- Fixture mode proves dry-run, duplicate-marker refusal, ceiling stop, wrong-model
  stop, missing-receipt stop, event reordering, child/tool partial failure, interrupted
  horizon, resume mismatch, and exact cleanup ledger behavior at zero cost.
- Installed mode runs one three-route, multi-turn, multi-tool, two-child manifest and
  reproduces the same receipts as a manually inspected pass.
- The generated handoff is exactly three sentences and includes repo/commit/checkpoint,
  live state/usage/cleanup/risk, and next action/hard stop. Fixture tests reject two or
  four sentences and missing `none` fields.

Suggested anomaly ceiling for the installed harness proof: **1.5m actual tokens**.

## Slice 6 — extract coordination seams and replace brittle test pins

**Purpose:** lower the cost of every later feature without a behavior rewrite.

### Scope

Do this as multiple tiny PRs if necessary, but never mix it with product behavior.

Current files. Reuse the extracted owners; do not create a second reducer, LRU
policy, or export type:

1. Extract remaining subagent/lifecycle correlation from `ChatStore` into
   `BackgroundTaskTracker` in `GrokBuild/Services/BackgroundTaskStore.swift`
   (already proven by Slice 1). Remaining call sites:
   `ChatStore.backgroundTaskTracker`, thin `ChatStore.currentTurnEvidenceWorkers()`
   (delegates to `BackgroundTaskTracker.evidenceWorkers`), and ChatStore
   turn-scoped worker ID sets in `GrokBuild/Services/ChatStore.swift`.
2. Extract remaining session-retention/LRU decisions from `ContentView` into
   `SessionRuntimeRetentionPolicy` in `GrokBuild/Models/SessionProcessIdentity.swift`
   (already proven by Slice 2). Remaining call sites:
   `ContentView.runtimeRetentionDecision` and `ContentView.enforceConnectionCap()`
   in `GrokBuild/ContentView.swift`.
3. Keep `RunHistory` in `GrokBuild/Models/RunHistory.swift` as the Sendable export
   layer. `RunHistory.snapshots(for:)` and `RunHistory.Presentation` own dashboard
   snapshot/formatting. Remaining call sites: `ContentView.openActivityDashboard()`
   (when to snapshot) and `SessionDashboardPanel` hosting `RunHistorySection`.
4. `ChatTopBar`, `ChatComposer`, and `ChatHeaderReviewToggle` own workbench
   chrome layout. Remaining call sites: thin `ChatView.topBar` / `composer` /
   `headerReviewToggle` wrappers that keep Tasks, slash matching, add-menu, and
   send state on `ChatStore` / `ChatView`.
5. Replace source-string assertions for touched contracts in
   `Tests/GrokBuildTests/ACPClientContractTests.swift` (the tests that
   `String(contentsOf:)` `ChatStore.swift`, `ContentView.swift`, `ChatView.swift`,
   or `GrokChatChrome.swift`) with compile-time or behavior tests; keep a few
   deliberate architecture tripwires.

Supporting tests: `SessionRuntimeRetentionTests.swift`, `RunHistoryTests.swift`,
`LifecycleAndSubprocessTests.swift`, `AcceptanceHarnessTests.swift`. Smoke driver:
`scripts/acceptance/run.py` with `manifests/installed-slice6-packet-v1.json`
(250k actual-token ceiling). Checkpoint handoff:
`scripts/acceptance/harness/handoff.py`. Installed proof is
`/Applications/GrokBuild.app` after `make ship`; `make run` opens `.build`.

### Acceptance

- No product copy, persistence schema, launch argv, provider route, or installed
  behavior changes.
- Focused tests plus `make test`, `make ship`, session switch/restore, Stop, close,
  quit, and process zero.
- The smoke is an agentic packet: three ordered tools, two parallel read-only child
  investigations, one follow-up turn, and one deliberate Stop. Prove no behavior or
  receipt drift before calling the extraction neutral.
- Suggested anomaly ceiling: **250k actual tokens**.

**Stop-the-line repair receipt (2026-08-14).** The neutral packet exposed two
installed macOS 26 SwiftUI layout loops, first during inspector-width movement
and then while restoring/resuming a populated tool transcript. The bounded
follow-up commit `079589bbf0573cb300ead69ac7410277a67d20b9` passed the focused
50-test layout suite and all 865 tests, then clean `make ship` with stamp ==
HEAD, `dirty=false`, dist/installed parity, Team `DD2GCQJVB4`, deep/strict
signing, no quarantine, and installed executable SHA-256
`42939354d0cbc4fc88cfc9400c11c7d0f897fc8ef81b1264005fb942f02aba1`.
Installed Computer Use proved the tool-heavy T1 transcript restored at 0.0% CPU
with no `grok` process; a separate populated saved task then changed from the
three named launch choices through **Resume current task** to connected idle,
with GrokBuild and its exact `grok` child both at 0.0% CPU after four seconds
and after a twenty-second soak. No prompt or billable provider turn ran.
Graceful close left process-zero samples at
`2026-08-14T22:05:47-0500` and `2026-08-14T22:05:59-0500`.

PR [#82](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/82)
passed GitHub **Test and Build App** run `31860976853` and merged normally as
`092bebca132f8a2980055462d0292dd0908cbfbf`. Clean merged `main` then passed all
865 tests and signed `make ship` with stamp == HEAD, `dirty=false`,
dist/installed parity, Team `DD2GCQJVB4`, deep/strict signing, no quarantine,
and installed executable SHA-256
`b0dadd8b04b66f2e4d94b48ccb47e4894812623b2a76c42476f11dbde0872cad`.
Computer Use against explicit `/Applications/GrokBuild.app` restored the
populated saved task and resumed to connected idle; exact GrokBuild and `grok`
processes remained at 0.0% CPU after four seconds and a twenty-second soak. No
prompt ran. Graceful close left merged-main process-zero samples at
`2026-08-14T22:20:39-0500` and `2026-08-14T22:20:47-0500`.

**Final acceptance receipt (2026-08-14).** Billable run
`20260815T033736Z` used Grok 4.6 under the 250k anomaly ceiling and evaluated
all three packets accepted at **165,710 actual tokens**. T1 retained the ordered
ONE/TWO/THREE terminals, exactly two successful concurrent children, exact
child backend IDs, and one `wait_all`; T2 retained the same local tab and parent
backend with the exact follow-up marker; T3 used the native Stop control and
retained `userStopped` with zero billed tokens. Installed Computer Use showed
the six successful coordination rows, exact T2 continuation, disabled empty
composer, and **Settled: Stopped by you**.

The first closeout attempt `20260815T033451Z` completed at 164,878 tokens but
the evaluator rejected its otherwise complete product receipt because the
settled ACP trace titles `LEFT child echo` and `RIGHT child echo` were
classified as generic `other` tools. The harness now maps that child-specific
settled shape to `spawn_subagent`, with zero-cost fixture coverage for both
children and `wait_all`; the fresh run above then passed without changing app
runtime behavior. Focused harness tests and all 865 repository tests passed with
zero failures. Both closeout tabs and original T1 tab were closed through their
exact installed-UI rows, all three local transcript/parent-backend identities
and six child IDs are absent, protected config is unchanged, final CPU settled
at 0.0% except one transient 1.0% accessibility sample, and process-zero passed
at `2026-08-14T22:43:16-0500` and `2026-08-14T22:43:21-0500`.

## Slice 7 — refresh public evidence and onboarding

**Purpose:** make the repository's first impression match the product that actually
ships.

### Scope

- Replace `docs/images/grokbuild-app.png` with a current signed-installed screenshot.
- Add a compact second image showing a settled tool turn with the docked Run inspector.
- Capture System/Dark and Light appearance if both are current supported surfaces;
  otherwise document the actual appearance contract instead of staging a fake image.
- Tighten the README's first screenful around three truths: thin wrapper over Grok CLI,
  project/thread workflow, and exact model/route receipts.
- Move historical acceptance detail out of the opening product pitch; keep links to
  the authoritative docs.

### Acceptance

- Screenshots come from `/Applications/GrokBuild.app` stamped to the exact merged
  `main`, not a debug preview.
- AX names match **Run inspector**, **Session dashboard**, **Describe a task**, and
  **What do you want to work on?**
- One minimal native tool turn may be used to populate the inspector. Suggested
  anomaly ceiling: **100k actual tokens**; reuse no prior provider history.
- The final public example should show a settled multi-tool/two-child run with readable
  parent/child and tool evidence, not another chatbot answering a one-line prompt.

## Ideas deliberately rejected

- Reimplementing ACP, MCP execution, memory, skills, plan mode, or subagents in the app.
- Adding an app-side fallback router or claiming OpenRouter's downstream provider.
- Keeping scheduled tasks alive through a new daemon or LaunchAgent.
- Persisting raw prompts, responses, tool inputs, credentials, or chain-of-thought in
  the performance ledger.
- Auto-running billable matrices merely because a model is configured.
- Treating a green unit suite, exact marker, polished answer, or `/health`-style status
  as installed-product acceptance.
- Calling gratuitous tool calls, child spam, or token burn “agentic performance.”
- Ending any checkpoint without the exact three-sentence copy/paste handoff.

## Current authorized slice

Execute **Slice 7 only** from the exact merged Slice 6 closeout. At session
start, require clean `main == personal/main`, installed stamp == HEAD,
`dirty=false`, dist/installed byte parity, Team `DD2GCQJVB4`, deep/strict
signing, no quarantine, and two process-zero samples. Slices 0–6 are closed;
do not rerun their provider packets or reuse their markers. Slice 7 must refresh
signed-installed public screenshots and the README first screenful within its
documented scope, then end every checkpoint and its final merged-main closeout
with the mandatory three-sentence handoff.
