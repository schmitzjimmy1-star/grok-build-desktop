# GrokBuild Slice 4 Activation Campaign — 2026-08-17

Status: **Slices 4B.0 through 4B.6 accepted; paid activation locked.** This document is the authority for completing
the official-provider and open-weight lane after the nonbillable Slice 4A hard-budget checkpoint. It
does not authorize a provider request, credential-value read, live Grok config
mutation, installed-CLI replacement, tag, release, or Slice 5 work.

Jimmy raised the eventual testing authority on 2026-08-17 to an absolute
**10,000,000-token ceiling**. On 2026-08-18 he raised that ceiling to
**20,000,000 tokens**. That is a ceiling, not a target. The versioned v3 policy
is 20M/19M/1M: the final immutable campaign may plan at most 19,000,000 tokens
and must retain 1,000,000 tokens as unreachable reserve. The current 4M/3M/1M
implementation remains authoritative until a later 4B slice versions, tests, and
merges the larger policy; the new ceiling does not unlock the paid branch today.

## Starting truth

The app repository is clean at merge `2559a43d74e4b1f8453edcaca6692f4016a39b4c`
(PR #126). The installed app matches that merged-main build. Its installed
runtime remains official `grok 1.0.4 (d846eb93d94d) [stable]`.

The hard-budget CLI fork is published and merged on Jimmy's `personal/main` at
`7d8d04c7d48369f6ebb5c4b31a37e0ac20286ab1`, with code-bearing candidate
source `003f95530228ffb7f7867c9365fc7a2c86dfd229` and docs-only final source
`f96892e075acfa3ef13a9563a5f7c7a0178007ff`. `origin` fetch remains the
official `xai-org/grok-build` repository while its push URL is the deliberately
unsupported `no_push://xai-org/grok-build` sentinel; `personal` is Jimmy's fork.
Two independent ad-hoc candidate artifacts and provenance manifests were built
and retained as 4B.0 evidence. Neither candidate was installed or exercised
through the installed app, and neither is armable under the signed-runtime
contract.

The paid harness refuses at its first branch before runtime discovery, app
launch, authority creation, or provider work. It separately refuses the whole
current manifest because the retained three-turn continuation group cannot
satisfy one immutable allocation per fresh CLI process. Zero Slice 4 paid
packets have run.

## Governing ownership

GrokBuild remains a native presentation, consent, Keychain, and evidence shell.
It may freeze the final prompt and attachments, select a configured model, read
one explicitly selected Keychain item, launch one exact candidate binary, and
reject any capability or receipt mismatch.

Grok CLI remains the sole runtime owner of config and provider resolution,
endpoint and auth-header construction, request serialization, transport,
redirect and retry policy, sampler admission, durable token reservation,
sessions, tools, workers, and response handling. Swift must not grow a second
provider client, config resolver, request serializer, fallback chain, or tool
executor.

The following are already provided by the official CLI/ACP surface and stay out
of GrokBuild ownership: `session/load`, model catalog membership, model
selection, provider inheritance, tools, subagents, sandboxing, session usage,
and session metadata. The fork adds only the downstream `com.grokbuild/*`
budget and receipt contract required to make paid acceptance mathematically
bounded.

## Threat model and non-negotiable invariants

1. The exact executable inspected by preflight is the executable launched by
   the app. Path, SHA-256, architecture, signing identity, fork commit, and ACP
   `cliBuild` must agree immediately before process creation.
2. The official CLI remains untouched. A candidate lives in an owner-private,
   digest-addressed GrokBuild runtime directory and is selected only by an
   authenticated acceptance contract. Ambient `PATH` and `GROK_CLI_PATH` can
   never substitute it while armed.
3. Every provider dispatch reserves from one immutable campaign ledger before
   network. The target activation equation is:

   `settled tokens + outstanding worst-case reservations <= 19,000,000`

   The remaining 1,000,000 tokens beneath Jimmy's absolute 20,000,000-token
   ceiling are unreachable reserve. The current checkpoint's exact 4M/3M/1M
   contract must fail closed until the versioned 20M/19M/1M authority is present
   end to end.
4. One packet owns one immutable allocation and one fresh CLI process. A later
   continuation turn uses a different allocation and fresh process, then loads
   the exact existing backend through standard `session/load`.
5. No executable auth helper runs while the governor is armed. A credential may
   cross into the exact CLI process only through a one-shot, nonpersistent,
   non-environment, non-argv materialization boundary proven with fake sentinel
   data before any real Keychain read.
6. Bound provenance is a canonical, versioned, credential-free structure
   generated from the CLI's actual resolved route and final serializer limits.
   Swift and Python independently canonicalize, hash, and validate the CLI
   projection against immutable route expectations; they do not recreate CLI
   config resolution. An opaque caller-supplied hash is insufficient.
7. Missing terminal usage, cancellation, stream failure, ambiguous dispatch,
   kill, or crash retains the full reservation. No retry follows a failure.
8. A successful packet requires exact agreement among the app checkpoint, ACP
   completion and usage, CLI request receipts, durable ledger cursors, route,
   model, token calls, cost state, and cleanup receipt.
9. OpenRouter is a brokered route. GrokBuild may prove the configured broker,
   provider-facing model, and observed ACP model; it may not claim the
   downstream serving provider was observed.
10. Slice 5 remains locked until Slice 4 is merged, installed, accepted,
    reconciled, and closed with process-zero.

## Merge-per-slice campaign

Each row gets its own short-lived branch, intended-path commits, skeptical
review, ready PR, exact-head required checks, normal match-head merge,
merged-main verification, and process-zero closeout. A row cannot borrow green
evidence from a predecessor or begin while its predecessor remains unmerged.

| Slice | Job | Writes allowed | Exit gate |
|---|---|---|---|
| **4B.0** | **Fork provenance and reproducible candidate contract** | CLI publication metadata/build tooling and campaign docs only | `origin` fetch remains upstream while its push URL is deliberately invalid; Jimmy-owned `personal` is the only publication remote; upstream range-diff reviewed; source/base/toolchain/lockfile/build/binary/signature manifest schema proven; no install |
| **4B.1** | **Pinned runtime selection and rollback** | App launch contract, unified resolver, harness/preflight candidate identity | Hostile tests prove `PATH`, ambient `GROK_CLI_PATH`, path swap, hash drift, wrong signature, and inspected/launched divergence all fail before ACP spawn; official CLI untouched |
| **4B.2** | **Credential materialization feasibility and contract** | Fake-sentinel transport spike and non-secret shared schema only | The real armed `posix_spawn` path proves one bounded fake transfer to a compiled cooperative receiver; receiver FD is closed before its nested exec and fake bytes are absent from argv/env/fixture files/stdout/stderr. This is not official-CLI, raw-fork, zeroization, provider, or Keychain proof; those remain 4B.3 gates. |
| **4B.3** | **Native armed credential, bound provenance, and campaign-policy v3** | CLI credential consumer, Swift materializer, canonical provenance producer/verifiers, typed capability, versioned 20M/19M/1M authority | Exact managed-provider/config binding, route TOCTOU refusal, helper paths still disabled, fake credential loopback, canonical route/bound equality in Rust/Swift/Python, old/new policy mismatch refusal; ordinary unarmed helper behavior unchanged |
| **4B.4** | **Fresh-process continuation contract** | Harness schema/evaluator/driver and app lazy-load choreography | Legacy continuation rejected at schema level; T1 new plus T2/T3 fresh-process `session/load` use three allocations, one backend, one ledger, no `session/resume`, no load-time prompt, no stale fallback, cleanup only after the group |
| **4B.5** | **Nonbillable staged-candidate lifecycle and containment** | Test-only loopback provider, process driver, receipt/cleanup fixtures | Exact staged, noninstalled candidate survives normal, Stop, cancel, kill, restart, stream failure, missing usage, repeated provider correlation, redirect, and call-ceiling tests; foreign egress/helper/retry count is zero; authority retained honestly |
| **4B.6** | **Signed candidate install and installed nonbillable acceptance** | Digest-addressed owner-private candidate runtime and rollback receipt | Build/sign/copy atomicity, architecture/quarantine/signature/hash parity, installed app launches that exact candidate, then reruns the complete 4B.5 hostile matrix; clean rollback, full suites, two process-zero samples |
| **4C** | **Bounded paid matrix** | Provider Sends and exact run-created acceptance artifacts only | Separately unlocked after three skeptical reviewers approve 4B.6; stop on first mismatch or sufficiency; planned spend never exceeds 19M and absolute authority remains 20M |
| **4D** | **Slice 4 closeout** | Evidence docs, app publication, narrowly owned cleanup | Exact-head CI, normal merge, merged-main ship/install, paid reconciliation or explicit retained failure, exact tab cleanup, two process-zero samples; Slice 5 still locked |

## Slice 4B.0 — exact first authority

Slice 4B.0 is accepted. Jimmy explicitly authorized sequential execution of
4B.1, then 4B.2, then 4B.3 on 2026-08-18. Merge-per-slice remains mandatory:
4B.1 and 4B.2 are accepted. 4B.3 T5 merged as PR #136. 4B.4 merged as PR #137
(`90782f2`). **4B.5 is accepted** as merge `324ff89` (PR #139) against signed pager
`f434fa4f…933b` / `1.0.5 (8226242)`. **4B.6 is accepted** as merge `29c064f`
(PR #140). Hostile `setsid`/tool-tree CI leftover is merged as CLI PR #7
`7e9f1ade576df903652b150d634ca634e5180bc4` after `candidate-contract` run
`32310906969` (`hard_budget_receiver_closes_fd_before_raw_fork_and_setsid_descendant`
on the pager-bin `hard_budget` filter). Darwin post-enrollment `setsid()` remains
the known 4B.2 limit. Do not rebuild the pager. Paid activation remains locked.

### Scope

- Preserve the clean `03a28d4` fork with an immutable backup ref before replay.
- Keep `origin` pointed at `xai-org/grok-build` and read-only. Publish through a
  clearly named `personal` remote owned by `schmitzjimmy1-star`; do not force,
  mirror, delete, or rewrite upstream history. Preserve the exact upstream fetch
  URL, replace `origin`'s push URL with a deliberately unsupported sentinel such
  as `no_push://xai-org/grok-build`, and prove an ordinary `git push origin`
  refuses locally before any publication. Record both credential-free URLs.
- Fetch and record the exact upstream head, then produce a range-diff from the
  official 1.0.5 base through the replayed fork. Any overlap with sampler,
  session, auth, ACP, or containment code triggers a new source audit.
- Add a machine-readable candidate provenance schema containing official base,
  upstream replay base, fork source SHA, `Cargo.lock` digest, Rust/Cargo versions,
  target triple, architecture, exact `release-dist` command, binary SHA-256 and
  size, signing state, and the expected `VERSION_WITH_COMMIT`/ACP `cliBuild`.
- Add deterministic build/inspection commands and fixture tests. The artifact
  may remain in a build or staging directory; it may not replace or shadow the
  installed official CLI.
- Update this campaign and `OUTSTANDING.md` with actual receipts, not projected
  success.

### Acceptance

- Both repositories begin and end clean except intended 4B.0 paths.
- The replay/range-diff is reviewed against both `9fabade` and current upstream.
- CLI focused hard-budget, armed containment, and receipt suites pass on the
  final source head; `cargo fmt --check`, `cargo check`, and `git diff --check`
  pass.
- Two independently generated candidate manifests agree byte-for-byte on all
  source/build identity fields.
- A hostile fixture with a substituted binary or mismatched commit/build string
  fails candidate verification.
- `git remote get-url origin` resolves only the official upstream for fetch,
  `git remote get-url --push origin` resolves only the disabled sentinel,
  `personal` resolves only to Jimmy's fork, and the local refusal test proves
  upstream push is mechanically unavailable.
- No app launch, installed CLI mutation, live config read/write, Keychain value
  read, provider request, tag, release, or paid authority occurs.

### Hard stop

Do not begin 4B.1 until 4B.0 is published, reviewed, merged, and the final fork
source and candidate-manifest schema have stable commit IDs. Do not smuggle
runtime selection into the provenance slice because it is "just one field."
That is how tires leave the vehicle at highway speed.

### 4B.0 receipt — 2026-08-18

- CLI PR [#1](https://github.com/schmitzjimmy1-star/grok-build/pull/1)
  passed exact-head `candidate-contract` runs `32104684963` and `32104688174`,
  then merged normally as
  `7d8d04c7d48369f6ebb5c4b31a37e0ac20286ab1`. The code-bearing candidate
  source is `003f95530228ffb7f7867c9365fc7a2c86dfd229`; the docs-only final
  head is `f96892e075acfa3ef13a9563a5f7c7a0178007ff`.
- Independent candidate A binds binary SHA-256
  `bafcef763d23a4ec99ec7ae14c9fd49a8655d0099f9513817d6040d21162bff5`
  and manifest SHA-256
  `771473e1bf970bc75305998ed181456b3283f9fba611b8f22e0dca6a80b0eb82`.
  Candidate B binds binary SHA-256
  `4763acd631b927b71cfa8594863fc19e9bb6873f7757ce7c7903eb3993b57287`
  and manifest SHA-256
  `dae8c7ad444ea5d2ce726cbb84f9fdfba9c471772126b9ec1521bb0dc3443bda`.
  Both are 147,981,040-byte arm64 ad-hoc artifacts reporting
  `1.0.5 (003f955)`.
- The canonical `{source, toolchain, build}` identity projection from the two
  independently generated manifests is byte-identical at SHA-256
  `91a098b999d5f69c24efafe30d8096e2dfc0aad584d7b03d8fcc469e7ed15feb`.
  Whole-binary bytes intentionally are not claimed reproducible: retained
  upstream `cryptify::flow_stmt!` expansion uses randomized compile-time dummy
  control flow, and schema v1 does not bind the Xcode SDK/linker. Each manifest
  instead binds its own exact binary, size, architecture, build string, and
  observed signing state. Candidate and manifest pieces may never be mixed.
- The focused provenance suite passed 19/19 locally; the sampler hard-budget
  suite passed 29/29 locally; both exact-head GitHub runs also passed candidate
  provenance, formatting, compilation, sampler, process-race, agent, shell,
  pager, and staged-candidate gates. Two completed security scans
  (`4c4528c2-2274-4dff-84e5-b0819c0c2aad` and
  `992b7377-7335-472b-8acd-a50ad6f6772c`) consumed 8,830,471 audit tokens and
  reported zero reportable findings in their immutable scanned ranges.
- The required source audit found two inherited Slice 4A prerequisites: a
  provider-usage settlement refund and an armed folder-trust path that could
  reload plugin MCP/hook execution. Both were repaired, tested, and rescanned
  before publication. This was the only 4B.0 scope expansion; it did not
  activate, install, or exercise the fork.
- `origin` fetch is official upstream, `origin` push is mechanically disabled,
  and `personal` is Jimmy's fork. A local upstream push dry run refused before
  publication. No app launch, installed-CLI mutation, live config read/write,
  Keychain value read, provider request, tag, release, or paid authority
  occurred. The official installed CLI remains untouched.

## Design contracts for later slices

These contracts guide later work; they do not authorize it.

### Exact candidate runtime

The acceptance sidecar must bind an absolute canonical executable path, binary
SHA-256, architecture, source commit, expected `cliBuild`, and one unambiguous
signature predicate. The candidate must pass strict code-signing verification,
carry Team Identifier `DD2GCQJVB4` (the installed app's team), and match the
exact designated requirement recorded in its provenance manifest; an arbitrary
valid or ad-hoc signature is insufficient. The implementation uses
Security.framework or an equivalently exact designated-requirement check, while
the acceptance receipt records credential-free `codesign --verify --strict`,
Team ID, and `codesign -d -r-` evidence. `HardBudgetLaunchContract` rechecks the file with
no-follow, owner/private, regular-file, device/inode/size/hash, and signing
validation immediately before process creation. A path recheck alone is not
the inspected-equals-launched proof because replacement can occur after the
last pathname check. Slice 4B.1 therefore copies the held, hashed descriptor
bytes into a random owner-private one-use executable, retains that copy's FD,
starts it suspended before user code, and compares the live process CodeDirectory
hash to the inspected copy before `SIGCONT`. A mismatch is killed and reaped before ACP can
start. This is the available Darwin inspected-equals-launched proof: macOS has
no usable `fexecve`, and a direct `/dev/fd/<n>` `posix_spawn` probe returned
`EACCES`. Hostile disposable signed-fixture tests prove a post-inspection source
path swap still executes the pinned inspected bytes and cannot execute replacement
code. The real 4B.0 candidates remain ad-hoc, refused, and
non-armable until the separately authorized signed installation in 4B.6; 4B.1
must not create a durable real-candidate install merely to make a fixture green.
`GrokProcess` and
`GrokCLIService` must share one resolver. Armed catalog and ACP execution name
the same selected candidate. Candidate preflight/inspect and provider execution
remain hard-locked until 4B.3 supplies the native credential and route-provenance
contracts; dormant legacy preflight must not be represented as candidate
authority.

The candidate is stored below an owner-private GrokBuild runtime root keyed by
its digest. Ordinary launches continue to use the official CLI. Rollback occurs
only after process-zero and means removing the acceptance selection—not
overwriting, deleting, or silently downgrading the official installation.

### 4B.1 receipt — 2026-08-18

- One strict runtime-selection sidecar binds the owner-private runtime root,
  digest-addressed candidate and provenance paths, and exact provenance hash.
  Swift and Python independently require the complete v1 source, toolchain,
  build, binary, architecture, build-string, Team, strict-signing, and
  designated-requirement contract. Root, digest-ancestor, selection, manifest,
  and ledger symlinks or hard links fail closed.
- `GrokProcess` and `GrokCLIService` now share one armed resolver. Any partial,
  duplicate, stale, malformed, or legacy acceptance authority blocks ordinary
  CLI discovery. Ambient `PATH`, `GROK_CLI_PATH`, and test overrides cannot
  substitute a different runtime while armed. Catalog warmup is suppressed
  until the selected candidate owns the ACP catalog.
- Acquisition hashes a no-follow candidate descriptor, copies those exact bytes
  into a random owner-private one-use executable, reopens and revalidates the
  copy, starts it suspended, and verifies the live CodeDirectory hash before
  `SIGCONT`. Hostile tests prove a post-acquisition source-path swap executes the
  pinned bytes, ad-hoc and wrong-Team fixtures refuse, a lease is single-use,
  and a TERM-ignoring child is force-killed and synchronously reaped.
- Authority retirement requires two typed process-zero samples and unlink-safe
  single-link sidecars. It removes only the ephemeral Swift authorization and
  runtime-selection sidecars; the CLI manifest, durable ledger, candidate, and
  provenance remain retained. A hard-linked sidecar refuses retirement rather
  than pretending its authority was removed.
- Final local verification passed the Python v2 authority/evaluator suite
  **25/25**, `CandidateRuntimeAuthorityTests` **8/8**, the complete Swift suite
  **984/984**, harness dry-run with exactly 3,000,000 planned and 1,000,000
  reserved tokens, `compileall`, and `git diff --check`. Two independent skeptical reviews
  returned no remaining 4B.1 blocker.
- A direct v2 `--billable` invocation exited 2 at the absolute-ceiling guard
  before runtime discovery, authority creation, app launch, or provider work.
  Process-zero samples at `2026-08-18T05:38:53-0400` and
  `2026-08-18T05:38:54-0400` contained no GrokBuild, helper, agent, or Grok CLI
  process.
- Retained candidate B still reports `grok 1.0.5 (003f955) [stable]`, binary
  SHA-256 `4763acd631b927b71cfa8594863fc19e9bb6873f7757ce7c7903eb3993b57287`,
  provenance SHA-256
  `dae8c7ad444ea5d2ce726cbb84f9fdfba9c471772126b9ec1521bb0dc3443bda`,
  ad-hoc signing, and no Team Identifier, so it remains deliberately non-armable
  and uninstalled. The official installed CLI remains unchanged at
  `grok 1.0.4 (d846eb93d94d) [stable]`, SHA-256
  `39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485`.
  No candidate install, Keychain value read, live config mutation, provider
  request, or paid packet occurred.

PR [#124](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/124)
passed required exact-head run `32123735441` on
`1e918c55bde519e67b41d7716c64c2085b915362` and merged normally as
`a8fb17fbfbc6bc5656148d7475bfff5a153eda11`. `make ship` reran the full
**984/984** suite, installed that exact clean code-bearing merge, and proved
stamp equality, dist/installed byte parity, Team `DD2GCQJVB4`, deep/strict
signing, and no quarantine. A focused installed-app smoke opened the ordinary
unarmed workbench without starting an ACP process, then quit normally. The
immediate process-zero gate truthfully refused while shutdown children drained;
final samples at `2026-08-18T06:03:58-0400` and
`2026-08-18T06:04:03-0400` were empty. The official CLI remained unchanged at
the version and SHA recorded above. Slice 4B.1 is closed; Slice 4B.2 is accepted.

### `HardBudgetCredentialMaterializationV1`

Swift validates the exact GrokBuild-managed provider ID, configured model,
endpoint identity, API backend, and auth scheme, then reads exactly one generic
password item from Keychain service `com.grokbuild.provider-credential`. It
passes bounded bytes once to the exact armed child through a private inherited
pipe/file descriptor or another equivalently proven nonpersistent primitive.

The secret never appears in argv, environment, TOML, filesystem artifacts, ACP,
stdout, stderr, checkpoints, crash text, receipts, or hashes. The CLI consumes
and closes the channel once, holds bytes in zeroizing storage, refuses malformed
or oversized input, and checks the supplied non-secret provider binding against
its own resolved config before reservation. It does not execute
`auth.command`, refresh helpers, or 401 recovery while armed. A Keychain read
proves only local materialization—not provider validity.

4B.2 must first exercise the app's actual armed `posix_spawn` candidate launcher,
not a substitute Foundation `Process` fixture. Its compiled cooperative receiver
must see only stdio plus fixed FD 198, consume one bounded fake frame, close that
FD before a nested exec, and emit no payload. The spike must explicitly retain
Darwin's limits: `FD_CLOEXEC` does not prevent raw-fork inheritance, an arbitrary
hostile child can escape a process group, and Swift value copies do not prove
zeroization. Therefore 4B.2 is mechanism feasibility only. Slice 4B.3 must put
the real Rust receiver before config/hooks/tools/subprocesses/network, close the
FD before any fork, use consuming zeroizing storage, and re-prove the exact
candidate/tool tree. A macOS-native CLI Keychain consumer may be evaluated as a
new design; environment secrets, temporary secret files, and an allowlisted
executable helper are not acceptable fallbacks.

#### Slice 4B.2 acceptance

PR [#126](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/126)
passed required exact-head run `32128471671` on
`b52855cda19b3701044f693430d90e81d050d436` and merged normally as
`2559a43d74e4b1f8453edcaca6692f4016a39b4c`. The exact committed range received
three independent skeptical COMMIT verdicts. The implementation remains a
cooperative fake-payload feasibility proof: no production caller supplies the
transport, and no Keychain value, provider credential, live config, auth helper,
official CLI replacement, or provider request entered the slice.

The real armed `posix_spawn` candidate path proved bounded binary framing on
fixed FD 198, an app-wide spawn gate across Darwin's non-atomic `socketpair`
close-on-exec window, positive environment allowlisting, payload refusal in
argv or environment before spawn, one aggregate deadline, collision-safe
descriptor normalization, nested-exec descriptor closure, generic errors, and
same-process-group rollback. Hostile coverage proves malformed, oversized,
truncated, duplicated, trailing, slow-drip, bad-peer, high-FD canary,
concurrent-spawn, root, descendant, and process-group cleanup cases. A stale
test-owned hostile-fixture process group from the uncommitted development run
was identified by its deleted fixture path, PGID, and FD 198 and removed
narrowly; the final code then tightened cleanup proof and passed the complete
**991/991** suite followed immediately by two empty process-zero samples.

Merged-main `make ship` reran **991/991**, built and installed the exact clean
merge, and proved stamp equality, dist/installed binary SHA-256
`310044e4e383f6fe1bb8c31115393007d5ae991657ce4e6becb2ffcc510d3415`, Team
`DD2GCQJVB4`, deep/strict signing, and no quarantine. The installed app opened
on the ordinary unarmed workbench without sending or starting a backend, quit
normally, and reached empty process-zero samples at
`2026-08-18T07:00:41-0400` and `2026-08-18T07:00:46-0400`. Python V2 contracts
passed 25/25, the focused candidate/transport suite passed 15/15, release build
passed, and the billable command still exited 2 at the absolute-ceiling lock
before runtime discovery. The official CLI remains unchanged at
`grok 1.0.4 (d846eb93d94d) [stable]`, SHA-256
`39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485`.

**Historical — superseded:** Slice 4B.3 is next and remains nonbillable. It owns the real Rust consumer
before any fork, consuming zeroizing storage, actual Keychain/provider binding,
route provenance, policy v3, and real tool-tree containment. Raw-fork/`setsid`
escape and real credential behavior are not 4B.2 claims.

A 2026-08-18 in-progress checkpoint on `codex/official-runtime-s4b3-native-credential`
and `codex/official-runtime-s4b3-materializer` made `SamplingClient::new_with_armed_v3`
require a registered `ActiveHardTokenV3Authority` and that object's real budget,
tied credential claim to active registration, refused legacy v1 env arming, and
kept capability unarmed until registration. Independent Swift and Python
verifiers share the Rust golden canonical digest
`5052a5285a35ea96151340259475a69351ed162c8308a8f2166b453a5720f950`. The Darwin
pager now installs the FD-198 payload into the one-shot owner and wipes it
before `process::exit`. `bind_and_install_v3_authority` plus the armed
constructor are the authorized fake-loopback consumer: Chat/Responses/Messages
send the one-shot sentinel only to an exact loopback URL whose endpoint SHA-256
matches the bound route. Remote hosts and route drift refuse before any
connection. Live 4M/3M/1M packets still load the v1 governor; unbound v3 still
fail-closes at bootstrap when `bind_measured_v3_authority_if_present` cannot
observe and resolve a complete candidate/config/route snapshot. The live v2 capability decoder will not treat a v3 projection as
enforcing. The CLI `open_private_file` path now refuses hard-linked manifest,
ledger, and lock artifacts (`nlink == 1`), matching the app sidecar contract.
Armed v3 `posix_spawn` now duplicates the held lease descriptor onto child FD
197. After GBCT READY the pager measures that descriptor plus compiled
`SOURCE_COMMIT_SHA` into `CandidateIdentityV1` and still does not call
`bind_actual` with an invented config or route. Hashing `current_exe()` remains
out of bounds. Fail-closed `ArmedV3ResolvedSnapshot` types refuse empty
defaults, remote hosts, and secret-bearing sampler configs. ACP spawn accepts
the live v1 contract or already-active v3 authority and still refuses an
unbound v3 env. Production `GrokProcess.start` materializes a v3 contract
through the dedicated Keychain client and `posix_spawn`s the leased candidate
with FD 198/197; debug tests inject that client, schema-2 still fail-closes, and
schema-3 packets parse `credentialAuthorizationV3` selectors. Dispatch binds
those selectors through `ArmedV3DispatchExpectation` to the live custom model
and linked provider before `HardBudgetLaunchContract`. Spawn rechecks that
latch immediately before `posix_spawn`. Armed `initialize` refuses `.ready`
without a matching nested `v3Authority`. Schema-3 packets require 20M/19M/1M
and refuse the live v1/v2 4M governor; schema-2 stays 4M/3M/1M. Native Grok routes fail
that bind and still fail preflight if a contract is constructed directly. Armed
mode omits the summary `OaiCompatClient`. Resolved models keep `model_provider`.
`ResolvedConfigIdentityTracker` bumps generation only when the credential-free
catalog projection changes. Live route observation now measures loopback
endpoint SHA, a deterministic `v3.<sha256>` route id, Darwin `fd_v1`,
selected-model `resolved-managed-provider`, the live 64KiB serializer ceiling,
and the five lexical `GrokBuild:` isolation IDs. Conservative request bound is
derived as live payload + observed output cap. Allocation ceiling and max model
calls must come from the frozen packet envelope. Golden 8192/route-1/two-tool
packet numbers are refused as actual. CLI `agent::init::bootstrap` now calls
`bind_measured_v3_authority_if_present` after `ModelsManager::from_config` to
bind complete unbound v3 envs from independently observed fields; it no-ops
without hard-budget env, skips bind on `LegacyManifestRefused`, and does not
invent OpenRouter goldens, SuperGrok, official 1.0.4 bytes, or copy secrets via
`sampling_config_for_model`. Production `GrokProcess.start` now materializes
v3 and launches the leased candidate; it still does not invent bind identity.
CLI PR #4 merged as `f87a874` after `candidate-contract` run `32216015180`;
desktop docs PR #131 merged as `55333d70`. Local E2E used candidate `86f0c70`
(`1.0.5 (86f0c70)`, binary SHA-256 `25181a88…0df98`), not merge `f87a874`. The live ACP capability now nests a strict three-field
`v3Authority` object instead of top-level provenance/policy fields. Swift
re-canonicalizes the typed provenance, derives headers from `authScheme`, and
still refuses to treat a v3 projection as historical v2 enforcement.

**Historical 4B.3-era T5 receipt:** T5 production `GrokProcess.start` now has an owner-local, env-gated E2E
(`GROKBUILD_SLICE4B3_RUNTIME_SELECTION`) against the Apple Development signed,
digest-staged pager at binary SHA-256
`14da2ef77ea00cbea6d8b2cf3ad9d6511eb530a53d23777109e6f382a7e68701`,
`cliBuild` `1.0.5 (86f0c70)`, Team `DD2GCQJVB4`. A 2026-08-19 local DEBUG run
passed in 17.445s: lease without the fixture signature override, fake Keychain
sentinel, `posix_spawn` of that SHA (not `/usr/bin/true`, not
`~/.grok/bin/grok`), fail-closed ACP startup, sentinel absent from the launch
receipt, leftover `.grokbuild-exec-*` copies reaped, and official CLI still
`grok 1.0.4 (d846eb93d94d) [stable]` SHA-256
`39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485`. The test
skips in CI and whenever the selection file is unset. It is not live Keychain,
live provider, candidate install, or paid proof. The ad-hoc original
`25181a88…0df98` remains evidence-only and is not the T5 binary.
Current accepted pager pin is `f434fa4f…933b` / `1.0.5 (8226242)`.
**Historical — superseded:** 4B.4 is the exact next slice after this closeout merges. Paid activation
remains locked.

PR [#136](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/136)
merged the T5 closeout as `1aeebdf`. 4B.4 tab-select is wired: schema_v3 rejects
`resumeAfterQuit`, `session/resume`, and `resume_saved_task`; receipts require
three allocations, one backend, and one ledger; `governed_fresh_process_load`
selects the retained tab by AX UUID and cannot call the ungoverned saved-task
chrome; acceptance `session/load` refuses stale `session/new` fallback; and
`resumeTaskSession` refuses during acceptance so packet Send owns allocated
load. Ordinary consumer Resume is unchanged. Schema-3 continuation dry-run and
`_billable_v3` are wired (T1 `session/new`, T2/T3 `governed_fresh_process_load`,
cleanup after T3) and still fail-closed at the absolute ceiling. That executor
is 4B.4 continuation proof, not the 4C paid route matrix. Paid activation
remains locked.

### `HardTokenBoundProvenanceV1`

The canonical credential-free document includes schema and serializer versions,
allocation and route IDs, provider-facing model, endpoint SHA-256, API backend,
maximum final serialized payload bytes, maximum output tokens, conservative
request bound, request/call ceilings, exact text-only/remote-context/multimodal
refusals, tool-isolation contract, redirect/retry state, and the bound rule used
by sampler admission. The CLI is the sole producer of the resolved-route
document from its actual config and serializer. Swift and Python do not recreate
that resolver: they independently canonicalize and hash the projected document,
validate its schema and arithmetic, and compare its non-secret route fields with
their immutable expected model/endpoint/backend contract.

Any version, model, endpoint, backend, serializer, limit, tool-policy, or bound
drift refuses before reservation. Provenance describes the bound calculation;
it does not claim the provider honored a request or that price settlement is
known.

### `freshProcessLoad` continuation v3

The continuation manifest records group and turn IDs, predecessor packet and
backend digest, expected local tab, fresh app launch epoch, fresh CLI process
generation, fresh allocation, and the shared campaign manifest/ledger. T1
creates the backend. T2 and T3 select the retained exact tab and trigger standard
`session/load` only after their own governed processes advertise the correct
allocation. The harness never invokes the legacy ungoverned resume entry point,
never calls `session/resume`, never starts an unallocated catalog/resume process,
and never falls back to a new backend when load identity fails.

The harness must not invoke the current ungoverned `resume_saved_task()` entry
point before allocation. It gets a new explicit governed-load driver action:
first launch and verify the exact allocated process, then use the app's standard
native `session/load` path for the selected retained tab. The ordinary consumer
"Resume current task" behavior remains intact outside acceptance. The old
runner's new-chat-per-packet behavior and close-after-every-packet cleanup cannot
be reused. The tab/backend remain retained until the group ends. Each
turn produces its own pre-dispatch cursor and terminal receipt; all three charge
the same campaign ledger. Only after T3 reconciliation may exact local cleanup
run.

## Nonbillable acceptance matrix

In 4B.5, the exact staged candidate must pass the matrix below without replacing
the installed official CLI. In 4B.6, the signed digest-addressed candidate must
be installed in the owner-private GrokBuild runtime, and the installed app must
rerun the complete matrix against that exact binary. Both passes use controlled
loopback providers with no real credential:

| Case | Required proof |
|---|---|
| Normal direct call | One connection, one reservation, settled usage, exact route and candidate identity |
| Ordered native reads | Three `GrokBuild:read_file` calls against hashed ONE/TWO/THREE fixtures; no terminal |
| Worker coordination | Exact task/wait lifecycle, inherited allocation, bounded calls, no widened tools |
| Recovery | Missing fixture read fails, RECOVERED read succeeds, then exact terminal receipt |
| Stop/cancel | Cancel/drain/query occurs before teardown; ambiguous work remains fully charged |
| Kill windows | Kill after reserve, after connection, after response before settlement, and during restart; ledger reopens conservatively |
| Retry/redirect | One attempt only; redirect target and retry listener receive zero connections |
| Continuation | Three fresh allocations/processes, one backend via `session/load`, no resume or stale fallback |
| Credential sentinel | One-shot fake credential reaches only the expected loopback authorization header and no retained artifact |
| Side egress | Terminal, MCP, hooks, plugins, LSP, workflows, scheduler, web/media, remote context, auth helper, ambient logging, and foreign network/process paths stay zero |
| Receipt reconciliation | App checkpoint, ACP usage/model, CLI typed receipts, ledger cursors, route, calls, tokens, and cleanup agree exactly |

Fake-provider price evidence is simulated and must be labeled that way. It can
prove tokens, reservations, calls, and lifecycle; it cannot prove a live
provider's billing or credential validity.

### 4B.5 edit map (2026-08-19)

Owner-local proofs live in these files. Do not retarget pager pins anywhere else.

| Job | Edit here |
|---|---|
| Signed pager pin (`SHA` / `cliBuild` / source) | `Tests/GrokBuildTests/Slice4B5LifecycleTests.swift`, `Tests/GrokBuildTests/GrokArmedCredentialMaterializerTests.swift`, `scripts/acceptance/harness/candidate_process_driver.py` |
| Loopback modes, SSE, tool wire names | `scripts/acceptance/harness/loopback_provider.py`, `scripts/acceptance/tests/test_v3_lifecycle.py` |
| Armed spawn / 90s `session/prompt` | `GrokBuild/Services/GrokProcess.swift` (`armedSessionPromptTimeout`), `GrokArmedCredentialMaterializer.swift` |
| CLI hang repairs (Outstanding, zero-tool freeze, after-turn detach) | CLI fork `crates/codegen/xai-grok-shell/src/session/acp_session_impl/{turn.rs,turn_end.rs}` and `acp_session.rs` on `cursor/official-runtime-s4b5-armed-turn-sampler` |
| Kill-after-response-before-settlement | `loopback_provider.py` mode `hold_after_body`; `Slice4B5LifecycleTests.testKillAfterResponseBeforeSettlementChargesAmbiguousReservation` |
| Hostile `setsid` / tool-tree | CLI spawn/process-group code in the grok-build fork. CI leftover merged as PR #7 `7e9f1ad` (`hard_budget_receiver_closes_fd_before_raw_fork_and_setsid_descendant` on the pager-bin `hard_budget` filter). Darwin post-enrollment `setsid()` escape remains the known 4B.2 limit. |
| 4B.6 signed owner-private install | `scripts/acceptance/harness/candidate_install.py`; owner-local `Slice4B5LifecycleTests` install a copy first; ordinary lookup never scans `candidate-runtime`; not `~/.grok/bin/grok`; rollback requires two empty process-zero samples with distinct timestamps |
| 4C paid unlock | `_billable_4c` plus `official-provider-slice4c-paid.json` pass the frozen-identity ceiling dispatcher. Schema-4 preflight uses the leased pager and keeps official grok at 1.0.4. Catalog prices are confirmed. Native freeze bind is in tree. First 4C `make ship` is dirty `18b2549`. Remaining: sidecar arm, Send, rollback. Do not unlock `_billable_v3` or weaken lower guards. CLI PR #7 is **merged** as `7e9f1ad`. |

Staged pager identity for this pass: binary SHA-256
`f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b`,
`cliBuild` `1.0.5 (8226242)`, source
`822624291de2b544605f439ad1349ae6bdc3cf10`. Official CLI remains
`39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485`.

### 4B.6 receipt — 2026-08-19

Desktop PR [#140](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/140)
passed required exact-head **Test and Build App** run `32310895764` and merged
normally as `29c064fbb67b740952fe6b291f00e6a053087f8d`. Merged-main `make ship`
installed that exact clean tree: stamp == HEAD, `dirty=false`, branch `main`,
dist/installed Mach-O SHA-256
`55d85de47511f2e1e34e0dcd9844ba5e9f61e4c6a6110f33543124e90038a7a7`, Team
`DD2GCQJVB4`, deep/strict signing, no quarantine. Version stays `0.1.22`.

`scripts/acceptance/harness/candidate_install.py` byte-copies the signed pager
into `~/Library/Application Support/GrokBuild/candidate-runtime/<sha256>/`
(`O_EXCL`, fsync, quarantine strip, chmod 0700/0700/0600) and refuses anything
under `~/.grok`. Owner-local `Slice4B5LifecycleTests` installed a copy first,
then reran the complete 4B.5 loopback matrix against that copy (17/17) with
`GROKBUILD_SLICE4B3_RUNTIME_SELECTION` pointing at the staged selection. Ordinary
`GrokCLIRuntimeResolver` still never scans `candidate-runtime`. The durable pager
copy remains on disk at SHA-256
`f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b`; rollback
unlinked only `runtime-selection.json`. A later closeout refuses rollback
samples that share one timestamp; the historical same-second
`rollback-receipt-v1.json` at `2026-08-19T17:53:24-0500` is retained evidence,
not a new rollback. Installed Computer Use of `/Applications/GrokBuild.app` was
unarmed idle (no 1.0.5 banner, Send labeled **Send and resume session** and
disabled). Distinct post-quit process-zero samples were recorded at
`2026-08-19T18:09:00-0500` and `2026-08-19T18:09:05-0500`. Official CLI remained
`grok 1.0.4 (d846eb93d94d) [stable]`, SHA-256
`39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485`.

The pager binary is still source `8226242`. Do not rebuild it. Local pager
`cargo test` in this worktree must set `CARGO_TARGET_DIR` to a path without
spaces (jemalloc configure refuses `MCP Servers`) and keep `dotslash` on
`PATH`; CI already uses `$RUNNER_TEMP/grokbuild-cargo-target`. The layout-loop
selection suspend from PR [#138](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/138)
is on this `main`. A 4B.6 closeout pass reconfirmed unarmed idle Computer Use
of `/Applications/GrokBuild.app` at stamp `29c064f` (Send labeled **Send and
resume session** and disabled; **Resume current task** visible and not
clicked). Paid 4C stays locked.

CLI PR [#7](https://github.com/schmitzjimmy1-star/grok-build/pull/7) passed
required `candidate-contract` run `32310906969` (armed pager tests plus staged
release candidate and provenance) and merged normally as
`7e9f1ade576df903652b150d634ca634e5180bc4`. Local CLI `personal/main` is that
merge. The pager on disk is still SHA-256
`f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b`; selection
sidecar remains absent. Official CLI remains `1.0.4` /
`39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485`. Local
`cargo test` under this space-containing worktree path is environmental, not a
product leftover; do not refill `/tmp` with another pager compile.

Three independent 4C-unlock reviews of installed `29c064f` plus CLI leftover
`7e9f1ad` finished 2026-08-19: containment GO; harness NO-GO for unlocking
`_billable_v3` (unarmed `launch_installed()` would Send on official 1.0.4);
identity pins re-derived live (official CLI `39366f77…`, pager `f434fa4f…`,
installed Mach-O `55d85de4…`, Team `DD2GCQJVB4`). Live selection sidecar stays
absent. `_billable_4c` plus the schema-4 matrix now exist; paid Send
still refuses at `require_absolute_ceiling_support()` for schema-3 and no-arg
calls. Schema-4 `--billable` uses the ceiling dispatcher, then
`require_4c_send_ready`, then leased-pager preflight (official 1.0.4 + pager
`1.0.5 (8226242)`). Native schema-3 freeze bind is in tree (leased candidate,
no Keychain). First 4C `make ship` is dirty `18b2549` / Mach-O `1aa3318f…`.
Do not treat `_billable_v3` as unlock, and do not send `_billable_v3` on official 1.0.4.

## Paid unlock and execution

4C is a separate decision boundary. It cannot begin merely because the locked
executor is merged or the unconditional lock is easy to delete. Three independent skeptical
reviews of the exact installed 4B.6 tree (`29c064f`), the CLI leftover merge
`7e9f1ad`, and retained nonbillable evidence are complete. The **unlock** commit
must replace the first-branch refusal with a
narrow, testable predicate for that exact campaign; it may not weaken any lower
guard or send `_billable_v3` on the official 1.0.4 path. The implementer map is
[`GROKBUILD_SLICE4C_EDIT_MAP_2026-08-19.md`](GROKBUILD_SLICE4C_EDIT_MAP_2026-08-19.md).

The paid manifest freezes exact catalog-confirmed models, routes, prices,
allocations, prompts, tools, and expected receipts. Its allocation sum is at
most 19M beneath the 20M absolute ceiling; the 1M remainder is structurally
unallocatable. Native control runs first, then the smallest direct-provider
packet, then the smallest brokered packet. Later tool, worker, continuation, or
additional depth packets run only while every predecessor is green and
reconciled and the evidence is still insufficient. There are no automatic
retries or substitute models. Early success ends the campaign without spending
the unused allocations.

Stop immediately on candidate drift, config drift, route/model/usage mismatch,
unexpected call/tool/worker, helper execution, foreign egress, missing or partial
receipt, price/cost variance outside the frozen policy, timeout, process identity
drift, cleanup failure, or any campaign/allocation/call/token ceiling refusal. A
failed packet is retained evidence, not permission to try again.

## Publication and cleanup

- App work uses `personal`; upstream CLI work keeps `origin` read-only and uses
  a clearly named Jimmy-owned publication remote.
- No force push, tag, release, notarization, branch deletion, broad session
  cleanup, or protected-history deletion is part of 4B.
- Candidate artifacts and authority files are owner-private. After confirmed
  process-zero, remove only the ephemeral Swift authorization sidecar. Retain
  the canonical CLI manifest, shared ledger, candidate provenance, and sanitized
  terminal receipts for reconciliation.
- On cleanup uncertainty or process-zero failure, retain all run-owned artifacts
  and stop. Never call retained backend state "cleaned."
- Slice 4 closes only after exact-head CI, normal merge, merged-main ship/install,
  installed identity parity, paid or explicitly failed packet reconciliation,
  exact run-created-tab cleanup, and two process-zero samples.

## Reconnaissance receipt

Three independent skeptical Terra Medium audits scoped this campaign from the
clean app and CLI heads. They independently examined the CLI fork publication
and candidate supply chain, the Swift/CLI credential and provenance boundary,
and harness continuation/loopback/cleanup behavior. Their common verdict was:

- **GO** for the nonbillable 4B sequence above.
- **NO-GO** for candidate installation, credential-value access, provider Send,
  or paid unlock today.
- **NO-GO** for weakening the official runtime ownership boundary or restoring
  executable auth helpers in armed mode.

No file, config, credential, provider, installation, or external repository was
mutated by the reconnaissance agents.

After the draft incorporated their supply-chain, signature, staged-versus-
installed, governed-load, and provenance corrections, all three returned
**COMMIT**. The exact planning branch passed `git diff --check` and the full app
suite: **976/976 tests, 0 failures**. No provider or backend prompt ran. Slice
4B.0 remains the only executable authority created by this document.
