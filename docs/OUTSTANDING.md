# OUTSTANDING — canonical GrokBuild edit and slice ledger

> **Authority:** This is the one canonical list of open GrokBuild work. If another
> handoff, receipt, issue, or chat conflicts with this file, stop and reconcile the
> conflict here before editing. Historical documents remain evidence; they do not
> silently add scope.
>
> **Publication authority:** Jimmy explicitly requires every accepted slice in this
> ledger to be committed, pushed to `schmitzjimmy1-star/grok-build-desktop`, reviewed
> in its own pull request, and merged before the next slice begins. This authority is
> limited to the named slice files and required tests/docs. It does not authorize
> force pushes, branch deletion, tags, releases, writes to `origin`, configuration or
> credential changes, or opportunistic cleanup.
>
> **Cleanup authority:** Every acceptance thread created for a slice must be removed
> after its receipt is captured. Only exact, ledgered test-thread IDs may be deleted.
> User conversations, historical acceptance evidence, unnamed sessions that were not
> created by the current slice, and unrelated browser/app state are protected.

## Status — seven repair slices open

The installed-app audit on 2026-08-08 verified the canonical repository and
installed application, then exposed seven bounded repair areas. They are ordered
below so truth and lifecycle contracts land before presentation and optimization.

| Slice | Objective | Risk | Provider spend | Status |
|---|---|---:|---:|---|
| 0 | Freeze the audit baseline and remove the four audit-only threads | Low | None; control slice creates no product behavior | Merged and accepted |
| 1 | Stop Activity from claiming task success from transport completion | High | 4 prompts; up to 220K tokens | Open |
| 2 | Separate browser process readiness, catalog capability, requested use, and proven use | High | 5 prompts; up to 320K tokens | Open |
| 3 | Replace Browser Settings false-negative startup flicker with an unresolved/checking state | Medium | 3 prompts; up to 180K tokens | Open |
| 4 | Replace raw Computer Use self-test JSON with a compact parsed receipt | Medium | 4 prompts; up to 240K tokens | Open |
| 5 | Repair navigation-rail accessibility selection semantics | Medium | 3 prompts; up to 200K tokens | Open |
| 6 | Reduce tiny-turn context cost and guarantee zero owned processes at slice close | High | 6 prompts; up to 480K tokens | Open |

No slice may begin until the preceding slice is merged, local `main` matches
`personal/main`, the installed app is stamped to that merged commit, slice-created
threads are gone, and the process-zero gate is green.

---

## Immutable identity and safety boundary

All work must stay on the maintained line:

| Identity | Required value |
|---|---|
| Worktree | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Personal repository | `https://github.com/schmitzjimmy1-star/grok-build-desktop` (`personal`) |
| Preserved upstream | `https://github.com/rimusz/grok-build-desktop` (`origin`, reference only) |
| Release branch | `main` |
| Installed app | `/Applications/GrokBuild.app` |
| Bundle ID | `com.grokbuild.app` |
| Signing team | `DD2GCQJVB4` |

Never build, install, publish, revive, or borrow files from
`/Users/jimmyschmitz/Documents/Grok Builf` or
`jimmmy-Jim/Grok-Build-GUI`. A provider label, version `0.1.20`, familiar UI,
or working model is not repository identity.

### Current audit baseline — re-derive before use

The 2026-08-08 audit observed:

- `main` at `6404a186a7bb28a348325aa16074e07d0e3fb8c6`;
- Git tree `2d47d224f206d810839655419389d30500b66d53` locally and on GitHub;
- a clean worktree with `main...personal/main` at `+0/-0`;
- installed `GrokBuild.app` stamped `personal • main @ 6404a186`, `dirty=false`;
- installed and `dist` executable SHA-256
  `360777b69de63b3fd72e4b021f4d376cc3697c5927f75c9195e193096699e68b`;
- valid deep/strict Apple Development signing under Team `DD2GCQJVB4`;
- Grok CLI `1.0.0 (3cd0d0cbcebe) [stable]`;
- `656` tests passing with zero failures.

These are provenance receipts, not frozen expected values. Every slice must derive
the current commit, tree, hashes, test count, app version, and CLI version again.

---

## Mandatory workflow for every slice

The sequence is deliberately repetitive. Repetition is cheaper than shipping the
wrong branch, accepting a dirty bundle, or leaving eight helper processes squatting
in memory like they pay rent.

### Gate A — start clean and canonical

Before editing:

```bash
cd '/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop'
pwd
git status --porcelain=v2 --branch
git branch --show-current
git rev-parse HEAD
git remote -v
git ls-remote --heads personal main
gh auth status
```

Requirements:

1. `pwd` is the canonical worktree.
2. The starting branch is `main`.
3. `main` is clean and matches `personal/main` exactly.
4. `personal` is Jimmy's repository and `origin` is the preserved upstream.
5. `gh` is actively authenticated as `schmitzjimmy1-star`.
6. No unreviewed user changes exist. If the worktree is dirty, stop; do not stash,
   reset, checkout, or absorb unrelated paths.
7. The installed bundle stamp names the personal repository, branch `main`, current
   `HEAD`, and `dirty=false`.

Record the starting `HEAD`, Git tree, installed stamp, executable hash, app version,
CLI version, and pre-existing GrokBuild-owned PIDs in the slice receipt.

### Gate B — create one branch with one bounded scope

Branch naming:

```text
codex/grokbuild-audit-s<slice>-<short-purpose>
```

Examples:

- `codex/grokbuild-audit-s1-activity-truth`
- `codex/grokbuild-audit-s2-browser-capability`

Rules:

- One branch and one PR per slice.
- Touch only files named in the slice plus directly necessary tests/docs.
- Document any compile-mandated extra file before editing it.
- Do not combine nearby cleanup, dependency upgrades, formatting sweeps, config
  migration, or another slice.
- Add focused behavioral tests before broad static-source assertions.
- Update `ARCHITECTURE.md`, `README.md`, and this ledger in the same slice when
  ownership, visible behavior, persistence, or acceptance changes.

### Gate C — pre-publication verification

At minimum:

```bash
swift test --filter <focused-suite-or-test>
make test
git diff --check
git status --short
git diff --stat
git diff -- <every-intended-path>
```

Then package/sign/install only through the repository `make` workflow and perform
Computer Use acceptance against `/Applications/GrokBuild.app`, not `.build`, a static
preview, or a helper alone. The candidate bundle must report the slice branch/commit
and the correct dirty state. Never treat a green test suite as installed acceptance.

Provider calls are forbidden unless the slice explicitly names a bounded live probe.
For every permitted probe, freeze the exact prompt, model, maximum number of turns,
allowed tools, expected marker, and stop condition before sending it. Disable retries
in the prompt. Record exact model, route, calls, tokens, tool receipts, outcome, and
test-thread IDs. Never infer downstream OpenRouter serving-provider identity.

