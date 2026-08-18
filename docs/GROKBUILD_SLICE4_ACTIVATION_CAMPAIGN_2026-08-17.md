# GrokBuild Slice 4 Activation Campaign — 2026-08-17

Status: **Reconnaissance and planning review complete; implementation not
started; paid activation locked.** This document is the authority for completing
the official-provider and open-weight lane after the nonbillable Slice 4A hard-budget checkpoint. It
does not authorize a provider request, credential-value read, live Grok config
mutation, installed-CLI replacement, tag, release, or Slice 5 work.

Jimmy raised the eventual testing authority on 2026-08-17 to an absolute
**10,000,000-token ceiling**. That is a ceiling, not a target. The final immutable
campaign may plan at most 9,000,000 tokens and must retain 1,000,000 tokens as
unreachable reserve. The current 4M/3M/1M implementation remains authoritative
until a later 4B slice versions, tests, and merges the larger policy; the new
ceiling does not unlock the paid branch today.

## Starting truth

The app repository is clean at merge `1660ee5e45fca7b1d7146ffc19d0714de866f501`
(PR #121). The installed app matches that merged-main build. Its installed
runtime remains official `grok 1.0.4 (d846eb93d94d) [stable]`.

The hard-budget CLI fork is clean at
`03a28d484da91788931aec1aeb0f3aa0ca9a1368`, six commits over official 1.0.5
base `9fabade`. Its only remote is upstream `xai-org/grok-build`, and that remote
is still configured for both fetch and push; 4B.0 must mechanically disable its
push URL before publication. The fork has not been published under Jimmy's GitHub account,
built as a retained candidate artifact, installed, or exercised through the
installed app. The current upstream delta after the pinned base is small and
does not touch the hard-budget seam, but it must still be range-diffed and
resolved before candidate publication.

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

   `settled tokens + outstanding worst-case reservations <= 9,000,000`

   The remaining 1,000,000 tokens beneath Jimmy's absolute 10,000,000-token
   ceiling are unreachable reserve. The current checkpoint's exact 4M/3M/1M
   contract must fail closed until the versioned 10M/9M/1M authority is present
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
| **4B.2** | **Credential materialization feasibility and contract** | Fake-sentinel transport spike and non-secret shared schema only | One-shot inherited transport is proven read-once, bounded, nonpersistent, noninherited by children, absent from argv/env/files/logs/receipts; otherwise stop and redesign; no Keychain value read |
| **4B.3** | **Native armed credential, bound provenance, and campaign-policy v3** | CLI credential consumer, Swift materializer, canonical provenance producer/verifiers, typed capability, versioned 10M/9M/1M authority | Exact managed-provider/config binding, route TOCTOU refusal, helper paths still disabled, fake credential loopback, canonical route/bound equality in Rust/Swift/Python, old/new policy mismatch refusal; ordinary unarmed helper behavior unchanged |
| **4B.4** | **Fresh-process continuation contract** | Harness schema/evaluator/driver and app lazy-load choreography | Legacy continuation rejected at schema level; T1 new plus T2/T3 fresh-process `session/load` use three allocations, one backend, one ledger, no `session/resume`, no load-time prompt, no stale fallback, cleanup only after the group |
| **4B.5** | **Nonbillable staged-candidate lifecycle and containment** | Test-only loopback provider, process driver, receipt/cleanup fixtures | Exact staged, noninstalled candidate survives normal, Stop, cancel, kill, restart, stream failure, missing usage, repeated provider correlation, redirect, and call-ceiling tests; foreign egress/helper/retry count is zero; authority retained honestly |
| **4B.6** | **Signed candidate install and installed nonbillable acceptance** | Digest-addressed owner-private candidate runtime and rollback receipt | Build/sign/copy atomicity, architecture/quarantine/signature/hash parity, installed app launches that exact candidate, then reruns the complete 4B.5 hostile matrix; clean rollback, full suites, two process-zero samples |
| **4C** | **Bounded paid matrix** | Provider Sends and exact run-created acceptance artifacts only | Separately unlocked after three skeptical reviewers approve 4B.6; stop on first mismatch or sufficiency; planned spend never exceeds 9M and absolute authority remains 10M |
| **4D** | **Slice 4 closeout** | Evidence docs, app publication, narrowly owned cleanup | Exact-head CI, normal merge, merged-main ship/install, paid reconciliation or explicit retained failure, exact tab cleanup, two process-zero samples; Slice 5 still locked |

## Slice 4B.0 — exact first authority

Only 4B.0 is preauthorized by this planning checkpoint.

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
validation immediately before process creation. `GrokProcess` and
`GrokCLIService` must share one resolver. Armed preflight, inspect, catalog, ACP,
and provider execution must all name the same binary.

The candidate is stored below an owner-private GrokBuild runtime root keyed by
its digest. Ordinary launches continue to use the official CLI. Rollback occurs
only after process-zero and means removing the acceptance selection—not
overwriting, deleting, or silently downgrading the official installation.

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

4B.2 must first prove that Foundation `Process` and the child CLI preserve only
the intended descriptor and do not leak it to model tools or subprocesses. If
that proof fails, the slice stops. A macOS-native CLI Keychain consumer may be
evaluated as a new design; environment secrets, temporary secret files, and an
allowlisted executable helper are not acceptable fallbacks.

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

## Paid unlock and execution

4C is a separate decision boundary. It cannot begin merely because the code is
merged or the unconditional lock is easy to delete. Three independent skeptical
reviews must approve the exact installed 4B.6 tree and retained nonbillable
evidence. The unlock commit must replace the first-branch refusal with a narrow,
testable predicate for that exact campaign; it may not weaken any lower guard.

The paid manifest freezes exact catalog-confirmed models, routes, prices,
allocations, prompts, tools, and expected receipts. Its allocation sum is at
most 9M beneath the 10M absolute ceiling; the 1M remainder is structurally
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
