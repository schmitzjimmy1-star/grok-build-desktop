# GrokBuild Official Runtime Alignment Campaign — 2026-08-16

Status: **Slices 0–3 complete; Slice 4A nonbillable implementation complete inside Slice 4; paid activation locked.** Jimmy authorized a rigorous
merge-per-slice campaign on 2026-08-16. Every slice gets its own branch,
explicit commits, ready pull request, exact-head required checks, normal merge,
merged-main installation, and process-zero closeout before the next slice begins.

Current code-bearing baseline and installed app: clean merge
`d774b365f9281cef6c8d53e6b2746a7f9a9c52e1` (PR #118). The dist and installed
executables match byte-for-byte. Installed CLI authority is
`grok 1.0.4 (d846eb93d94d) [stable]`. Official 1.0.5 source informs this
campaign, but no CLI upgrade is authorized.

## Governing decision

Keep the native macOS workbench. GrokBuild owns projects, tabs, accessibility,
local presentation caches, Git review, and typed evidence presentation. Grok CLI
owns reasoning, model routing, filesystem and terminal execution, sandboxing,
permissions, hooks, MCP invocation, memory, sessions, worktrees, and subagents.
ACP and explicitly version-gated `x.ai/*` methods are the runtime contract;
private CLI storage and app-side execution are not.

No slice may add a second LLM runtime, provider fallback chain, model server,
persistent control daemon, private-session parser, or competing tool executor.
Open-weight endpoints remain external OpenAI-compatible services consumed by the
Grok CLI.

## Slice map

| Slice | Title | Authorized job | Status |
|---|---|---|---|
| **0** | **Restore CLI execution ownership** | Disable ACP client FS/terminal capabilities; remove Swift reverse executors; fail surprise reverse execution closed; retain typed tool receipts. | **Complete — PR #114** |
| **1** | **Contain model-config corruption** | Refuse unsafe nested-model rewrites, add official nested-TOML fixtures, then choose a structure-preserving ownership boundary. | **Complete — PR #115** |
| **2** | **Typed ACP control spine** | Add a version/capability-aware facade over each existing ACP connection; first methods are models, usage, session metadata, and bounded session updates. | **Complete — PR #116** |
| **3** | **Session truth and recovery** | Consume typed `session/load` replay, reconcile the local presentation cache, and retire private root/child storage reads after a shadow-parity gate. | **Complete — PR #118** |
| **4** | **Official provider and open-weight lane** | Use official provider definitions, resolve the keyless-endpoint credential hazard, and pilot one Keychain-backed auth helper without bundling a model runtime. | **Active** |
| **4A** | **Hard pre-provider budget governor** | Define and prove an official-CLI-owned, atomic worst-case reservation boundary shared by parent, child, and retry sampling before any provider request; keep the app and harness projection-only. | **Nonbillable implementation complete — paid locked** |
| **5** | **Controls behave like controls** | Replace model-prompt control actions where official methods exist; separate cancel, worker cancel, and disconnect semantics. | Locked |
| **6** | **Coordinator simplification** | Split transport/session/projection owners only after authority correction; evaluate workspace/profile process pooling without a default leader daemon. | Locked |

Locked rows are roadmap, not implementation authority. Their exact scope must be
re-audited against the then-current CLI, repository, and merged predecessor.

### Slice 4A authority and hard stop

Jimmy authorized Slice 4A on 2026-08-17 after the Slice 4 paid gate correctly
refused to treat post-response ACP usage polling as an absolute budget. Slice 4A
may inspect and test the pinned official Grok 1.0.5 source, define the smallest
upstream-aligned sampler contract, harden GrokBuild's nonbillable handoff and
typed receipt projection, and add hostile local fixtures. It may not send a
provider request, read a credential value, mutate live Grok configuration,
upgrade the installed CLI, add a proxy or second runtime, or begin Slice 5 or 6.

The target invariant is enforced **before network dispatch** by the CLI runtime:

`settled spend + outstanding worst-case reservations <= campaign ceiling`

Every parent request, child request, retry, and concurrent process participating
in the paid campaign must enter through one atomic durable authority. An
ambiguous dispatch, cancellation, missing usage response, or crash keeps the
full reservation charged until authoritative reconciliation. Swift may authorize
an immutable packet, display typed CLI receipts, and retain Stop as defense in
depth; it may not infer or manufacture the reservation. Paid execution remains
locked until the installed CLI advertises this exact capability and hostile
tests prove the invariant across concurrency, retry, cancellation, and restart.

### Slice 4A nonbillable checkpoint — 2026-08-17

The local fork is pinned to official 1.0.5 source `9fabade`. CLI fork commits
`b1ab29e`, `717b94b`, `2a639d9`, `190e984`, `e78ae89`, and `03a28d4`
implement the nonbillable governor, armed-runtime containment, typed request
receipts, and durable cursor projection. App commits `7f7bfad`, `6619bde`,
`e9a4a4d`, `39dd56c`, `c73469f`, `f373f04`, and `08b95f6` fail closed on route
substitution, activate one immutable packet per CLI process, retain native
read-only acceptance fixtures, and reconcile terminal ledger evidence. The
downstream contract stays under `com.grokbuild/*`; it is never presented as an
upstream `x.ai/*` method.

The CLI checkpoint owns one immutable multi-route campaign manifest and one
durable process-shared ledger. Each allocation binds packet, prompt digest,
model, endpoint digest, API backend, token/call ceilings, maximum serialized
payload bytes, maximum output, and independent bound provenance. Every sampler
dispatch validates the final text-only wire payload and reserves atomically
before provider network. Automatic retries and redirects are disabled while
armed; missing usage, cancellation, stream failure, or process death retains
the worst-case reservation. Hosted search, provider-side Responses history,
multimodal/indirect inputs, memory embeddings, web search, and image/video
generation paths fail closed rather than escape accounting.

GrokBuild remains projection-only. It hashes the final prompt after MCP/file
attachment blocks, securely reads separate private authorization, CLI-manifest,
and shared-ledger files, and requires the exact live CLI capability to match the
campaign ID, 4M ceiling, 1M reserve, 3M spendable ledger, manifest digest, CLI
build, allocation and packet IDs, prompt, route, bound, provenance, containment,
and remaining token/call state. Configured acceptance starts no warm unarmed CLI;
the exact packet contract launches a fresh process and ambient governor variables
are scrubbed. A successful checkpoint now requires the CLI's typed terminal
request records to advance the pre-dispatch ledger cursor through one exact
contiguous reservation range, match route and bounds, remain within each reserved
token amount, settle with exact charges, and reconcile to ACP model-call and token
usage. Stop cancels, drains, queries the still-live generation, and retains a
truthful reserved/ambiguous/unavailable projection before teardown.

Acceptance: full Swift **976/976**; focused ACP **90/90**; Python v2 harness
**22/22**; Rust sampler hard-budget **29/29** at CLI head `03a28d4`; prior armed
shell/agent/pager checks remain retained; both repository diff checks are clean.
Three skeptical reviewers returned **COMMIT** for the exact nonbillable app and
harness tree and **NO-GO** for paid execution. No provider call, credential read,
live config mutation, installed CLI upgrade, or app installation occurred.

Paid execution remains blocked at the first harness branch. The next full Slice
4 activation must install and prove the exact committed fork binary, generate and
independently verify route-specific bound provenance, resolve external-provider
credentials without re-enabling arbitrary auth-helper subprocesses, and replace
or redesign the continuation packets that the current fresh-allocation harness
correctly refuses as a whole. It must then run nonbillable loopback process,
kill/restart/cancel, no-retry, and side-egress acceptance before any provider
Send. The private CLI manifest and ledger are retained after process-zero for
forensic reconciliation; only the app authorization sidecar is removed. Slice 5
and Slice 6 remain locked.

## Slice 0 — Restore CLI execution ownership

### Root cause

GrokBuild advertised ACP client filesystem read/write and terminal support. The
Grok CLI consequently delegated the actual operations back to Swift. Those file
operations and sibling terminal processes did not run beneath the sandbox
installed around the Grok process, while absolute paths were accepted directly.
The implementation contradicted the documented CLI-executor boundary.

### Exact scope

- Advertise `fs.readTextFile = false`, `fs.writeTextFile = false`, and
  `terminal = false` in the initialize packet.
- Remove reverse-ACP filesystem handlers, the Swift terminal manager, and their
  teardown path.
- Return JSON-RPC `-32601 Method not found` for an unexpected client request
  instead of an empty success object.
- Consume plan text from the typed plan interaction request; do not watch a
  CLI-owned plan file through client-side writes.
- Preserve typed Grok-owned tool updates, terminal exit interpretation, run
  artifacts, permissions, and MCP evidence.
- Add a hostile fake-agent contract that attempts both an absolute file write
  and a terminal-launched file creation and proves neither side effect occurs.

### Exclusions

- No CLI upgrade, provider call, billable prompt, model selection, credential
  access, Keychain change, `~/.grok` mutation, session deletion, or user-config
  edit.
- No model TOML repair, typed `x.ai/*` implementation, private-session migration,
  Stop redesign, process pooling, or UI refactor.
- No tag, GitHub release, notarization, write to `origin`, force push, or broad
  cleanup.

### Acceptance and publication

1. Canonical identity and GitHub publication preflight pass.
2. Focused ACP contracts prove false capabilities on the wire, `-32601` responses,
   and zero hostile side effects.
3. `make test`, `git diff --check`, and exact-path review pass.
4. Commit the code-bearing candidate, then run clean `make ship` so installed
   stamp equals candidate HEAD with `dirty=false`, dist/install parity, Team
   `DD2GCQJVB4`, deep/strict signing, and no quarantine.
5. Focused installed-app acceptance confirms launch, canonical build identity,
   ordinary navigation, no provider send, and clean native quit.
6. Push only to `personal`, open a ready PR, verify required CI on the exact head,
   and merge with `--match-head-commit` using the repository's normal method.
7. Fast-forward local `main`, run merged-main `make ship`, confirm local/main and
   `personal/main` parity, then take two process-zero samples. Only then unlock
   Slice 1.

### Candidate receipt — 2026-08-16

Code-bearing candidate `0157d1996c9a595d407267908b48bb1c80823885`
removes the Swift reverse filesystem/terminal implementation and its four
implementation-owned terminal tests. The replacement hostile ACP fixture proves
the exact initialize wire advertises all three execution capabilities as false,
then attempts an absolute `fs/write_text_file` and a `/usr/bin/touch` through
`terminal/create`; both receive JSON-RPC `-32601`, and neither side-effect file
exists. The focused ACP suite passed **76/76** and two clean full runs passed
**903/903**; the count is three lower than the 906-test baseline because four
deleted terminal-manager tests were replaced by the one stronger boundary test.

Candidate `make ship` installed `/Applications/GrokBuild.app` with exact stamp
`0157d1996c9a595d407267908b48bb1c80823885`, `dirty=false`, executable SHA-256
`1d8fc74003279db821b692d4b29afc92bae091730051d035023c11b2b82ad25b`
matching `dist`, Apple Development Team `DD2GCQJVB4`, deep/strict signing, and no
quarantine. Installed Computer Use opened the real app, verified About reported
the exact branch/commit and `grok CLI: 1.0.4 [stable]`, opened the project
sidebar, and retained the canonical `grok-build-desktop` row, composer, and
saved-task choices. Send remained disabled; Resume was not pressed; no provider
prompt, backend process, test session, credential/config change, or cleanup was
created. Native Quit produced two process-zero samples.

PR #114 merged normally as `e6c0925ff847b5f51ff171b7ccf25aef4eaa97ce`.
Merged-main `make ship` passed **903/903**, installed the exact clean merge, and
produced matching dist/install SHA-256
`233a35280244870d3db3bcc2a37b95799088cade7d893506ec68ea9e8c6cef5a`.
Local `main`, `personal/main`, installed identity, signing, and two process-zero
samples reconciled. Slice 0 is complete.

## Slice 1 — Contain model-config corruption

### Root cause and ownership decision

Official Grok 1.0.5 accepts [nested per-model
tables](https://github.com/xai-org/grok-build/blob/9fabadea800fa6e2ed8ec91c4f45f02b7e2504f4/crates/codegen/xai-grok-shell/src/agent/config_model_override_parse.rs#L595-L610)
such as `[model.<id>.extra_headers]` and `[model.<id>.query_params]`, plus
[provider tables and `model_provider`
references](https://github.com/xai-org/grok-build/blob/9fabadea800fa6e2ed8ec91c4f45f02b7e2504f4/crates/codegen/xai-grok-shell/src/agent/model_providers.rs#L830-L862).
GrokBuild's flat text parser previously treated every `model.*` header as a new
model id, then a save removed all such tables and re-emitted flattened bogus
entries.

Slice 1 chooses a fail-closed ownership boundary. GrokBuild may continue to
manage exact flat `[model.<id>]` tables and `[models].default`; advanced model
and provider structures remain CLI-owned. Supporting those structures later
requires a semantic TOML representation or an official CLI/ACP mutation
contract, not more destructive string rewriting.

### Exact scope

- Parse only exact flat model tables as GrokBuild-managed models; nested tables
  must never appear as bogus model rows.
- Detect nested model tables, `model_providers` tables, provider references, and
  unrecognized/alternate table spellings and root dotted model keys
  conservatively.
- Recheck write safety inside the locked `GrokConfigRepository.update` closure
  before any replacement or model-metadata save.
- Best-effort refuse a stale replacement when an external CLI/TUI writer changes
  the source bytes before the repository's final pre-rename comparison; this is
  not claimed to be a cross-process transaction or lock.
- Make the app-launch legacy config migration stand down before config or
  sidecar changes when advanced model structures are present.
- Surface a visible read-only notice and block model, provider, default-model,
  credential-projection, and removal writes while advanced configuration exists.
- Hydrate existing provider credentials read-only in that state, and roll back
  provider/Keychain changes if a late authoritative config check refuses.
- Pin official 1.0.5-shaped fixtures and prove every refused save preserves the
  original config bytes exactly; retain writable quoted dotted model ids.
- Update architecture, README, campaign, and canonical outstanding state.

### Slice 4 paid-gate checkpoint — 2026-08-17

The v2 harness is implemented as a fail-closed, append-only acceptance ledger,
but **paid execution remains locked**. Official ACP usage is reported only after
a model response settles, so polling `x.ai/session/usage` and invoking Stop is a
reactive circuit breaker, not proof that aggregate provider billing cannot cross
Jimmy's absolute 4,000,000-token ceiling. The app retains that reactive guard as
defense in depth; `preflight_v2.require_absolute_ceiling_support()` refuses every
paid packet before app launch until an official per-request bound or another
mathematically defensible worst-case bound exists. No paid Send has occurred and
the requested paid test is blocked, not waived or accepted.

The frozen harness records three fsync'd rows per packet—reservation, full typed
terminal evidence, and exact local cleanup—so route/usage/cost evidence survives
rejection and cleanup crashes. It pins the exact workspace, prompt hash, single
Send actuator, app-launch epoch, official layered-config receipt, helper identity,
model route, tool/worker topology, response continuity term, and backend/tab
identities. Legacy v1 billable execution is retired. Unlocking still requires a
clean exact-head signed install, CLI 1.0.5+, official provider migration, an exact
launch-policy contract, and a hard ceiling mechanism; Slice 5 remains locked.

### Exclusions

- No semantic TOML editor, provider-schema adoption, config migration, CLI
  upgrade, ACP control method, private-session work, provider call, billable
  prompt, Keychain access, or mutation of the user's live `~/.grok` config.
- No Slice 2 implementation, tag, GitHub release, notarization, write to
  `origin`, force push, or broad cleanup.

### Acceptance and publication

1. Official-shaped focused fixtures pass and blocked saves preserve exact bytes.
2. `make test`, `git diff --check`, and exact-path review pass.
3. Commit the code-bearing candidate; run clean `make ship` and reconcile exact
   installed identity, executable parity, signing, and quarantine.
4. Installed Computer Use verifies Models remains readable and ordinary flat
   configuration remains usable without changing config, credentials, or
   starting a provider session.
5. Push only to `personal`, open a ready PR, verify exact-head required CI, and
   merge normally with `--match-head-commit`.
6. Fast-forward local `main`, run merged-main `make ship`, reconcile parity, and
   take two process-zero samples. Only then may Slice 2 be considered.

### Candidate receipt — 2026-08-17

Code-bearing candidate `53328c1d5559002e06afc909cecd415de6cc9999`
contains Slice 1. Two independent Sol Medium reviewers returned **COMMIT** after
the final exact-diff pass. Focused config/settings contracts passed **101/101**;
the clean full suite and candidate `make ship` each passed **914/914**.

Candidate `make ship` installed exact clean stamp `53328c1d`, with matching
dist/install executable SHA-256
`3289d021dee6075ba6119adc55272b91a03b4e83b60871b47f7caed749d4fe8c`,
Team `DD2GCQJVB4`, deep/strict signing, and no quarantine. Installed Computer
Use verified the real `/Applications/GrokBuild.app` Models pane, ordinary flat
configuration presentation, disabled unchanged Apply, and App identity
`codex/official-runtime-s1-model-config-safety @ 53328c1d`. Native Quit produced
process-zero samples at `2026-08-17T04:05:06-0400` and
`2026-08-17T04:05:14-0400`.

No prompt, provider validation/fetch, backend process, credential read/write,
live `~/.grok/config.toml` mutation, or CLI upgrade occurred. PR #115 merged
normally as `f00b99216364cbedb47de221073cf3736d8012ca`. Merged-main `make ship`
passed **914/914** and installed that exact clean merge with matching dist/install
SHA-256 `5bd4f7412b1e2dd947a84808bd2ae76d104f167285db21ba686d59b600561043`,
Team `DD2GCQJVB4`, deep/strict signing, and no quarantine. Local `main`,
`personal/main`, and installed identity reconciled; crash-recovery process-zero
samples at `2026-08-17T08:38:07-0400` and `2026-08-17T08:38:12-0400` confirmed
the closeout. Installed CLI authority remains
`grok 1.0.4 (d846eb93d94d) [stable]`. Slice 1 is complete.

## Slice 2 — Typed ACP control spine

### Ownership decision

Slice 2 adds no second process or runtime. Each `GrokProcess` uses its existing
per-tab stdio connection for read-only official controls. The exact
`initialize._meta.agentVersion` and one bounded method probe determine whether
an `x.ai/*` method exists for that process generation; a missing version or a
known Grok version below 1.0.5 never puts those calls on the wire. A new
generation resets every cached capability instead of inheriting truth from an
older CLI process.

The first typed contracts follow official 1.0.5 source:
`x.ai/models/list`, `x.ai/session/usage`, `x.ai/session/info`, and bounded
`x.ai/session/updates`. Models and session info unwrap xAI's extension-result
envelope; usage and update pages retain their direct response shapes. Unknown,
method-not-found, malformed, timed-out, and stale-generation outcomes remain
distinct failures rather than empty success.

### Exact scope

- Capture and semantically compare the agent version from the live initialize
  packet; cache support per exact method and process generation.
- Add typed, credential-free models for the catalog, cumulative session usage,
  resident-session metadata, and persisted update envelopes.
- Cap every session-update page at 512 rows. Child receipt reconciliation may
  walk at most four 256-row tail pages and keeps child prose excluded.
- Prefer official `x.ai/session/updates` for terminal child tool receipts on the
  current connection. Retain the existing private child-ledger reader only as a
  clearly named compatibility fallback for installed Grok 1.0.4; Slice 3 owns
  parity acceptance and removal.
- If initialize has no model catalog on 1.0.5 or newer, use the official model
  list on the same connection without making launch depend on an extension.
- Pin exact fake-agent wire fixtures for supported 1.0.5, known-old 1.0.4,
  method-not-found caching, typed response shapes, and request bounds.
- Update architecture, README, campaign, and canonical outstanding state.

### Exclusions

- No CLI upgrade, provider/model call, billable prompt, authentication,
  credential/Keychain access, config mutation, session deletion, or user-state
  cleanup.
- No `session/load` replay consumption, root history recovery, or removal of
  private storage fallbacks; those are Slice 3.
- No control mutations, task/fork/worktree redesign, second ACP process,
  persistent leader/control daemon, coordinator split, or UI redesign.
- No Slice 3 implementation, tag, GitHub release, notarization, write to
  `origin`, force push, or broad cleanup.

### Acceptance and publication

1. Focused fake-agent contracts prove all four methods share the existing pipe,
   known-old calls stay off wire, method-not-found is probed once, update pages
   are bounded, and child receipts exclude prose.
2. `make test`, `git diff --check`, and exact-path review pass.
3. Commit the code-bearing candidate; run clean `make ship` and reconcile exact
   installed identity, executable parity, signing, and quarantine.
4. Installed Computer Use verifies ordinary launch/navigation and exact build
   identity without Send, Resume, provider validation, or CLI upgrade.
5. Push only to `personal`, open a ready PR, verify exact-head required CI, and
   merge normally with `--match-head-commit`.
6. Fast-forward local `main`, run merged-main `make ship`, reconcile parity, and
   take two process-zero samples. Only then may Slice 3 be considered.

### Candidate receipt

Code-bearing candidate `950bfc26a5c7b219ea96666917a8d3711f301ff3`
implements the exact Slice 2 boundary. Focused contracts passed 10/10 typed
control-plane, 76/76 ACP client, and 5/5 activity-parity tests. Clean `make test`
and candidate `make ship` each passed **924/924**; `git diff --check` passed.

`make ship` installed the exact clean candidate in `/Applications/GrokBuild.app`.
The dist and installed executables share SHA-256
`d67593eba4b16476f529e51ce561fc36890d34989f1eefd12027e735a5e404b2`;
the bundle carries Team `DD2GCQJVB4`, passes deep/strict signing, and has no
quarantine attribute. Installed Computer Use verified About identity
`0.1.22 Personal` on branch `codex/official-runtime-s2-typed-acp-control` at
`950bfc26`, then ordinary Settings navigation. It did not select Send, Resume,
provider validation, or CLI update, and no Grok backend/helper process started.
Installed CLI authority remains `grok 1.0.4 (d846eb93d94d) [stable]`.

Native Quit produced process-zero samples at `2026-08-17T09:12:06-0400` and
`2026-08-17T09:12:17-0400`. No prompt, provider/model call, billable work,
credential access, config mutation, session recovery, CLI upgrade, or Slice 3
implementation occurred.

PR #116 passed required **Test and Build App** on exact head
`791b6fd8e298ba2ba5f557ca5b27590906bfe9c2` and merged normally as
`a615fed8f5ffd0173bfd66a306e73ddf4fb419c0`. Local `main == personal/main`
reconciled cleanly. Merged-main `make ship` passed **924/924** and installed that
exact clean merge; dist/install SHA-256 is
`afb0437c83f96e94c28fc9baeb81b7d01ba214587508a04236eca09293fde9ab`,
with Team `DD2GCQJVB4`, deep/strict signing, and no quarantine. Installed
Computer Use verified About identity `0.1.22 Personal • main @ a615fed8` without
starting or resuming a backend. Native Quit produced process-zero samples at
`2026-08-17T09:26:32-0400` and `2026-08-17T09:26:41-0400`.

Slice 2 is complete. Jimmy explicitly authorized Slice 3 on 2026-08-17; its
fresh scope audit and execution contract follow. Slice 4 remains locked.

## Slice 3 — Session truth and recovery

### Ownership decision

Jimmy authorized Slice 3 on 2026-08-17. Grok CLI replay is backend-history
authority; GrokBuild's owner-only transcript remains the durable offline
presentation cache. A resumed backend is usable only after typed `session/load`
replay is bound to the exact local tab, backend ID, and process generation and
passes the existing keyed root-conversation comparison. Historical replay never
re-drives live thinking, tools, workers, permissions, or completion state.

The Release app owns no private CLI session reader. The former
`chat_history.jsonl` importer remains DEBUG-only for the one shadow-parity gate,
and the child `updates.jsonl` fallback is deleted. Installed 1.0.4 therefore
keeps authoritative parent lifecycle summaries but reports detailed child
receipts and official candidate review unavailable.

### Exact scope

- Capture standard and official xAI replay notifications only while one exact
  `session/load` is in flight; consume the buffer once after the response.
- Project only root user and assistant message chunks. Exclude host-turn context,
  thought, tools, subagents, permissions, terminal state, and completion updates.
- Verify exact/prefix/divergent relationships after load, then reconcile only a
  verified local presentation cache. A mismatch leaves the exact connection
  unsendable and available only for official read-only review; Continue as New
  and Relink tear it down before rebinding.
- Preserve one-submit behavior: when Send discovers a replay mismatch, that same
  frozen intent records Continue as New, creates a successor, and dispatches only
  to the successor.
- Make selection/offline browsing app-local only. Remove restore-time and
  completion-time private backend-tail reads.
- Use standard `session/list` plus bounded official `x.ai/session/updates` for
  explicit candidate review/relink on supporting CLIs. Candidate review is capped
  at 50 entries, five inventory pages, one 512-update page per candidate, and a
  five-second candidate-start window. Relink re-fetches under a 4,096-update
  fail-closed cap.
- Delete the private child-ledger compatibility reader. Unsupported, malformed,
  timed-out, stale, or known-old official methods yield unavailable evidence.
- Keep the legacy private root parser only under `#if DEBUG`, prove typed replay
  shadow parity on a pinned fixture, and prove the Release binary contains neither
  private reader symbol nor private session path string.
- Update architecture, README, campaign, and canonical outstanding state.

### Exclusions

- No CLI upgrade, provider/model call, prompt dispatch for acceptance,
  authentication, Keychain/config mutation, session deletion, or user-state
  cleanup.
- No control mutations, provider/open-weight work, task/fork/worktree redesign,
  second ACP process, persistent control daemon, or coordinator split.
- No Slice 4 implementation, tag, GitHub release, notarization, write to
  `origin`, force push, branch deletion, or broad cleanup.

### Acceptance and publication

1. Fake-agent contracts prove typed replay capture, live-stream isolation,
   exact/prefix reconciliation, divergence refusal, and same-submit safe fork.
2. Shadow parity, standard list, bounded update, known-old, method-not-found, and
   child-detail-unavailable contracts pass. Release compilation proves the
   private readers are absent.
3. `make test`, `git diff --check`, and exact-path review pass.
4. Commit the code-bearing candidate; run clean `make ship` and reconcile exact
   installed identity, executable parity, signing, and quarantine.
5. Installed Computer Use loads one existing saved backend without a prompt,
   verifies the local transcript is not duplicated, and closes with process zero.
6. Push only to `personal`, open a ready PR, verify exact-head required CI, and
   merge normally with `--match-head-commit`.
7. Fast-forward local `main`, run merged-main `make ship`, reconcile parity, and
   take two process-zero samples. Only then may Slice 3 be complete; Slice 4
   remains locked until separately authorized.

### Candidate receipt

Focused typed replay/control/recovery/reconnect contracts pass 25/25. Full
`make test` passes 929/929. Production `swift build -c release` passes; symbol
and string inspection finds no `GrokSessionTranscriptImporter`, private child
reader, `chat_history.jsonl`, `updates.jsonl`, or `.grok/sessions` in the
Release binary. Code-bearing candidate `e3b290475de83a1dd3f95b810307d4b5e3fa691f`
completed clean `make ship` at 929/929. The installed executable matches dist at
SHA-256 `b984f66d…619ee`, Team `DD2GCQJVB4`, deep/strict signing, and no
quarantine. Nonbillable installed Computer Use resumed one existing saved backend
without a prompt; its one existing user turn remained singular after typed replay,
the live model confirmed, and About reported
`0.1.22 Personal • codex/official-runtime-s3-session-truth @ e3b29047` with
`grok CLI: 1.0.4 [stable]`. Native Quit produced process-zero samples at
`2026-08-17T11:42:41-0400` and `2026-08-17T11:42:56-0400`.

PR #118 passed required **Test and Build App** on exact head
`a88cd9898f1ab386d39649ffae48e7809a613f59` and merged normally with the
match-head guard as code-bearing baseline
`d774b365f9281cef6c8d53e6b2746a7f9a9c52e1`. Clean merged-main `make ship`
passed 929/929 and installed that exact merge with matching dist/install SHA-256
`2f5f95d8…e03e4`, Team `DD2GCQJVB4`, deep/strict signing, and no quarantine.
Installed Computer Use verified `0.1.22 Personal • main @ d774b365` with CLI
`1.0.4 [stable]` without sending or resuming another prompt. Native Quit produced
process-zero samples at `2026-08-17T11:53:57-0400` and
`2026-08-17T11:54:14-0400`. Slice 3 is complete. Jimmy authorized Slice 4 on
2026-08-17; its fresh scope audit and execution contract follow.

## Slice 4 — Official provider and open-weight lane

### Ownership decision

Grok CLI already owns provider inheritance, credential precedence, auth-helper
execution and caching, request protocols, model eligibility, model execution,
tools, subagents, sandboxing, and fallback behavior. GrokBuild may provide
onboarding templates, a Keychain-backed credential helper, lossless edits to
its own trusted user-config nodes, and typed presentation of the official ACP
catalog and route receipts. It must not become a provider runtime.

The former flat projection duplicated each provider URL and credential into
every `[model.<id>]` table. A keyless flat custom endpoint can therefore inherit
the signed-in xAI session bearer; clearing a provider credential can also leave
an old model copy that later rehydrates Keychain. Official
`[model_providers.<id>]` inheritance plus a declared helper is the fail-closed
boundary. Every GrokBuild-managed custom endpoint, including loopback, must use
that boundary so absence or failure of provider auth never falls back to xAI
session auth.

The effective model party list likewise belongs to the CLI. Provider `/models`
fetches remain optional setup/catalog evidence, but initial ACP catalog state
and generation-bound `x.ai/models/update` notifications own live membership.
Local metadata may decorate an advertised model; it may not add back a model
the CLI hid, rejected, or removed.

### Exact scope

- Add a spec-validating, syntax-preserving TOML document mutation boundary.
  It may replace only explicitly GrokBuild-owned canonical provider/model nodes;
  unrelated comments, ordering, unknown fields, partial overrides, nested tables,
  and user-authored provider/auth definitions remain byte-for-byte untouched.
- Immediately fail closed on flat partial model overrides or official fields the
  current editor does not own. Preserve the atomic compare-before-rename boundary
  and validate every candidate with bounded `grok inspect --json`; a parse or
  app-owned warning rolls back config and provider metadata.
- Migrate only exact models already linked to a GrokBuild provider. Ambiguous or
  user-authored definitions remain untouched and read-only.
- Emit official `[model_providers.<id>]` definitions and
  `model_provider = "<id>"` references. Stop copying provider credentials into
  `[model.<id>].api_key`.
- Pilot OpenRouter through one dedicated signed helper. The helper accepts one
  exact provider ID as a direct argument, reads only service
  `com.grokbuild.provider-credential` from macOS Keychain, writes only the token
  to stdout, and emits credential-free failures. Grok CLI owns timeout, cache,
  refresh, and request use.
- Make Disconnect remove the exact Keychain credential and any recognized legacy
  inline copies transactionally. An explicit disconnect must never be reimported
  on reload; provider/model definitions remain visible as credential unavailable.
- Give `x.ai/models/list` its official method-specific 1.0.4 floor. Consume both
  `x.ai/models/update` and `_x.ai/models/update` as complete generation-bound
  catalog replacements. A stale notification cannot change the picker or a
  historical confirmed model receipt.
- Once ACP has supplied a catalog, stop unioning locally parsed models into live
  membership. Unknown official routes disclose provider detail unavailable
  instead of being labeled native xAI.
- Replace the paid acceptance path with a v2 allowlisted ledger: no private
  `~/.grok/sessions` reads or human `grok sessions search`, exactly one Send
  actuator, attempt-start and terminal-failure rows, observed typed route/model
  evidence, per-packet token/call allocations, reserve accounting, cost
  reconciliation, and exact run-created-tab cleanup.
- Run nonbillable hostile provider/helper/config/catalog fixtures first. The paid
  packet may plan at most 3,000,000 tokens, retaining a 1,000,000-token emergency
  reserve beneath Jimmy's absolute 4,000,000-token ceiling. There are no retries;
  stop early as soon as the contract is settled or any route, receipt, cost,
  usage, helper, process, or config invariant fails.
- Update architecture, README, campaign, and canonical outstanding state.

### Exclusions

- No CLI upgrade, second model runtime, direct completion client, app-side
  provider fallback, persistent control daemon, or generic Swift inference layer.
- No ACP bearer-token export, secret logging, helper stdout capture, environment
  credential export, or response-body retention.
- No automatic adoption or rewrite of arbitrary user-authored official provider,
  auth-provider, nested model, or partial override structures.
- No claim that a provider `/models` fetch proves inference, that OpenRouter's
  downstream serving provider is observed, or that token volume is model quality.
- No Slice 5 control mutations, task/fork/worktree redesign, coordinator split,
  tag, GitHub release, notarization, write to `origin`, force push, branch
  deletion, broad session cleanup, or deletion of protected user history.

### Acceptance and publication

1. Hostile fixtures prove flat keyless routes cannot dispatch, provider-bound
   keyless/helper failures never receive an xAI sentinel, Disconnect cannot
   resurrect a key, and helper errors contain no secret material.
2. TOML fixtures prove lossless preservation of comments, partial overrides,
   unknown fields, nested tables, quoted/dotted IDs, user providers, concurrent
   replacement, inspect-warning rollback, and exact app-owned migration.
3. ACP fixtures prove 1.0.4 model-list availability, both live update spellings,
   complete add/remove/reorder replacement, stale-generation rejection, hidden
   model exclusion, and no local membership reinjection.
4. Harness-v2 fixtures prove reserve refusal, one-attempt Send, failure ledgering,
   route/model/model-usage mismatch stops, bounded live Stop, cost labels,
   allowlist redaction, and exact cleanup without private storage.
5. Focused tests, `make test`, `git diff --check`, exact-path review, and a clean
   candidate `make ship` pass before any paid Send.
6. Installed nonbillable acceptance verifies exact identity, official catalog
   visibility, helper/config presentation, and no secret/config drift. The frozen
   paid packet remains prohibited until the absolute-ceiling gate above has a
   provable implementation; reactive usage polling alone cannot unlock it.
7. Capture exact route, effective/provider-facing model, token split, model calls,
   provider cost or explicit unavailable state, frozen price estimate, tool/worker
   receipts, config hashes, and attempt/cleanup receipts. Preserve failures.
8. Push only to `personal`, open a ready PR, verify required CI on the exact head,
   and merge normally with `--match-head-commit`.
9. Fast-forward local `main`, run merged-main `make ship`, reconcile installed
   identity/parity/signing, close only exact run-created local tabs, and take two
   process-zero samples. Only then may Slice 4 be complete; Slice 5 remains locked.