#### Skeptical billable-acceptance rule

Every product-changing slice (Slices 1–6) must run its complete billable matrix. A
single green prompt, exact marker, polished answer, successful parent turn, configured
MCP, ready badge, or model-picker label is never acceptance by itself.

For every matrix:

1. Use fresh disposable sessions with exact `GB-S<slice>-...` markers. Never reuse
   provider-specific web/tool history across models.
2. Cover at least these four evidence classes across the slice's prompts:
   - a normal successful path;
   - an intentional tool or capability failure;
   - a multi-tool or multi-step path that proves ordering and exact tool identity;
   - a subagent/worker path whenever the changed projection, lifecycle, MCP, Activity,
     navigation, or process ownership can be affected by child work.
3. Use representative routes: native Grok, one direct provider, and one pinned
   OpenRouter model across the matrix unless the slice explicitly documents why a lane
   cannot exercise the changed feature.
4. Freeze the prompt packet before sending: exact model, route, effort, parent turns,
   maximum children, permitted tool names/servers, forbidden tools, retry rule, expected
   marker, and failure expectation.
5. Default to one parent turn, no automatic retry, and no more than two child workers.
   Multi-turn continuity must be intentional and named in the matrix.
6. Inspect the visible transcript, expanded tool/worker rows, Activity Live state,
   Activity Settled state, model-route receipt, backend session history, usage ledger,
   and process tree. A success marker proves only that text was emitted.
7. Reconcile requested, configured, discovered, invoked, succeeded/failed, and settled
   facts separately. Never promote one layer into another.
8. A subagent counts only when `spawn_subagent` (or the current authoritative worker
   tool) has an exact child identity and the child has terminal lifecycle evidence.
   Parent prose claiming “I delegated” is worthless.
9. A multi-tool prompt counts only when each expected tool has its own authoritative
   receipt in the required order. One search/discovery call is not browser execution.
10. Record every unexpected retry, extra model call, worker, tool, token jump, provider
    mismatch, or lingering process as a failure or explicit variance. Do not average it
    into a green conclusion.
11. Stop the matrix when its slice token ceiling is reached. Preserve the partial
    receipt and report the budget stop; do not silently exceed the ceiling.
12. Delete every exact matrix thread under Gate F and finish at process zero under
    Gate G. A matrix that leaves test history or owned processes behind is failed.

Slice 0 is the sole no-prompt exception: it changes only this execution contract and
deletes prior audit-only threads. Creating a new billable thread merely to test thread
deletion would manufacture the residue the slice exists to remove.

### Gate D — commit, push, PR, checks, and merge

After the candidate passes:

1. Re-run `git status --short`, `git diff --check`, and the intended-path review.
2. Stage only the slice paths; never use broad staging while unrelated changes exist.
3. Commit with a slice-specific message, for example:
   `Fix Activity completion truth (slice 1)`.
4. Push the slice branch to `personal` with an ordinary non-force push.
5. Open a PR against `schmitzjimmy1-star/grok-build-desktop:main` using the curated
   GitHub Publish Changes workflow. The PR body must contain:
   - objective and exclusions;
   - exact files;
   - focused/full test receipts;
   - installed-app receipt;
   - provider spend, if any;
   - test-thread ledger;
   - rollback boundary.
6. Verify the PR head SHA and changed-file tree equal the reviewed local commit.
7. Wait for required checks and review; do not merge red, pending, or scope-expanded
   work.
8. Merge with a normal merge commit, matching current repository history.
9. Do not delete local or remote branches unless Jimmy separately authorizes it.
10. Never push or open a PR against `origin`.

If ordinary terminal push is blocked by Codex policy, the exact-tree
`github-safe-publish` skill is the allowed fallback. Authentication failure, branch
protection, a dirty worktree, or GitHub rejection is not a reason to use that fallback.

### Gate E — rebuild and accept merged `main`

After GitHub reports the PR merged:

```bash
git switch main
git pull --ff-only personal main
git status --porcelain=v2 --branch
git rev-parse HEAD
git ls-remote --heads personal main
make ship
```

`make ship` must run from the clean merged `main`, producing an installed app whose
stamp equals the merge commit and whose `dirty` flag is false. Repeat the slice's
focused installed-app acceptance on this exact merged build. A pre-merge branch build
does not substitute for post-merge `main` acceptance.

### Gate F — remove exact test threads

Every live acceptance thread must use a unique marker:

```text
GB-S<slice>-<purpose>-<YYYYMMDDTHHMMSS>
```

Before deletion, record:

- marker and exact prompt;
- local tab UUID;
- backend Grok session ID;
- model and route;
- process generation and PID;
- outcome/tool receipt;
- calls/tokens/cost metadata;
- screenshot or accessibility receipt path.

Cleanup order:

1. Switch away from the test session.
2. Close its GrokBuild tab so it is neither open nor active.
3. Open **Sessions**, search the exact marker, and verify the returned backend ID
   matches the ledger.
4. Delete that one session through GrokBuild's Sessions UI, accepting its permanent
   deletion confirmation. Alternatively use
   `grok sessions delete <exact-ledgered-id>` from the canonical workspace.
5. Search the exact marker again; it must return zero sessions.
6. Verify the closed local tab does not reappear after a quit/relaunch round trip.
7. Search GrokBuild transcript storage and `~/.grok/sessions` for the exact marker.
   Expected result: no retained slice-test transcript. If exact-marker residue remains,
   stop and classify it; do not manually `rm` history around it.

Never use **Clear Empty** as slice cleanup. Never delete by age, summary resemblance,
model, or a broad glob. If the exact ID cannot be proven, preserve the thread and stop.

### Gate G — quit and prove nothing GrokBuild-owned is running

After test-thread cleanup and final screenshots:

1. Quit GrokBuild normally with **GrokBuild → Quit GrokBuild** or Command-Q.
2. Wait up to five seconds for graceful teardown.
3. Verify no exact GrokBuild-owned executable remains:

```bash
pgrep -x GrokBuild
pgrep -x grok
pgrep -x GrokBuildComputerUseMCP
pgrep -x agent-desktop
```

Each command must return no PID. Also inspect for GrokBuild-owned browser processes:

```bash
ps -axo pid=,ppid=,command= | rg \
  'GrokBuild/BrowserProfiles|\.agent-browser/browsers'
```

Normal user Chrome processes are out of scope and must not be killed. If an owned
process remains, capture PID, PPID, command, elapsed time, and CPU first. Send `TERM`
only to the exact proven orphan, wait five seconds, and use `KILL` only when graceful
teardown failed and the receipt records why. Never use a broad `pkill -f grok` or kill
unrelated Codex/Claude/browser processes.

Process-zero is an acceptance requirement, not an optimization suggestion. The next
slice cannot start while a prior installed app, `grok agent stdio`, bundled Computer
Use MCP, `agent-desktop`, or managed browser runtime remains alive.

