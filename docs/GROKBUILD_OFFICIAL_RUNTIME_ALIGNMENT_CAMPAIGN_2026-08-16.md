# GrokBuild Official Runtime Alignment Campaign — 2026-08-16

Status: **active; Slice 2 authorized.** Jimmy authorized a rigorous merge-per-slice
campaign on 2026-08-16. Every slice gets its own branch, explicit commits, ready
pull request, exact-head required checks, normal merge, merged-main installation,
and process-zero closeout before the next slice begins.

Current baseline: clean `main == personal/main` at
`f00b99216364cbedb47de221073cf3736d8012ca` (PR #115). The installed app is
the same clean merged-main source, and the dist and installed executables match
byte-for-byte. Installed CLI authority is `grok 1.0.4 (d846eb93d94d) [stable]`.
Official 1.0.5 source informs this campaign, but no CLI upgrade is authorized by
Slice 1.

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
| **2** | **Typed ACP control spine** | Add a version/capability-aware facade over each existing ACP connection; first methods are models, usage, session metadata, and bounded session updates. | **Active** |
| **3** | **Session truth and recovery** | Consume typed `session/load` replay, reconcile the local presentation cache, and retire private root/child storage reads after a shadow-parity gate. | Locked |
| **4** | **Official provider and open-weight lane** | Use official provider definitions, resolve the keyless-endpoint credential hazard, and pilot one Keychain-backed auth helper without bundling a model runtime. | Locked |
| **5** | **Controls behave like controls** | Replace model-prompt control actions where official methods exist; separate cancel, worker cancel, and disconnect semantics. | Locked |
| **6** | **Coordinator simplification** | Split transport/session/projection owners only after authority correction; evaluate workspace/profile process pooling without a default leader daemon. | Locked |

Locked rows are roadmap, not implementation authority. Their exact scope must be
re-audited against the then-current CLI, repository, and merged predecessor.

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
implementation occurred. Publication and merged-main closeout remain.