### Gate H — final identity/version/parity receipt

With the app stopped, verify the installed artifact and merged repository:

```bash
HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote personal refs/heads/main | awk '{print $1}')"
STAMP_SHA="$(plutil -extract GrokBuildSourceCommit raw \
  /Applications/GrokBuild.app/Contents/Info.plist)"
STAMP_BRANCH="$(plutil -extract GrokBuildSourceBranch raw \
  /Applications/GrokBuild.app/Contents/Info.plist)"
STAMP_REPO="$(plutil -extract GrokBuildSourceRepository raw \
  /Applications/GrokBuild.app/Contents/Info.plist)"
STAMP_DIRTY="$(plutil -extract GrokBuildSourceDirty raw \
  /Applications/GrokBuild.app/Contents/Info.plist)"

test "$HEAD_SHA" = "$REMOTE_SHA"
test "$HEAD_SHA" = "$STAMP_SHA"
test "$STAMP_BRANCH" = main
test "$STAMP_REPO" = 'https://github.com/schmitzjimmy1-star/grok-build-desktop'
test "$STAMP_DIRTY" = false

diff -qr dist/GrokBuild.app /Applications/GrokBuild.app
shasum -a 256 \
  dist/GrokBuild.app/Contents/MacOS/GrokBuild \
  /Applications/GrokBuild.app/Contents/MacOS/GrokBuild
codesign --verify --deep --strict --verbose=2 /Applications/GrokBuild.app
codesign -dvvv /Applications/GrokBuild.app 2>&1 | rg 'TeamIdentifier=DD2GCQJVB4'
! xattr /Applications/GrokBuild.app | rg -qi quarantine
"$HOME/.grok/bin/grok" --version
git status --porcelain=v2 --branch
```

The two executable hashes must match, `diff -qr` must be silent, signing must pass,
quarantine must be absent, `main` must be clean at `+0/-0`, and the CLI version must
match Settings → App. Relaunch once for the visible Settings → App receipt, then quit
again and repeat Gate G so the slice ends at process zero.

---

## Slice 0 — baseline lock and audit-thread cleanup

### Objective

Make this ledger the merged source of truth, preserve the 2026-08-08 audit receipts,
and remove only the four billable audit threads created by that audit.

### Exact deletion inventory

These four backend IDs were created exclusively by the audit and may be deleted after
their durable receipt is preserved here:

| Backend ID | Marker/summary | Model lane | Audit result |
|---|---|---|---|
| `019fe3de-4ba5-7823-9dc5-dd72ffc499be` | `GROK45_TERM_OK` / Run `/bin/pwd` once | Grok 4.5 | Terminal success; 31,715 tokens, 2 calls |
| `019fe3df-2485-7d41-b93d-63797825201e` | `TERRA_FINAL_OK` / printf marker | GPT-5.6 Terra | Terminal success; 23,535 tokens, 2 calls |
| `019fe3df-e903-7151-aeb6-8d294bf7b4c0` | `DEEPSEEK_FAILURE_SEEN` / run `false` once | DeepSeek via OpenRouter | Exit 1 correctly visible; 29,566 tokens, 2 calls |
| `019fe3e2-d040-7a22-ac79-dd7f2a08d7fc` | `BROWSER_LIST_OK` / list open tabs | GPT-4.1 Mini via OpenRouter | Discovery succeeded but requested browser task did not; 23,815 tokens, 2 calls |

Do not delete any other session. Close their local tabs first, delete each exact backend
ID, prove all four searches return zero, quit GrokBuild, and pass process-zero.

### Files

- `docs/OUTSTANDING.md`
- historical receipt document only if a durable cross-reference is required

### Tests and acceptance

- Markdown links and commands reviewed manually.
- `git diff --check`.
- Canonical identity and installed-artifact receipt re-derived.
- Exact four-thread cleanup receipt.
- Process-zero receipt.

### Publication

Branch `codex/grokbuild-audit-s0-canonical-ledger`; commit, push, PR, normal merge
commit, resync `main`, and pass Gates E–H. Slice 1 cannot start until this plan itself
is merged and the four audit threads are gone.

### Slice 0 completion receipt — 2026-08-08

- Objective: establish this canonical seven-slice ledger and remove only the four
  audit-only sessions named above.
- Starting main SHA/tree: `6404a186a7bb28a348325aa16074e07d0e3fb8c6` /
  `2d47d224f206d810839655419389d30500b66d53`.
- Branch and content commit SHA:
  `codex/grokbuild-audit-s0-canonical-ledger` /
  `4aeea652a4094908f4e4ffb5d239f80512a5d2aa`.
- Intended files: `docs/OUTSTANDING.md` only.
- Unexpected files: none.
- Focused tests: documentation link/command review; all named paths and commands
  remained repository-relative or canonical absolute paths.
- Full `make test`: 656 tests, 0 failures in 23.950 seconds.
- `git diff --check`: clean.
- Candidate installed stamp/hash/signing: unchanged clean starting `personal/main`
  bundle at `6404a186a7bb28a348325aa16074e07d0e3fb8c6`, version `0.1.20`;
  installed/dist executable SHA-256
  `360777b69de63b3fd72e4b021f4d376cc3697c5927f75c9195e193096699e68b`;
  deep/strict Team `DD2GCQJVB4` baseline retained.
- Computer Use acceptance: installed app exposed all four exact audit tabs; each was
  closed through its own **Close Session** action before backend deletion, then the
  app selected an unrelated protected historical session which was left untouched.
- Provider prompts/models/routes: none; Slice 0 is the sole no-prompt control slice.
- Calls/tokens/cost: zero new calls, zero new tokens, zero new provider spend.
- Test thread markers/local tab IDs/backend IDs:
  - `GROK45_TERM_OK` / `62AEB90D-6D3A-4622-A39B-FCEE13D45467` /
    `019fe3de-4ba5-7823-9dc5-dd72ffc499be`;
  - `TERRA_FINAL_OK` / `64BBD584-6083-421A-B01B-0034FED1C460` /
    `019fe3df-2485-7d41-b93d-63797825201e`;
  - `DEEPSEEK_FAILURE_SEEN` / `E105C8A4-37EE-4015-B46E-88DA643DCF44` /
    `019fe3df-e903-7151-aeb6-8d294bf7b4c0`;
  - `BROWSER_LIST_OK` / `46E69CCD-59AF-4A0C-B88E-7FD3525DB26B` /
    `019fe3e2-d040-7a22-ac79-dd7f2a08d7fc`.
- Test thread deletion proof: each exact `grok sessions delete` returned success;
  every exact marker search returned `Total: 0`; all four backend directories and all
  eight local transcript/metadata paths were absent.
- Candidate process-zero proof: exact-name checks returned zero for `GrokBuild`,
  `grok`, `GrokBuildComputerUseMCP`, and `agent-desktop`; no GrokBuild-owned managed
  browser process remained.
- PR URL/number: `https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/22`.
  The immutable PR and final task receipt retain the final reviewed head, merge SHA,
  and post-merge Gates E–H values because those values do not exist until after this
  pre-merge source snapshot is created.
- Merge commit SHA: retained in PR #22 and the final task receipt after merge.
- Post-merge `main` installed stamp/hash/signing: retained in PR #22 and the final
  task receipt after Gate E.
- Post-merge visible acceptance: Settings → App receipt and quit/relaunch persistence
  retained in PR #22 and the final task receipt after Gate H.
- Final test thread deletion proof: the four exact marker searches remained zero
  before publication; repeated after merged-main relaunch under Gate F.
- Final process-zero proof: repeated after merged-main Settings → App acceptance under
  Gate G and retained in the final task receipt.
- CLI version and Settings → App agreement: CLI `1.0.0
  (3cd0d0cbcebe) [stable]`; visible agreement rechecked on merged `main` under Gate H.
- Worktree/personal-main parity: required after PR #22 merge and recorded in the final
  task receipt.
- Known residual risk: none within Slice 0; Slices 1–6 remain deliberately open and
  unstarted.
- Exact next slice: Slice 1 — truthful completion and next-action language. Do not
  begin it in this task.

---

## Slice 1 — truthful completion and next-action language

### Problem

`turn_completed` proves transport/lifecycle completion, not that the user's requested
task succeeded. The audit's browser request was not completed, yet Activity rendered
“Everything finished and checked out” and “No further action reported” because the
tool-discovery call itself succeeded and no failed tool receipt existed.

### Required behavior

1. Keep authoritative distinctions among completed, stopped, missing receipt, active
   workers, and failed tools.
2. Replace goal-success language with bounded lifecycle language. Recommended neutral
   success copy: **“Turn completed; no tool or worker failures were reported.”**
3. Replace **“No further action reported”** with wording that attributes the absence
   to the agent/receipt, not to objective truth, for example
   **“The agent reported no next action.”**
4. Never infer task satisfaction from a successful tool, final text, requested marker,
   or parent `turn_completed`.
5. Preserve the strong failed-terminal path: unresolved count, exit status, failed-tool
   count, and review-next-action.

### Primary files

- `GrokBuild/Views/ActivitySidebar.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Models/RunEvidenceSnapshot.swift` if the contract needs a typed field
- `Tests/GrokBuildTests/ActivitySidebarTests.swift`
- `Tests/GrokBuildTests/RunEvidenceSnapshotTests.swift`
- `Tests/GrokBuildTests/ACPClientContractTests.swift`
- `ARCHITECTURE.md`
- `README.md` if user-visible Activity wording is documented
- this ledger

### Required tests

- Completed turn + succeeded discovery tool + assistant says it cannot perform the
  request must not render goal-success language.
- Completed turn with zero tool failures uses neutral completion copy.
- Failed terminal still renders failed and unresolved receipts.
- Missing `turn_completed` remains incomplete.
- User Stop remains stopped, never completed.
- Active/unknown/orphaned workers remain non-successful.
- `nextAction` text is explicitly attributed and bounded.

### Installed acceptance

Run all four frozen prompts; token ceiling **220K total**:

| Prompt | Route | Frozen work | Required skeptical evidence |
|---|---|---|---|
| S1-A success | Native Grok | Run `/bin/pwd` exactly once, then emit `GB-S1-SUCCESS`; no other tool or retry. | One terminal receipt, exit 0, neutral completion wording, exact live model, no invented next action. |
| S1-B failure | Direct provider | Run `/usr/bin/false` exactly once, then explain the observed failure and emit `GB-S1-FAILURE`; no retry. | Terminal exit 1 overrides outer completion; failed/unresolved counts remain visible after parent completion. |
| S1-C unmet task | Pinned OpenRouter | Search/discover one deliberately absent read-only browser capability, do not substitute or navigate, and emit `GB-S1-UNAVAILABLE`. | Discovery may succeed; requested task remains unavailable; Activity must not say checked out or convert discovery into browser use. |
| S1-D worker variance | Native Grok | Spawn exactly one child to run `/usr/bin/false`; parent must collect it and perform no other tool; emit `GB-S1-WORKER`. | Exact child identity, terminal child lifecycle, child failure/unresolved state, parent completion kept separate from worker success. |

For every prompt confirm exact live model/route, requested versus actual tools, worker
identity where applicable, transcript, Live/Settled Activity, backend history, usage,
and process ownership. The exact markers are lookup handles, not success criteria.

Delete the exact test thread, quit, prove process-zero, merge, rebuild merged `main`,
repeat S1-B and S1-C as the minimum merged-main smoke, delete those new threads, then
pass Gates F–H.

### Slice 1 completion receipt — 2026-08-08

- Objective: keep parent `turn_completed` lifecycle truth separate from requested-task,
  terminal-tool, and child-tool outcome truth; attribute an empty next-action receipt
  to the agent.
- Starting main SHA/tree: `7a9566fdfc7790853326292c9e06279fac601545` /
  `46198928e2e490344e48bc1417ccb0b1105e49a2`.
- Branch and content commit SHA: `codex/grokbuild-audit-s1-activity-truth` / retained
  by the immutable Slice 1 PR and final task receipt after this pre-merge snapshot.
- Intended files: `ARCHITECTURE.md`, `GrokBuild/Models/RunEvidenceSnapshot.swift`,
  `GrokBuild/Services/ChatStore.swift`, `GrokBuild/Views/ActivitySidebar.swift`,
  `Tests/GrokBuildTests/ACPClientContractTests.swift`,
  `Tests/GrokBuildTests/ActivitySidebarTests.swift`,
  `Tests/GrokBuildTests/RunEvidenceSnapshotTests.swift`, and this ledger.
- Unexpected files: none.
- Focused tests: 17 Activity sidebar tests and 3 snapshot tests passed; the ACP
  completion/failure source contract passed in the full ACP suite.
- Full `make test`: 662 tests, 0 failures in 24.195 seconds; candidate `make ship`
  repeated 662 tests, 0 failures in 23.467 seconds.
- `git diff --check`: clean.
- Candidate installed stamp/hash/signing: `personal` /
  `codex/grokbuild-audit-s1-activity-truth` / `7a9566fd`, `dirty=true`, version
  `0.1.20`; installed/dist executable SHA-256
  `7fa72bdcf993ddceb1a167133286a0e355c8eec518c14ad6d93f3e35cd0c5cbc`;
  Apple Development Team `DD2GCQJVB4`, deep/strict valid, no quarantine.
- Computer Use acceptance: S1-A rendered neutral lifecycle completion and attributed
  next action; S1-B retained exit 1, one failed tool, one unresolved error, and review
  action after parent completion; S1-C admitted the missing capability without
  claiming navigation/browser use or task success; the first S1-D exposed that a
  completed child lifecycle hid its internal exit 1, and corrective S1-D-R2 visibly
  rendered `1 worker receipt remains unresolved`, retained the completed lifecycle,
  and stated that child tool outcomes were not reported to the parent receipt.
- Provider prompts/models/routes: S1-A native Grok 4.5; S1-B direct
  `gpt-5.6-terra`; S1-C pinned `deepseek/deepseek-v4-flash-0731` through OpenRouter;
  S1-D and S1-D-R2 native Grok 4.5. All were Medium, one parent turn, no retry, and
  live receipts confirmed the requested model/route with no GrokBuild fallback.
- Calls/tokens/cost: S1-A 2 calls / 31,913 tokens; S1-B 2 / 23,791; S1-C 2 / 30,689
  (OpenRouter estimated $0.0028-$0.0055); S1-D 5 / 73,379; corrective S1-D-R2 5 /
  73,276. Total: 16 model calls / 233,048 tokens; cost unavailable where the route
  receipt did not expose pricing.
- Test thread markers/local tab IDs/backend IDs:
  - `GB-S1-SUCCESS-20260808T210645` / `76A87109-A2AA-4367-873C-B99E2D6D508C` /
    `019fe410-3fb5-7e00-b09a-dca2b006eefc`;
  - `GB-S1-FAILURE-20260808T210646` / `0B35A187-51D3-4C30-9360-7BEC054E8FF4` /
    `019fe411-b540-7141-aa9c-906054c71286`;
  - `GB-S1-UNAVAILABLE-20260808T210647` / `4B1C3693-3ADF-4718-81B8-35B4C4B2951F` /
    `019fe412-eb36-7362-a26a-b46c005e9857`;
  - `GB-S1-WORKER-20260808T210648` / `275BC577-64C7-4E5F-B7EC-1D1FBCB058C8` /
    `019fe416-b9c8-7eb2-9955-cc41d1e06a49`;
  - `GB-S1-WORKER-R2-20260809T013826Z` / `5D49AF7F-8B48-472C-83DD-6504EE754F7E` /
    `019fe42c-a960-7120-b4f1-144e92e9dda6`.
- Test thread deletion proof: pending exact Gate F cleanup after merge; no non-test
  session is authorized for deletion.
- Candidate process-zero proof: exact-name checks returned zero for `GrokBuild`,
  `grok`, `GrokBuildComputerUseMCP`, `agent-desktop`, and GrokBuild-owned browser MCP.
- PR URL/number and reviewed head SHA: retained in the immutable Slice 1 PR and final
  task receipt after publication.
- Merge commit SHA: retained in the Slice 1 PR and final task receipt after merge.
- Post-merge `main` installed stamp/hash/signing: pending Gate E.
- Post-merge visible acceptance: pending the required S1-B/S1-C merged-main smoke.
- Final test thread deletion proof: pending Gate F.
- Final process-zero proof: pending Gate G.
- CLI version and Settings -> App agreement: CLI `1.0.0
  (3cd0d0cbcebe) [stable]`; visible merged-main agreement pending Gate H.
- Worktree/personal-main parity: pending normal PR merge and `main` resync.
- Known residual risk: ACP currently reports a child's terminal lifecycle and tool
  count but not typed per-child tool outcomes to the parent; completed workers that
  invoked tools therefore remain explicitly outcome-unresolved instead of being
  promoted from final child prose.
- Exact next slice: Slice 2 - browser readiness and capability truth. Do not begin it
  until Slice 1 merges and Gates E-H pass.

---

## Slice 2 — browser readiness and capability truth

### Problem

The UI reported `grokbuild-browser ready`, while the model's tool discovery surfaced a
`chrome-devtools` inventory that could open/load but could not list existing pages. A
configured/settled MCP process was presented adjacent to a turn that never exercised
the requested browser capability.

### Required behavior

Model four separate facts and never collapse them:

1. **Configured:** the server exists in applied session configuration.
2. **Process ready:** the owning process passed its bounded MCP startup barrier.
3. **Capability discovered:** the exact required tool was present in the current
   catalog, with authoritative server and qualified tool name.
4. **Capability exercised:** a current-turn tool receipt proves the exact tool ran and
   records success/failure.

Additional requirements:

- A prompt attachment requests a server; it does not prove use.
- A successful search/discovery tool is labeled as discovery, not browser execution.
- Activity “Sources” must name only servers evidenced by current-turn tool receipts.
- If a requested browser capability is absent, surface **Unavailable for this turn**
  with the missing qualified tool; do not emit or bless a success marker.
- Reconcile `grokbuild-browser` versus `chrome-devtools` identities from authoritative
  tool/catalog receipts. Do not alias by guesswork.
- Keep readiness bounded and secret-free; no URLs, headers, tokens, or environment
  values enter Activity.

### Primary files

- `GrokBuild/Services/MCPReadinessPolicy.swift`
- `GrokBuild/Services/GrokProcess.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/Models/ComposerModels.swift`
- `GrokBuild/Views/ComposerViews.swift`
- `GrokBuild/Views/ActivitySidebar.swift`
- `GrokBuild/Views/ChatView.swift`
- `Tests/GrokBuildTests/MCPReadinessTests.swift`
- `Tests/GrokBuildTests/ChatTranscriptLayoutTests.swift`
- `Tests/GrokBuildTests/ACPClientContractTests.swift`
- `Tests/GrokBuildTests/ActivitySidebarTests.swift`
- `ARCHITECTURE.md`
- `README.md`
- this ledger

### Required tests

- Configured but not started is not ready/discovered/used.
- Ready without tool inventory is process-ready only.
- Discovery receipt does not count as browser action.
- Qualified `chrome-devtools__list_pages` maps to `chrome-devtools` only when that
  authoritative name is present.
- `grokbuild-browser` is never synthesized from prompt attachment alone.
- Requested-but-absent tool produces unavailable, not failed or succeeded use.
- Exact tool failure remains failed even when parent turn completes.
- Restored transcripts retain past actual-use receipts without promoting current
  readiness.

### Installed acceptance

Run all five frozen prompts against a disposable local proof page; token ceiling
**320K total**:

| Prompt | Route | Frozen work | Required skeptical evidence |
|---|---|---|---|
| S2-A requested only | Native Grok | Attach/request the exact browser MCP, then answer a static arithmetic question without calling tools; emit `GB-S2-REQUESTED`. | Requested/configured server visible; no discovered/used/source claim and zero tool receipts. |
| S2-B discovery only | Direct provider | Search for the exact list-pages capability once, do not invoke it; emit `GB-S2-DISCOVERY`. | Discovery tool receipt is labeled discovery and never presented as browser execution. |
| S2-C multi-tool success | Pinned OpenRouter | On the disposable local page, list pages, inspect the target, and read one exact marker in that order; maximum three browser calls; emit `GB-S2-MULTI`. | Three ordered qualified tool receipts, authoritative server identity, requested/discovered/used separation, exact page marker. |
| S2-D absent capability | Pinned OpenRouter | Request one frozen nonexistent browser tool; do not substitute, navigate, or retry; emit `GB-S2-ABSENT`. | Unavailable state, no false tool failure/success, no generic checked-out claim. |
| S2-E child browser use | Native Grok | Spawn one child that performs exactly one read-only inspection of the disposable page; parent waits/collects and emits `GB-S2-WORKER`. | Exact child identity and terminal lifecycle; child's browser receipt attributed to the child/server without becoming an invented parent tool receipt. |

The disposable page must be local, deterministic, non-authenticated, and contain a
unique marker. Record requested MCP chips, catalog results, qualified tool names,
server identities, invocation order, tool results, worker receipts, model route, usage,
and process tree for every prompt. Final prose does not repair missing receipts.

Delete the thread and any managed-browser test page/profile artifact owned by this
slice, without touching the user's normal Chrome profile. Quit, process-zero, merge,
rebuild merged `main`, repeat S2-A, S2-C, and S2-D as the merged-main smoke, remove all
new threads/artifacts, and pass Gates F–H.

---

## Slice 3 — Browser Settings unresolved/checking state

### Problem

`BrowserSettingsPane` initializes `BrowserBackendStatus` to `.unavailable`, immediately
renders “Setup needed” and install controls, then corrects itself after asynchronous
status discovery. A healthy install visibly flashes a false failure.

### Required behavior

- Add an explicit unresolved/loading state distinct from unavailable.
- On first presentation, show **Checking browser support…** with neutral styling.
- Do not show install commands, setup-needed copy, destructive runtime controls, or a
  red/error badge until the first status probe resolves.
- Keep the last settled status during a manual refresh and add a small checking
  indicator; do not regress the whole pane to unavailable.
- Cancel stale probes when the pane disappears or applied settings generation changes.
- A failed probe shows a bounded error and Retry without discarding the last proven
  status unless that status is no longer applicable.

### Primary files

- `GrokBuild/Views/Settings/BrowserSettingsPane.swift`
- `GrokBuild/Services/AgentBrowserService.swift` only if a typed probe state belongs
  in the service
- `Tests/GrokBuildTests/BrowserIntegrationTests.swift`
- `Tests/GrokBuildTests/SettingsTabTests.swift`
- `ARCHITECTURE.md`
- `README.md` if visible setup wording changes
- this ledger

### Required tests

- Initial unresolved state never contains “Setup needed” or install instructions.
- Ready resolution moves once from checking to ready.
- Missing runtime moves once from checking to setup-needed.
- A stale slower probe cannot overwrite a newer result.
- Manual refresh preserves the prior settled presentation while checking.
- Leaving the pane cancels view-owned work without mutating draft/applied settings.

### Installed acceptance

First open Settings → Browser from a cold pane creation and capture the initial and
settled frames. Then run all three frozen prompts; token ceiling **180K total**:

| Prompt | Route | Frozen work | Required skeptical evidence |
|---|---|---|---|
| S3-A pre/post round trip | Native Grok | Read one marker from the disposable local browser page, open/close Browser Settings during the idle settled session, then ask a second turn to read the same marker again. | Exact same backend/model continuity, browser tool succeeds before and after, no configuration reload or false setup state. |
| S3-B multi-tool while probing | Pinned OpenRouter | While Browser Settings performs a manual diagnostics refresh, run one terminal `pwd` and one read-only browser inspection; emit `GB-S3-MULTI`. | Both ordered receipts settle; the pane remains checking/ready rather than setup-needed; no process generation changes. |
| S3-C child after pane recreation | Direct provider | Close/reopen Browser Settings, then spawn one child for exactly one read-only browser inspection; parent collects and emits `GB-S3-WORKER`. | Fresh pane begins unresolved/checking, child has exact identity/tool receipt, no stale probe overwrites Ready, no extra helper/process survives. |

Confirm a healthy install never flashes failure, install/destructive controls stay
suppressed until the probe resolves, and Settings navigation does not change applied
configuration. Delete all three threads, quit, process-zero, merge, rebuild merged
`main`, repeat S3-A and the cold-pane check, delete the smoke thread, and pass Gates
F–H.

---

## Slice 4 — compact Computer Use end-to-end receipt

### Problem

The real self-test correctly calls `initialize` and `computer_list_apps`, but success
renders a truncated raw JSON process inventory containing PIDs and process-instance
identifiers. That is noisy, visually hostile, and more process disclosure than the
main success surface needs.

### Required behavior

- Parse the helper response into a typed, secret-free receipt.
- Main success presentation should include only:
  - pass/fail;
  - protocol/helper version;
  - command (`computer_list_apps`);
  - returned app count;
  - bounded duration;
  - whether Accessibility/screenshot prerequisites were required and proven.
- Put bounded redacted raw output behind **Show diagnostics** only.
- Never render PIDs, process-instance IDs, command lines, paths, window titles, or app
  inventory in the default success message.
- Malformed JSON, JSON-RPC error, wrong final request ID, timeout, empty content, and
  helper exit failure must remain distinct failures.

### Primary files

- `GrokBuild/Services/ComputerUseService.swift`
- `GrokBuild/Views/Settings/ComputerUseSettingsPane.swift`
- `Tests/GrokBuildTests/ComputerUseIntegrationTests.swift`
- `Tests/GrokBuildTests/SettingsTabTests.swift`
- `ARCHITECTURE.md`
- `README.md` if the diagnostic contract is user-documented
- this ledger

### Required tests

- Valid list-apps response becomes a compact typed receipt with correct app count.
- Default presentation contains no PID/process-instance/raw JSON.
- Diagnostics remain bounded and redact known sensitive fields.
- Empty content and malformed JSON fail closed.
- JSON-RPC error, timeout, and nonzero helper exit remain distinguishable.
- Repeated tests do not leave `agent-desktop` or MCP helpers running.

### Installed acceptance

Run **Test Computer Use** first through the installed app, then run all four frozen
billable prompts; token ceiling **240K total**:

| Prompt | Route | Frozen work | Required skeptical evidence |
|---|---|---|---|
| S4-A list apps | Native Grok | Invoke Computer Use list-apps exactly once and emit `GB-S4-LIST`; no screenshot. | Exact qualified tool/server, success receipt, bounded app count, no raw PID/process-instance dump in the main presentation. |
| S4-B inspect app | Direct provider | Inspect GrokBuild semantically once, no click/type/screenshot, then emit `GB-S4-INSPECT`. | Read-only action receipt, target bundle/process identity, no mutation and no raw inventory spill. |
| S4-C intentional failure | Pinned OpenRouter | Request inspection of a frozen nonexistent bundle ID once; no fallback/retry; emit `GB-S4-FAIL`. | Failed/unavailable receipt stays distinct from parent completion; bounded redacted diagnostic only. |
| S4-D child Computer Use | Native Grok | Spawn one child to list apps exactly once; parent waits/collects and emits `GB-S4-WORKER`. | Exact child lifecycle and tool attribution; helper exits after child completion; parent does not duplicate the child's tool receipt. |

The non-billable Settings self-test and billable model-driven path must agree on helper
version and command contract. Record before/during/after process lists for each prompt.
The main pane stays compact, diagnostics remain opt-in, and no temporary helper survives.
Delete all threads, quit, process-zero, merge, rebuild merged `main`, repeat the Settings
self-test plus S4-C and S4-D, delete smoke threads, and pass Gates F–H.

---

## Slice 5 — navigation-rail accessibility selection

### Problem

The accessibility tree repeatedly reported **Security** as selected while a normal
conversation was active. The rail is implemented as stateless action buttons, so the
reported selection has no reliable relationship to the visible route.

### Required behavior

- Decide and document whether rail items are navigation destinations or action buttons.
- For transient sheets/settings destinations, expose ordinary buttons with no selected
  trait after the destination closes.
- If a persistent route is active, bind selected state to the real `AppRoute` and render
  the same state visually, semantically, and in accessibility.
- New chat, Sessions, Plugins, Security, project rows, and session rows must not claim
  simultaneous selection.
- Keyboard focus is not selection; hover is not selection; the last-clicked button is
  not selection after returning to the conversation.

### Primary files

- `GrokBuild/Views/SidebarView.swift`
- `GrokBuild/ContentView.swift`
- `Tests/GrokBuildTests/CodexShellParityTests.swift`
- `Tests/GrokBuildTests/SidebarActivityTests.swift`
- accessibility-focused tests in `Tests/GrokBuildTests/`
- `ARCHITECTURE.md`
- `README.md` only if navigation behavior changes visibly
- this ledger

### Required tests

- Active conversation: no Security/Plugins/Sessions button claims selected.
- Open Permissions through Security: only the actual destination is represented.
- Close Settings: selection returns to the real conversation/project/session.
- Keyboard focus moves without mutating selection.
- Selected workspace/session state remains correct and independent from rail actions.
- Accessibility identifiers remain stable for Computer Use automation.

### Installed acceptance

Capture fresh accessibility trees after New chat, Sessions open/close, Plugins
open/close, Security open/close, project switch, and session switch, then run all three
frozen prompts; token ceiling **200K total**:

| Prompt | Route | Frozen work | Required skeptical evidence |
|---|---|---|---|
| S5-A live terminal navigation | Native Grok | Run a five-second terminal command that emits `GB-S5-LIVE`; while it is live, round-trip Sessions and return to the same conversation. | Live model/process and Stop state remain on the real session; rail/sheet selection is accurate; terminal settles once. |
| S5-B live child navigation | Direct provider | Spawn one child to run a bounded five-second wait then `pwd`; while active, round-trip Security/Permissions and return; parent collects `GB-S5-WORKER`. | Exact parent/child identities survive navigation; no rail item remains falsely selected; worker Live→Settled transition is intact. |
| S5-C multi-tool route switching | Pinned OpenRouter | Run terminal `pwd` then one read-only Computer Use inspect in order; while settled, open/close Plugins and switch away/back to the session; emit `GB-S5-MULTI`. | Both receipts remain attached to the correct turn; selection and keyboard focus do not rewrite model/tool/session identity. |

For every navigation stop, compare visual highlight, AX selected state, keyboard focus,
selected project, selected session, and route. Delete all threads, quit, process-zero,
merge, rebuild merged `main`, repeat S5-B plus the full AX round trip, delete the smoke
thread, and pass Gates F–H.

---

## Slice 6 — tiny-turn context cost and deterministic lifecycle closeout

### Problem

Four trivial audit prompts consumed 108,631 tokens across eight model calls:

| Lane | Tokens | Calls |
|---|---:|---:|
| Grok 4.5 terminal `pwd` | 31,715 | 2 |
| GPT-5.6 Terra terminal `printf` | 23,535 | 2 |
| DeepSeek/OpenRouter failed `false` | 29,566 | 2 |
| GPT-4.1 Mini/OpenRouter browser discovery | 23,815 | 2 |

Two calls for tool-use plus final synthesis may be legitimate. Shipping 23–32K tokens
for a microscopic single-tool task is the optimization target. The same audit retained
four `grok agent stdio` processes plus four Computer Use MCP helpers—approximately
420 MiB combined RSS—until app shutdown.

### Required behavior

#### Context/tool-cost contract

- Measure, do not guess, where prompt tokens come from: base instructions, workspace
  context, MCP/tool schemas, session history, skills, memory, and provider wrappers.
- Preserve model-routing, safety, permission, receipt, and continuity contracts.
- Prefer progressive discovery and exact requested MCP/tool schemas over loading every
  available capability into tiny turns.
- Do not silently remove tools, memory, project instructions, or provider features.
- Do not add a second proxy, fallback route, SDK, runtime, or background daemon.
- Add a deterministic prompt-packet measurement fixture that can compare byte/token
  contributors without sending a provider request.
- Establish an evidence-backed target only after the baseline fixture exists. The first
  target should be a meaningful reduction in non-user context for a one-tool fresh turn,
  with zero loss of required contract fields.

#### Process ownership contract

- Keep the existing maximum of four connected sessions unless measurements justify a
  different cap.
- Closing a tab must terminate its owned Grok process and bundled MCP children.
- Quitting the app must leave zero owned Grok, Computer Use, `agent-desktop`, and managed
  browser processes within five seconds.
- LRU eviction must preserve exact backend continuity while terminating children.
- A self-test helper must not survive its result.
- Add a reusable test-only process ledger keyed by tab, backend, generation, PID, and
  child PID; never kill by approximate name inside production code.

### Primary files

- `GrokBuild/Services/GrokProcess.swift`
- `GrokBuild/Services/ChatStore.swift`
- `GrokBuild/ContentView.swift`
- `GrokBuild/Services/MCPReadinessPolicy.swift`
- prompt/context assembly owners identified by measurement
- `GrokBuild/Services/ComputerUseService.swift` only if helper teardown needs repair
- `Tests/GrokBuildTests/ACPClientContractTests.swift`
- `Tests/GrokBuildTests/LifecycleAndSubprocessTests.swift`
- `Tests/GrokBuildTests/MCPReadinessTests.swift`
- new focused context-budget fixture tests
- `ARCHITECTURE.md`
- `README.md` if user-visible lifecycle behavior changes
- this ledger

### Required tests

- Deterministic baseline and post-change prompt-packet contributor report.
- Tiny terminal turn retains exact model, permission, workspace, and required tool
  schemas while excluding unrelated inventories.
- Requested browser/Computer Use schema is present when explicitly selected.
- No cross-provider fallback or model substitution.
- Tab close, LRU eviction, app quit, failed launch, Stop, config reload, and helper
  self-test each terminate the correct generation's children.
- Wrong-tab/wrong-backend/wrong-generation teardown cannot kill another session.
- Five consecutive lifecycle fixture runs end with zero owned test processes.
- Full suite remains free of order-sensitive process leaks.

### Installed acceptance and billable comparison

After deterministic optimization passes, run all six frozen prompts; token ceiling
**480K total**:

| Prompt | Route | Frozen work | Required skeptical evidence |
|---|---|---|---|
| S6-A native tiny turn | Native Grok | Terminal `/bin/pwd` exactly once; emit `GB-S6-NATIVE`. | Direct comparison with 31,715-token audit baseline; exact packet contributors and one terminal receipt. |
| S6-B direct tiny turn | GPT-5.6 Terra/direct | Terminal `printf GB-S6-DIRECT` exactly once. | Direct comparison with 23,535-token baseline; no unrelated MCP/tool schema loaded. |
| S6-C OpenRouter failure | DeepSeek/OpenRouter | Terminal `/usr/bin/false` once, no retry; emit `GB-S6-FAIL`. | Comparison with 29,566-token baseline; failure semantics and route receipt unchanged. |
| S6-D multi-tool | GPT-4.1 Mini/OpenRouter | Terminal `pwd`, then read one marker from the disposable local browser page; maximum two tools; emit `GB-S6-MULTI`. | Exact ordered schemas/receipts; only explicitly needed terminal/browser context present. |
| S6-E Computer Use | Native Grok | Inspect GrokBuild once without screenshot or action; emit `GB-S6-COMPUTER`. | Computer Use schema appears only when required; helper starts and exits; no browser inventory pollution. |
| S6-F worker lifecycle | Native Grok | Spawn exactly two children in parallel: one terminal `pwd`, one read-only browser marker inspection; parent waits for both and emits `GB-S6-WORKERS`. | Two exact child identities and terminal receipts, parallel lifecycle evidence, bounded schemas, LRU/process ledger, zero children after close. |

Use medium effort only if required for audit comparability, no retries, and exact final
markers. Compare every prompt against its deterministic packet fixture and, when a
matching audit baseline exists, against that live baseline:

- exact live model and route;
- prompt/completion/total tokens when exposed;
- model-call count;
- loaded/requested/used MCPs;
- tool result and terminal exit;
- process and child RSS;
- post-close and post-quit process-zero.

Do not claim improvement from model variance alone. The deterministic packet fixture
must show what GrokBuild removed or deferred. The full matrix must exercise one-tool,
failure, multi-tool, Computer Use, and parallel subagent behavior without weakening any
route or receipt contract. Delete all six comparison threads, quit, process-zero, merge,
rebuild merged `main`, repeat S6-A, S6-D, and S6-F as the merged-main smoke, delete all
smoke threads, and pass Gates F–H.

---

## Slice receipt template

Append a completed receipt beneath the relevant slice before merging:

```markdown
### Slice N completion receipt — YYYY-MM-DD

- Objective:
- Starting main SHA/tree:
- Branch and commit SHA:
- Intended files:
- Unexpected files: none / explained
- Focused tests:
- Full `make test`:
- `git diff --check`:
- Candidate installed stamp/hash/signing:
- Computer Use acceptance:
- Provider prompts/models/routes:
- Calls/tokens/cost:
- Test thread markers/local tab IDs/backend IDs:
- Test thread deletion proof:
- Candidate process-zero proof:
- PR URL/number and reviewed head SHA:
- Merge commit SHA:
- Post-merge `main` installed stamp/hash/signing:
- Post-merge visible acceptance:
- Final test thread deletion proof:
- Final process-zero proof:
- CLI version and Settings → App agreement:
- Worktree/personal-main parity:
- Known residual risk:
- Exact next slice:
```

After a slice closes, mark its status **Merged and accepted** in the top table. Keep the
receipt in this ledger until all seven slices close; then move durable historical detail
to `docs/UI_ACCEPTANCE_MATRIX.md`, retain a compact close-out here, and restore the
status to **all clear**.

---

## Documented behaviors — not defects

These remain standing contracts unless a future explicitly authorized slice changes
them:

| # | Behavior | Source of truth |
|---|---|---|
| B-1 | Second-launch activation is unconditional and may foreground GrokBuild. | Existing architecture/close-out receipt |
| B-2 | System Events cannot reliably read AXDescription on SwiftUI elements; automation should use stable identifiers. | Existing accessibility receipt |
| C-1 | Cross-provider web/tool history is not replay-safe; start a new session when switching providers after such a turn. | `docs/TOOL_USE_AND_MULTI_TURN_CONTRACT.md` |
| C-2 | A compound multi-MCP first turn may need one same-session retry on fast OpenRouter routes while servers connect. Slice 2 may tighten presentation but must not rewrite history. | `docs/TOOL_USE_AND_MULTI_TURN_CONTRACT.md` |
| C-3 | Changed-files counts refresh at selection/turn boundaries rather than arbitrary external edits. | `ARCHITECTURE.md` |
| C-4 | Historical turns without a per-turn model receipt retain the neutral Build agent label. | `ARCHITECTURE.md` |

## One-sentence new-session handoff

Continue the canonical GrokBuild repair campaign from `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop/docs/OUTSTANDING.md`; execute exactly the next open slice, follow Gates A–H and its complete skeptical billable acceptance matrix, commit/push/open and merge its PR to `personal/main`, remove only exact ledgered test threads, end at process zero on the verified merged installed version, and do not begin the following slice.

## Hard stop conditions

Stop the slice immediately when any of the following occurs:

- wrong worktree, remote, branch, repository owner, bundle ID, or installed path;
- local `HEAD`, `personal/main`, GitHub PR head, or installed source stamp disagree;
- unrelated dirty work cannot be isolated safely;
- a test requires credential/config mutation not named in the slice;
- a provider routes to the wrong effective model or fallback is suspected;
- a billable probe exceeds its frozen call/turn boundary;
- a test thread cannot be identified by exact local/backend ID;
- session deletion would touch non-test history;
- an owned process survives teardown and its ownership is ambiguous;
- signing team changes, deep/strict verification fails, quarantine appears, or
  installed/dist bytes differ;
- required checks fail or the PR tree differs from the reviewed local tree;
- the slice exposes an architectural contradiction that requires touching the next
  slice.

At a hard stop, preserve receipts, leave the branch/worktree recoverable, and report the
exact blocker. Do not widen scope, guess, force, reset, delete broadly, or merge anyway.
