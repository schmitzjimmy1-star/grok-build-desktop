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

## Status — seven-slice repair campaign

The installed-app audit on 2026-08-08 verified the canonical repository and
installed application, then exposed seven bounded repair areas. They are ordered
below so truth and lifecycle contracts land before presentation and optimization.

| Slice | Objective | Risk | Provider spend | Status |
|---|---|---:|---:|---|
| 0 | Freeze the audit baseline and remove the four audit-only threads | Low | None; control slice creates no product behavior | Merged and accepted |
| 1 | Stop Activity from claiming task success from transport completion | High | 4 prompts; up to 220K tokens | Merged and accepted |
| 2 | Separate browser process readiness, catalog capability, requested use, and proven use | High | 5 prompts; up to 320K tokens | Merged and accepted |
| 3 | Replace Browser Settings false-negative startup flicker with an unresolved/checking state | Medium | 3 prompts; up to 5,000,000 tokens | Merged and accepted |
| 4 | Replace raw Computer Use self-test JSON with a compact parsed receipt | Medium | 4 prompts; up to 240K tokens | Merged and accepted |
| 5 | Repair navigation-rail accessibility selection semantics | Medium | 3 prompts; up to 200K tokens | Merged and accepted |
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
11. Charge the slice budget only from actual terminal `totalTokens` receipts for the
    frozen matrix turns. Do not project one model or route's context cost onto another,
    and do not stop merely because a future prompt might be expensive. Stop before the
    next prompt only when accumulated actual usage is already at or above the slice
    ceiling; preserve the partial receipt and report the budget stop.
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
2. Use that exact tab's **Close Session** action. Verify its local tab UUID is absent
   from the live layout and its exact file is absent from GrokBuild `Transcripts/`
   before continuing; merely navigating to a project or another tab is not closure.
3. Open **Sessions**, search the exact marker, and verify the returned backend ID
   matches the ledger.
4. Delete that one session through GrokBuild's Sessions UI, accepting its permanent
   deletion confirmation. Alternatively use
   `grok sessions delete <exact-ledgered-id>` from the canonical workspace.
5. Search the exact marker again; it must return zero sessions.
6. Verify the closed local tab does not reappear after a quit/relaunch round trip and
   its exact transcript UUID remains absent.
7. Search GrokBuild transcript storage and backend session directories for the exact
   marker, explicitly excluding workspace `prompt_history.jsonl`. Expected result: no
   retained local transcript or backend session. `prompt_history.jsonl` is the Grok
   CLI's global composer-recall history, not a session or thread; an exact prompt there
   is expected non-session residue and must neither fail Gate F nor be manually edited.
   Any marker in a transcript UUID file or backend session directory still fails the
   gate and must be classified without broad or manual history deletion.

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
- Branch and content commit SHA: `codex/grokbuild-audit-s1-activity-truth` /
  `480deb727410ee0d494bf76f9d4025c839b0e847` (tree
  `a845a7be605b0e8ca666b340f43863e02d381e1e`).
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
- Test thread deletion proof: all five exact candidate tabs/backends were closed and
  permanently deleted; their transcript files and exact prompt-history rows are absent,
  and every marker search returned zero. No non-test session was changed.
- Candidate process-zero proof: exact-name checks returned zero for `GrokBuild`,
  `grok`, `GrokBuildComputerUseMCP`, `agent-desktop`, and GrokBuild-owned browser MCP.
- PR URL/number and reviewed head SHA: PR
  `https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/23`, ready and merged
  after its exact head/tree matched the reviewed local commit.
- Merge commit SHA: `f59b7a80a090424c5f94c29a714e409d46c3dcf7`.
- Post-merge `main` installed stamp/hash/signing: `personal` / `main` / `f59b7a80`,
  `dirty=false`, version `0.1.20`; installed/dist executable SHA-256
  `419862609ff9e06b4e0dcb01d4dc25dec1a9e9cc5f37383d56ea5652c8eb30d1`;
  Team `DD2GCQJVB4`, deep/strict valid, no quarantine.
- Post-merge visible acceptance: S1-B-MAIN (`gpt-5.6-terra`, direct, Medium)
  preserved exit 1, 1 failed tool, 1 unresolved error, and review-next-action after
  parent completion: marker `GB-S1-FAILURE-MAIN-20260809T014934Z`, local tab
  `5AD39E5C-6B5F-44AF-AAC3-690B44C531B7`, backend
  `019fe437-349a-79d3-9c44-f96715e701dc`, 2 calls / 23,633 tokens. S1-C-MAIN
  (pinned `deepseek/deepseek-v4-flash-0731`, OpenRouter, Medium) performed one
  discovery and no invocation/navigation/substitution, rendered neutral lifecycle
  completion and attributed next-action copy: marker
  `GB-S1-UNAVAILABLE-MAIN-20260809T014935Z`, local tab
  `C6407175-412C-4403-8384-BB0F7E009315`, backend
  `019fe439-e8aa-7d23-bcce-0675b9371ba9`, 2 calls / 30,474 tokens,
  approximately $0.0027-$0.0055.
- Final test thread deletion proof: both exact merged-main smoke tabs/backends,
  transcript files, and exact prompt-history rows are absent; both marker searches
  returned zero.
- Final process-zero proof: normal Command-Q followed by exact-name/process-tree
  checks returned zero owned processes.
- CLI version and Settings -> App agreement: CLI `1.0.0
  (3cd0d0cbcebe) [stable]`; Settings -> App visibly reported version `0.1.20`,
  `Personal • main @ f59b7a80`, and the personal repository.
- Worktree/personal-main parity: clean `main` and `personal/main` both
  `f59b7a80a090424c5f94c29a714e409d46c3dcf7` before Slice 2 began.
- Known residual risk: ACP currently reports a child's terminal lifecycle and tool
  count but not typed per-child tool outcomes to the parent; completed workers that
  invoked tools therefore remain explicitly outcome-unresolved instead of being
  promoted from final child prose.
- Exact next slice: Slice 2 - browser readiness and capability truth. Slice 1's merge
  and Gates E-H are complete.

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

Directly necessary typed-contract files for this slice:

- `GrokBuild/Models/ContextInspectorProjection.swift` — carries configured,
  process-ready, discovered, exercised, and unavailable facts without deriving one
  from another.
- `GrokBuild/Models/Message.swift` and
  `GrokBuild/Models/RunEvidenceLiveProjection.swift` — preserve qualified current-turn
  tool evidence across live and restored transcript presentation.
- `Tests/GrokBuildTests/ContextInspectorProjectionTests.swift` — verifies the added
  projection boundary directly.
- `GrokBuild/Services/BackgroundTaskStore.swift` and
  `GrokBuild/Models/RunEvidenceSnapshot.swift` — keep typed child discovery/use
  receipts bound to the exact worker and reconcile them without promoting them into
  parent tools or Sources.
- `Tests/GrokBuildTests/RunEvidenceSnapshotTests.swift` — verifies complete,
  partial, and failed child receipt truth directly.
- `GrokBuild/Services/GrokSessionTranscriptImporter.swift` and
  `Tests/GrokBuildTests/GrokSessionTranscriptImporterTests.swift` — encode the exact
  UTF-8 session path (including spaces and percent signs) before reading child ledgers
  from the canonical workspace.

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

### Frozen final-candidate matrix — `20260809T025338Z`

The user explicitly raised this campaign's provider ceiling to 2M tokens after the
first S2-E candidate exposed missing typed child-tool outcomes. The original 320K
ceiling remains part of the audit history; this frozen rerun is authorized by that
newer explicit ceiling. Every lane uses a fresh disposable local tab, Medium effort,
the deterministic unauthenticated page `http://127.0.0.1:38192/`, title marker
`GB-S2-PROOF-20260809T021928Z`, and body marker
`GB-S2-PAGE-20260809T021928Z`. Markers are lookup handles only.

| Lane | Exact route and marker | Frozen prompt/tool boundary | Expected receipt and hard stop |
|---|---|---|---|
| S2-A | Native Grok 4.5; `GB-S2-REQUESTED-FINAL2-20260809T025338Z` | Attach `chrome-devtools`; answer `17 + 25`; zero tools, retries, workers, navigation, or substitution. | Requested/configured only; no discovery, exercise, or Source. Stop on any tool receipt or route mismatch. |
| S2-B | Direct `gpt-5.6-terra`; `GB-S2-DISCOVERY-FINAL2-20260809T025338Z` | Attach `chrome-devtools`; call `search_tool` exactly once for `chrome-devtools__list_pages`; zero `use_tool`, navigation, retries, workers, or substitution. | One discovery receipt; no exercised/source claim. Stop on fallback, extra call, or invocation. |
| S2-C | OpenRouter pinned `deepseek/deepseek-v4-flash-0731`; `GB-S2-MULTI-FINAL2-20260809T025338Z` | Attach `chrome-devtools`; one exact search for `chrome-devtools__list_pages`, then exactly three invocations in order: `list_pages`, `new_page` to the frozen URL, `take_snapshot`; no retry/substitution/worker. | One discovery plus three successful exact qualified invocations, `chrome-devtools` Source, and exact body marker. Stop on fallback, route drift, extra/reordered call, or missing marker. |
| S2-D | Same pinned OpenRouter route; `GB-S2-ABSENT-FINAL2-20260809T025338Z` | Attach `chrome-devtools`; search exactly once for deliberately absent `chrome-devtools__read_browser_history`; zero use/navigation/retry/substitution/worker. | Exact capability unavailable; no exercised/source/success claim. Stop on any invocation or fallback. |
| S2-E | Native Grok 4.5; `GB-S2-WORKER-FINAL2-20260809T025338Z` | Attach `chrome-devtools`; parent spawns exactly one general-purpose child, then only waits/collects it. Child searches exactly once for `grokbuild-browser__browser_open_url`, invokes it exactly once with the frozen URL, reports exact title marker; no other tool/retry/substitution. | Exact child identity and terminal 2-tool lifecycle; typed child discovery/invocation attributed inside worker to `grokbuild-browser`, 2/2 succeeded, zero invented parent browser tool/Source, exact title marker. Stop on missing/partial child ledger, extra call, or unresolved worker. |

S2-A hard-stopped: native Grok ignored the zero-tool boundary and invoked one terminal
`echo` before answering. Marker `GB-S2-REQUESTED-FINAL2-20260809T025338Z`, local tab
`450E5DC0-51B3-432E-904B-CB33E9B9A181`, backend
`019fe472-1907-7052-9b1d-7bc16647f240`. This receipt is rejected, preserved for the
ledger, and authorized only for exact cleanup. Frozen replacement S2-A-R1 at
`20260809T025610Z`: native Grok 4.5, Medium, attach `chrome-devtools`; return exactly
`42` followed by `GB-S2-REQUESTED-R1-20260809T025610Z`, with zero tools of any kind
(explicitly including terminal, echo, search, files, MCP, and workers), zero retry,
navigation, or substitution. Stop on any tool receipt or route mismatch.

S2-C hard-stopped after the frozen first query returned only `list_pages`: the pinned
DeepSeek route made a second discovery for `new_page` and `take_snapshot`, then invoked
`list_pages` before the user Stop settled the run truthfully. Marker
`GB-S2-MULTI-FINAL2-20260809T025338Z`, local tab
`00A8C135-EB73-47CA-A12A-9AE63BD37C24`, backend
`019fe476-7f95-7452-8996-bdea30d0006d`. Rejected and authorized only for exact
cleanup. Frozen replacement S2-C-R1 at `20260809T030204Z`: same pinned route, Medium,
and attachment; one `search_tool` query containing all three exact names
`chrome-devtools__list_pages chrome-devtools__new_page chrome-devtools__take_snapshot`,
then exactly three `use_tool` calls in that order (new-page URL remains
`http://127.0.0.1:38192/`), exact body-marker report, and marker
`GB-S2-MULTI-R1-20260809T030204Z`. No retry, substitution, worker, or other tool; stop
on fallback, an extra/reordered call, or a missing body marker.

S2-E hard-stopped after the installed Activity receipt kept the terminal child
unresolved even though its exact backend ledger contained two successful terminal
tool receipts. The lookup encoded `/` but not the spaces in the canonical workspace,
so the `/tmp` unit fixture missed the production-path defect. Marker
`GB-S2-WORKER-FINAL2-20260809T025338Z`, child backend
`019fe47c-109e-78e3-a502-0fb1ee4dbcdb`; rejected and authorized only for exact
cleanup. Frozen replacement S2-E-R1 at `20260809T031300Z`: native Grok 4.5, Medium,
attach `chrome-devtools`; parent spawns exactly one general-purpose child and then
only waits/collects it. The child calls `search_tool` exactly once for
`grokbuild-browser__browser_open_url`, calls that exact tool exactly once with
`http://127.0.0.1:38192/`, reports title marker
`GB-S2-PROOF-20260809T021928Z`, and makes no other tool call, retry, substitution, or
worker. Parent emits `GB-S2-WORKER-R1-20260809T031300Z`. Stop on route drift, any
extra call, incomplete child ledger, unresolved worker, invented parent browser
receipt, or parent Source attribution.

S2-E-R1 was also rejected: the candidate bundle had been replaced on disk, but the
pre-fix app process remained live, so the rerun exercised the old executable. Marker
`GB-S2-WORKER-R1-20260809T031300Z`, parent backend
`019fe483-2582-7b43-94b4-03693513094f`, child backend
`019fe483-726a-76b2-9316-ff0a2584ff7b`; authorized only for exact cleanup. After a
normal quit, verified process-zero, and fresh launch of the installed candidate,
S2-E-R2 is frozen at `20260809T031800Z` with the identical route, attachment, URL,
child tool boundary, expected child receipts, and stop conditions as S2-E-R1. Its
only new final marker is `GB-S2-WORKER-R2-20260809T031800Z`.

S2-E-R2 proved the child ledger repair in the freshly launched candidate (`2/2`
succeeded, no unresolved worker, no parent Source) but hard-stopped because the parent
Tools total still counted one ACP-mirrored child invocation (`3` instead of the
authoritative parent ledger's spawn + collect only). Marker
`GB-S2-WORKER-R2-20260809T031800Z`, parent backend
`019fe487-239e-7ad2-9200-6ab5d4edca6f`, child backend
`019fe487-7016-7e01-ae1c-d7339beb8dec`; authorized only for exact cleanup. S2-E-R3 is
frozen at `20260809T032400Z` with the identical route, attachment, URL, child tool
boundary, expected receipts, and stop conditions. Its final marker is
`GB-S2-WORKER-R3-20260809T032400Z`; parent Tools must be exactly `2 succeeded`, while
both child receipts remain visible only inside the worker.

### Slice 2 completion receipt — 2026-08-08/09

- Objective: preserve configured, process-ready, discovered, exercised, unavailable,
  parent, and child browser facts as distinct typed evidence; never promote discovery,
  prompt attachment, final prose, or a child receipt into invented browser use.
- Starting main SHA/tree: `f59b7a80a090424c5f94c29a714e409d46c3dcf7` /
  `a845a7be605b0e8ca666b340f43863e02d381e1e`.
- Branch and implementation commit SHA: `codex/grokbuild-audit-s2-browser-capability` /
  `8a19b814b6c17c078e70ba1ef8959dc823cda520` (tree
  `9a64934e514dc930ddfbc81e75ef79fe039caf2c`).
- Intended files: the Slice 2 primary and directly necessary files enumerated above;
  23 paths total. Unexpected files: none.
- Focused verification: 106 tests, 0 failures. Full candidate `make ship`: 680 tests,
  0 failures in 23.027 seconds, followed by a matching signed install.
- `git diff --check`: clean.
- Candidate installed stamp/hash/signing: `personal` /
  `codex/grokbuild-audit-s2-browser-capability` / `f59b7a80`, `dirty=true`, version
  `0.1.20`; installed/dist executable SHA-256
  `33f62f154956bfaacabcb7fecf6dfe64d22033440680ed9fd4d40509fe0f8c39`;
  Apple Development Team `DD2GCQJVB4`, deep/strict valid, no quarantine. CLI:
  `1.0.0 (3cd0d0cbcebe) [stable]`.
- Disposable proof page: local unauthenticated `127.0.0.1:38192` only; exact title
  `GB-S2-PROOF-20260809T021928Z` and body `GB-S2-PAGE-20260809T021928Z`. Its exact
  process and `/tmp/grokbuild-s2-proof.UFm9AP` artifact remain only until merged-main
  S2-C smoke, then must be stopped and removed without touching a normal Chrome
  profile.
- Accepted candidate lanes:
  - S2-A-R1: marker `GB-S2-REQUESTED-R1-20260809T025610Z`, local tab
    `BADED3F2-6B39-41D0-AC96-72A1BCF7CD45`, backend
    `019fe473-e48d-7943-9340-9292a2b5cc0d`; native Grok 4.5, Medium; 1 call /
    16,161 tokens / `228420000` cost ticks; requested/configured only and zero tools.
  - S2-B: marker `GB-S2-DISCOVERY-FINAL2-20260809T025338Z`, local tab
    `19CB3F3A-D12B-4E3F-8122-82599048D4B7`, backend
    `019fe475-5ae0-7ea0-bcc7-369b479a4512`; direct `gpt-5.6-terra`, Medium; 2 calls /
    24,278 tokens; one discovery and zero exercise/Source.
  - S2-C-R1: marker `GB-S2-MULTI-R1-20260809T030204Z`, local tab
    `04728E9E-DE80-45B3-A0B0-A24E160BDD50`, backend
    `019fe479-1a40-7f12-818c-15622b09a136`; pinned OpenRouter
    `deepseek/deepseek-v4-flash-0731`, Medium; 5 calls / 81,670 tokens; one discovery
    followed by exact successful `list_pages`, `new_page`, and `take_snapshot`
    receipts, authoritative `chrome-devtools` Source, and exact body marker.
  - S2-D: marker `GB-S2-ABSENT-FINAL2-20260809T025338Z`, local tab
    `2E94C4A2-100D-42BC-A170-CAFF1AAE07EB`, backend
    `019fe47a-6ba8-7620-8810-560aad261744`; same pinned OpenRouter route, Medium;
    2 calls / 31,036 tokens; one discovery, exact absent capability, zero exercise or
    Source.
  - S2-E-R3: marker `GB-S2-WORKER-R3-20260809T032400Z`, local tab
    `3956D76D-5B36-4BD4-8004-D85355019A57`, parent backend
    `019fe48f-2bfe-76c1-b877-5f36b3694cb2`, child backend
    `019fe48f-7d35-7f72-bc90-a1fb31c5965f`; native Grok 4.5, Medium; 6 calls /
    89,274 tokens / `1126416000` cost ticks. The child has exactly one discovery and
    one successful use attributed to `grokbuild-browser`; parent Tools remain exactly
    2 succeeded and parent Sources remain empty.
- Accepted total: 16 model calls / 242,419 tokens, below the original 320K ceiling;
  exposed native cost `1354836000` ticks. Direct/OpenRouter receipts exposed no exact
  cost; no fallback or route substitution occurred.
- Rejected variance: 14 rejected parent candidates plus the five accepted parents
  (19 exact candidate parents total) captured zero-tool disobedience, incomplete
  discovery, user Stop, pre-fix child-ledger lookup, stale installed process, and one
  mirrored child receipt in the parent count. All are ledgered above or in the final
  task receipt and were used only to correct the bounded Slice 2 contract.
- Candidate cleanup: all 19 exact parent backends were deleted; all 19 local tabs and
  transcript caches were closed through GrokBuild; exactly 19 matching prompt-history
  rows were removed. Five unindexed child ledger directories could not be addressed by
  the backend CLI and were moved by exact validated ID to recoverable Trash paths.
  Active GrokBuild support and backend-session marker searches both returned zero; no
  non-test session or normal browser profile was changed.
- Candidate process-zero proof: normal app quit followed by exact-name checks returned
  zero for `GrokBuild`, `grok`, `GrokBuildComputerUseMCP`, `agent-desktop`, and any
  GrokBuild-owned managed browser process. The separately ledgered local proof server
  remains solely for the required post-merge smoke.
- PR, merge SHA, post-merge install/parity, S2-A/S2-C/S2-D visible smoke, final exact
  smoke cleanup, proof-page cleanup, Settings -> App agreement, and final process-zero
  are mandatory post-merge Gates E-H. Their immutable values belong in the PR and
  final task receipt because they do not exist in this pre-merge source snapshot.
- Exact next slice after those gates: Slice 3 — Browser Settings unresolved/checking
  state. Do not begin Slice 3 in this task.

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
settled frames. Then run all three frozen prompts; token ceiling **5,000,000 actual
receipt tokens total**:

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

### Frozen Slice 3 candidate matrix — `20260809T002000Z`

All lanes use Medium effort, fresh disposable tabs, the unauthenticated page
`http://127.0.0.1:38203/`, title `GB-S3-PROOF-20260809T001700Z`, and body
`GB-S3-PAGE-20260809T001700Z`. `chrome-devtools` is the only attached MCP; no
configuration, credential, provider, browser-profile, or normal Chrome state may be
changed. Every lane hard-stops on route drift, fallback, retry, extra tool/model call,
missing marker, process-generation change, or false Setup needed presentation.

- **S3-A — native Grok 4.5, marker `GB-S3-ROUNDTRIP-20260809T002000Z`:** Turn 1
  searches once for `chrome-devtools__new_page` and
  `chrome-devtools__take_snapshot` in one query, invokes each exactly once in that
  order against the frozen URL, and reports the exact body marker plus `GB-S3-A1`.
  With the backend idle, open and close Browser Settings without applying anything.
  Turn 2 searches once for `chrome-devtools__take_snapshot`, invokes it once on the
  same page, and reports the same body marker plus `GB-S3-A2`. No terminal, file,
  worker, navigation substitution, or other tool is allowed.
- **S3-B — pinned OpenRouter `deepseek/deepseek-v4-flash-0731`, marker
  `GB-S3-MULTI-20260809T002000Z`:** while the turn is live, manually run Browser
  Settings diagnostics. The model runs exactly one terminal `pwd`, searches once for
  `chrome-devtools__take_snapshot`, invokes that browser tool once on the frozen page,
  then emits the exact body marker and `GB-S3-MULTI`. No worker, retry, file write,
  extra browser action, or substitution is allowed.
- **S3-B-R — user-authorized remediation retry, marker
  `GB-S3-MULTI-RETRY-20260809T161732Z`:** the original S3-B lane settled on
  `about:blank` because the fresh `chrome-devtools` process did not inherit S3-A's
  selected page. In one fresh pinned OpenRouter
  `deepseek/deepseek-v4-flash-0731` session, run exactly one terminal `pwd`, search
  exactly once with one query containing `chrome-devtools__new_page` and
  `chrome-devtools__take_snapshot`, invoke `new_page` exactly once for the frozen URL,
  then invoke `take_snapshot` exactly once. While that turn is live, manually run one
  Browser Settings diagnostics refresh. Report the exact path, frozen body marker,
  and `GB-S3-MULTI-RETRY`; no worker, further retry, file write, substitution, or
  other tool is allowed. This single retry was explicitly authorized by Jimmy after
  the preserved S3-B failure receipt; it does not erase or replace that receipt.
- **S3-B-R2 — clean-process remediation retry, marker
  `GB-S3-MULTI-RETRY2-20260809T162109Z`:** S3-B-R proved that the still-open
  original S3-B tab owned the shared `chrome-devtools` profile lock. After recording
  both failed receipts, close their exact local tabs, delete only backend IDs
  `019fe74d-fdc0-7b63-a2f0-2aa3431dfe9d` and
  `019fe751-a569-7832-9ce4-3cdc21d158ed`, quit GrokBuild, and prove process-zero.
  From that clean state, repeat the S3-B-R tool order in one fresh pinned DeepSeek
  session: one `pwd`, one combined discovery, one `new_page` for the frozen URL, and
  one `take_snapshot`, while one manual Browser Settings diagnostics refresh runs.
  Report the exact path, body marker, and `GB-S3-MULTI-RETRY2`; no worker, further
  in-turn retry, file write, substitution, or other tool is allowed. Jimmy's explicit
  instruction to retry when needed authorizes this environment-clean retry without
  invalidating either preserved failure.
- **S3-C — direct `gpt-5.6-terra`, marker
  `GB-S3-WORKER-20260809T002000Z`:** after closing and recreating Browser Settings,
  the parent spawns exactly one `general-purpose` child and only waits/collects it.
  The child searches once for `chrome-devtools__take_snapshot`, invokes it once on the
  frozen page, reports the exact body marker, and makes no other tool call. The parent
  emits `GB-S3-WORKER`; no retry, second child, substitution, or extra helper is
  allowed.
- **S3-C-R — environment-safe child lane, marker
  `GB-S3-WORKER-RETRY-20260809T162818Z`:** the preserved S3-B receipts prove a
  fresh `chrome-devtools` process starts on `about:blank` and cannot inherit another
  tab's selected page without also inheriting its locked profile. After the Browser
  pane recreation and successful S3-B tab closure, use one fresh direct
  `gpt-5.6-terra` session. The parent spawns exactly one `general-purpose` child and
  only waits/collects it. The child searches exactly once with one query containing
  `chrome-devtools__new_page` and `chrome-devtools__take_snapshot`, invokes
  `new_page` exactly once for the frozen URL, invokes `take_snapshot` exactly once,
  and reports the exact body marker. The parent emits `GB-S3-WORKER-RETRY`; no second
  child, in-turn retry, substitution, file write, or other tool is allowed. Jimmy's
  instruction to retry when needed authorizes this bounded setup action before the
  lane is sent instead of deliberately reproducing the known `about:blank` failure.

### Slice 3 interrupted candidate receipt — amended `20260809T002000Z`

- Candidate source remained the uncommitted branch
  `codex/grokbuild-audit-s3-browser-checking` based on
  `7c53e655d77932f8ece9e4fe66322f257f7759f8`; no commit, push, PR, or merge was
  attempted because the complete matrix did not pass.
- Intended files remained exactly the seven Slice 3 paths named by the candidate
  diff. Focused `BrowserIntegrationTests` passed 18/18, focused
  `SettingsTabTests` passed 17/17, and `make test` plus candidate `make ship`
  each passed 687 tests with zero failures.
- Candidate `/Applications/GrokBuild.app` reported version `0.1.20`, source commit
  `7c53e655d77932f8ece9e4fe66322f257f7759f8`, branch
  `codex/grokbuild-audit-s3-browser-checking`, and `dirty=true`. Installed and
  `dist` executable SHA-256 both equaled
  `d4d7af045fa063441dd64aaa62506840b942d34b76acf28fb8bb096634b29d6a`;
  deep/strict signing passed under Team `DD2GCQJVB4`, and quarantine was absent.
- Cold Browser Settings settled to **Browser Control Ready** for
  `agent-browser 0.33.0` at `/opt/homebrew/bin/agent-browser`; no false Setup
  needed presentation or applied-settings mutation was observed. The initial
  checking frame settled faster than the Computer Use capture interval, so its
  installed-frame screenshot was not claimed; the initial-state behavior remains
  covered by the focused behavioral tests.
- S3-A marker `GB-S3-ROUNDTRIP-20260809T002000Z`; local tab UUID
  `120F6DCA-4DD3-4BF0-A508-05FC8704B6BF`; backend ID
  `019fe4c0-d07b-7920-948e-448fc46b0dfa`; native Grok 4.5 at Medium; process
  generation 1, PID 58891. Turn 1 used 69,217 tokens across four model calls and
  exactly one discovery, one `chrome-devtools__new_page`, and one
  `chrome-devtools__take_snapshot`; it returned the frozen page marker plus
  `GB-S3-A1`. After an idle Browser Settings round trip, Turn 2 used 55,102 tokens
  across three model calls and exactly one discovery plus one
  `chrome-devtools__take_snapshot`; it returned the same page marker plus
  `GB-S3-A2`. Both tools succeeded in the required order and the backend/model
  remained continuous.
- S3-A consumed 124,319 actual receipt tokens, leaving 4,875,681 under the revised
  5,000,000-token Slice 3 ceiling. The earlier stop projected Grok 4.5 context cost
  onto unsent routes; the amended Gate C rule forbids that projection. S3-B and S3-C
  remain unsent and authorized within the revised ceiling.
- Cleanup deleted exact backend ID
  `019fe4c0-d07b-7920-948e-448fc46b0dfa`; the Sessions UI exact-marker search then
  returned **No Sessions**. The marker in workspace `prompt_history.jsonl` is now
  correctly classified as expected global composer-recall history and is not Gate F
  thread residue. Gate F remains incomplete only because local transcript
  `120F6DCA-4DD3-4BF0-A508-05FC8704B6BF.json` remains and the tab reappeared after
  relaunch, proving the prior coordinate action navigated away instead of completing
  the explicit **Close Session** action. Before any new billable prompt, close that
  exact local tab through its named action and prove its UUID/file stays absent.
- The disposable proof server was stopped and its exact fixture was moved to Trash.
  Normal Command-Q left exact GrokBuild PID 59787 at PPID 1 with 0.0% CPU; after
  recording PID/PPID/elapsed/CPU/command, TERM to only that proven orphan succeeded.
  Final checks found zero `GrokBuild`, `grok`, `GrokBuildComputerUseMCP`,
  `agent-desktop`, or GrokBuild-owned browser processes.
- Slice 3 remains open. Resume with the exact local-tab cleanup proof, then S3-B and
  S3-C under the frozen packet and revised 5,000,000-token ceiling. Gate D publication,
  Gate E merged-main acceptance, and Slice 4 remain forbidden until the full matrix
  and Gates F–H pass.

### Slice 3 resumed candidate receipt — child-cleanup hard stop `20260809T162818Z`

- The residual S3-A local tab was closed through its named **Close Session** action.
  Transcript UUID `120F6DCA-4DD3-4BF0-A508-05FC8704B6BF` stayed absent across a
  quit/relaunch round trip, and the exact marker returned no local-transcript or
  backend-session match when global `prompt_history.jsonl` was correctly excluded.
- Original S3-B used local UUID `6139C553-E428-4FD4-8C05-2892A994CE6B` and backend
  ID `019fe74d-fdc0-7b63-a2f0-2aa3431dfe9d`. Pinned DeepSeek ran one `pwd`, one
  discovery, and one snapshot in order; the snapshot succeeded technically but
  returned `about:blank`, so the required page marker was absent. The lane stopped
  without retry or substitution after 61,700 tokens and four model calls.
- User-authorized S3-B-R used local UUID
  `37631F2F-9FF3-434B-92E4-7F9A9840FF4A` and backend ID
  `019fe751-a569-7832-9ce4-3cdc21d158ed`. Its one `new_page` and one snapshot were
  rejected because the still-open original lane owned the shared
  `chrome-devtools` profile lock. It stopped after 66,798 tokens and four model calls.
  Both failed local tabs and exact backend IDs were then deleted, a quit reached
  process-zero, and their markers returned no session/transcript matches.
- Clean-process S3-B-R2 used local UUID
  `505481DA-AB6E-445B-BA12-2CB993062F14` and backend ID
  `019fe754-fd0f-7af3-b211-5e029a2217af`. Pinned DeepSeek at Medium ran exactly one
  `pwd`, one combined discovery, one `new_page`, and one snapshot; all four tools
  succeeded in order, the frozen title/body markers matched, Browser diagnostics
  remained Ready during the live turn, and no setting changed. Usage was 66,326
  tokens and four model calls.
- The Browser pane was unmounted through Agents and recreated before S3-C; it settled
  Ready with no false Setup needed presentation. Environment-safe S3-C-R used local
  UUID `02C00970-2810-4C4B-9E64-C176AEAABB63`, parent backend
  `019fe75a-fb26-7493-b07e-7577f6cca5d7`, direct `gpt-5.6-terra` at Medium, and
  exactly one `general-purpose` child
  `019fe75b-41c2-7562-a354-3f20c214b682`. The child completed in 7.2 seconds with
  3/3 receipts succeeded: one combined discovery, one `new_page`, and one snapshot.
  It returned the exact body marker; the parent collected the exact child identity and
  emitted `GB-S3-WORKER-RETRY`. Parent usage was 74,856 tokens and seven model calls.
- Total actual Slice 3 receipt usage is 393,999 tokens: original S3-A 124,319 plus
  269,680 across the resumed S3-B/S3-C lanes, under the 5,000,000-token ceiling.
- Cleanup removed all four resumed local transcript UUIDs and deleted exact parent
  backend IDs `019fe74d-fdc0-7b63-a2f0-2aa3431dfe9d`,
  `019fe751-a569-7832-9ce4-3cdc21d158ed`,
  `019fe754-fd0f-7af3-b211-5e029a2217af`, and
  `019fe75a-fb26-7493-b07e-7577f6cca5d7`. Exact marker searches for S3-B, S3-B-R,
  and S3-B-R2 returned zero session/transcript matches. GrokBuild, Grok CLI,
  Computer Use, `agent-desktop`, `chrome-devtools-mcp`, and owned browser processes
  all reached zero after normal quit.
- Gate F is blocked only by unindexed child directory
  `~/.grok/sessions/%2FUsers%2Fjimmyschmitz%2FDesktop%2FProjects%2FMCP%20Servers%2FGrok%20Build%2Fgrok-build-desktop/019fe75b-41c2-7562-a354-3f20c214b682`.
  `grok sessions search` returns zero and `grok sessions delete
  019fe75b-41c2-7562-a354-3f20c214b682` returns **No session found**, but its
  `chat_history.jsonl` and `updates.jsonl` retain the exact S3-C marker after parent
  deletion and quit. The directory was preserved under Gate F; no manual history
  deletion, commit, push, PR, merge, or Slice 4 work occurred.
- Jimmy then explicitly authorized manual removal of that exact unindexed child.
  Permanent `rm` was rejected by the execution environment, so the validated,
  non-symlink directory was moved intact to recoverable Trash entry
  `~/.Trash/GrokBuild-S3-child-019fe75b-41c2-7562-a354-3f20c214b682` instead.
  Active GrokBuild transcript storage and `~/.grok/sessions` then returned zero Slice 3
  marker matches (excluding global composer history), and the exact process gate
  remained zero. Gate F therefore passes for active session/thread storage; the Trash
  entry remains an explicit recoverable rollback receipt until separately emptied.
- Slice 3 publication and merged-main acceptance completed in PR #25. Reviewed head
  `95c6e2503b52f7004ceab3418d1d2d42962e0499` merged normally as
  `3000fe4fc5569f2a396d5444c8817127de4dff0f`; clean merged `main`,
  `personal/main`, and the installed stamp agree. The merged install passed 687 tests,
  deep/strict signing under Team `DD2GCQJVB4`, no quarantine, and executable hash
  parity at `2a6ddf480eca1f355d1bf7f22765ca19f55c3b94e81a494bffc4ebb45b08925c`.
  Post-merge S3-A used the same native Grok backend before/after the idle Browser
  Settings round trip, consumed 123,908 actual tokens, and returned the same proof-page
  marker with exact discovery/new-page/snapshot receipts. Its exact local and backend
  threads were deleted, the proof server stopped, active Slice 3 marker storage and
  owned processes reached zero, and Slice 4 remained untouched until this branch.

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

### Frozen Slice 4 candidate matrix — `20260809T165153Z`

Every lane uses one fresh disposable tab, Medium effort, the named route, and the
`grokbuild-computer-use` attachment. One exact discovery call is allowed only to resolve
the named qualified tool. No lane may retry, substitute a tool/server/model, write a
file, change settings, or invoke Browser tools. Stop on route drift, fallback, an extra
tool/worker, missing terminal receipt, or accumulated actual usage already at/above the
240,000-token ceiling before the next prompt.

- **S4-A — native Grok 4.5, marker `GB-S4-LIST-20260809T165153Z`:** search exactly
  once for `grokbuild-computer-use__computer_list_apps`, invoke it exactly once with
  no screenshot, then report only the returned app count and `GB-S4-LIST`. No other
  tool, retry, worker, or raw inventory repetition.
- **S4-B — direct `gpt-5.6-terra`, marker `GB-S4-INSPECT-20260809T165153Z`:** search
  exactly once for `grokbuild-computer-use__computer_snapshot`, invoke it exactly once
  against GrokBuild, inspect only the semantic accessibility result, and emit
  `GB-S4-INSPECT`. No click, type, screenshot, retry, worker, or mutation.
- **S4-C — pinned OpenRouter `deepseek/deepseek-v4-flash-0731`, marker
  `GB-S4-FAIL-20260809T165153Z`:** search exactly once for
  `grokbuild-computer-use__computer_snapshot`, invoke it exactly once against frozen
  nonexistent bundle ID `com.grokbuild.slice4.nonexistent`, do not recover or retry,
  and emit `GB-S4-FAIL` while preserving the failed tool receipt separately from the
  parent completion.
- **S4-D — native Grok 4.5, marker `GB-S4-WORKER-20260809T165153Z`:** spawn exactly
  one `general-purpose` child, then only wait/collect it. The child searches exactly
  once for `grokbuild-computer-use__computer_list_apps`, invokes it exactly once, and
  reports the app count. The parent emits `GB-S4-WORKER` without duplicating the
  child's tool call; no second child, screenshot, retry, or substitution.

### Slice 4 candidate acceptance receipt — 2026-08-09

- Starting `main` SHA/tree: `3000fe4fc5569f2a396d5444c8817127de4dff0f` /
  `ca37bb4a0c5995524c07efbc55219f7116ce25ea`; clean local `main` matched
  `personal/main` before the branch was created.
- Candidate branch: `codex/grokbuild-audit-s4-computer-use-receipt`; seven intended
  files were modified and no unexpected path appeared.
- Focused tests: `ComputerUseIntegrationTests` 36/36 and `SettingsTabTests` 18/18.
  Full `make test` and candidate `make ship` each passed 695 tests with zero failures.
- Candidate installed stamp/hash/signing: `personal` /
  `codex/grokbuild-audit-s4-computer-use-receipt` / `3000fe4f`, `dirty=true`, version
  `0.1.20`; installed/dist executable SHA-256
  `d4bdd1a783756fbe4762495bc25f364d7a16c3a9a26b2c54e10c5a0530606e2c` with byte
  parity; Apple Development Team `DD2GCQJVB4`, deep/strict valid, no quarantine.
- Settings -> Computer Use self-test: visible compact success reported protocol
  `2024-11-05`, helper `0.1.1`, command `computer_list_apps`, 34 apps, 191 ms,
  Accessibility proven, and screenshots not required. The default pane contained no
  PID, process-instance identifier, path, or raw inventory. Opt-in diagnostics showed
  only `{"command":"list-apps","data":{"apps":["<redacted 34 app records>"]},
  "ok":true,"version":"2.1"}` for the helper payload.
- S4-A: native Grok 4.5, one exact discovery plus one successful
  `grokbuild-computer-use__computer_list_apps`, 35 apps, no screenshot or raw
  inventory repetition; 3 model calls / 49,961 tokens.
- S4-B: direct `gpt-5.6-terra`, one exact discovery plus one successful semantic
  `grokbuild-computer-use__computer_snapshot` against GrokBuild, no screenshot or
  mutation; 3 calls / 41,363 tokens.
- S4-C: pinned OpenRouter `deepseek/deepseek-v4-flash-0731`, one exact discovery plus
  one intentional failed snapshot against `com.grokbuild.slice4.nonexistent`; Activity
  preserved `APP_NOT_FOUND` as one unresolved failed tool separately from the completed
  parent turn, with no retry; 3 calls / 45,979 tokens.
- S4-D: native Grok 4.5 spawned exactly one `general-purpose` child
  `019fe77c-4192-7353-a0fb-c4d247687734`. The child searched once, invoked
  `computer_list_apps` once, returned 40 apps, and finished 2/2 tools successfully;
  the parent only spawned, waited, collected, and emitted the marker. Activity reported
  6 model calls / 88,136 tokens for the settled parent row and no worker/tool failure.
- Candidate Activity total: 15 model calls / 225,439 displayed row tokens. The stop
  check was below 240,000 before every next prompt (137,303 before S4-D); no prompt was
  sent after S4-D. Route receipts showed no GrokBuild fallback. Pricing was not exposed
  consistently enough for a defensible combined cost.
- Exact local tab/backend receipts:
  - S4-A: `17F2CD02-BC60-435D-8E0A-C392E4366A45` /
    `019fe776-1ef5-7183-a5a4-36c4bd1a4570`;
  - S4-B: `D81C311A-B54F-404F-9E3C-70DECA677CFB` /
    `019fe779-6aae-7f43-8adf-5c741c05ecea`;
  - S4-C: `6FB7734D-4BEF-4AB6-ABC2-6A343B424D59` /
    `019fe77a-b23b-7c82-a5a4-4bd00429d144`;
  - S4-D: `03C105E4-EE02-4E50-B361-181B88BC883D` / parent
    `019fe77b-ec56-7e93-ac2f-b31ee60a6ea5` / child
    `019fe77c-4192-7353-a0fb-c4d247687734`.
- Process receipts: each fresh tab owned one exact `grok agent stdio` process and one
  browser/Computer Use MCP pair. S4-D's child tool helper exited after completion; no
  extra child ACP process or duplicated parent Computer Use receipt appeared. Closing
  the four exact tabs terminated every candidate process tree.
- Candidate cleanup: the four exact local tabs were closed; the four parent backends
  were deleted; deleting S4-D's parent cascaded the child from the backend registry.
  The remaining exact local child directory was moved to Trash for recoverability
  after permanent deletion was safety-blocked. All four markers then returned zero in
  live GrokBuild transcripts and `.grok/sessions`; no non-test tab or backend changed.
- Candidate process-zero/relaunch proof: normal Command-Q left zero GrokBuild-owned
  processes; a clean relaunch showed none of the four Slice 4 tabs; the second normal
  quit again left zero owned processes.
- Final-candidate race hardening: the first post-matrix focused rerun exposed a real
  SIGTERM/termination-handler race in `runResult`: a fast child exit could publish a
  success before the timeout error. Publishing the timeout before SIGTERM fixed it;
  the timeout test then passed five consecutive isolation runs, both focused suites
  passed, and full `make test` plus final `make ship` each passed 695/695. The four
  billable route lanes ran on the immediately preceding signed candidate hash
  `1ee4068abca1863a19ba65bec10018279e01fb76b35023e4aa90512cedafff23`; the only later
  source change was that two-line timeout ordering fix. No additional billable prompt
  was sent beyond the frozen matrix. On the final installed hash, the non-billable
  self-test repeated the compact receipt with protocol `2024-11-05`, helper `0.1.1`,
  31 apps, 191 ms, Accessibility proven, screenshots not required, and opt-in-only
  `<redacted 31 app records>` diagnostics; final normal quit left zero owned processes.

### Slice 4 completion receipt — 2026-08-09

- Content commit `990e4c80257b433e99c62f2c7384680519d9ea0c` (tree
  `c6735df7e7a7837f5003423d33a9f6fcc87b05e9`) was pushed by ordinary non-force push
  to `personal/codex/grokbuild-audit-s4-computer-use-receipt`. PR
  [#26](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/26) was ready,
  matched that exact reviewed head and seven-path scope, reported no required checks,
  and merged normally as `1205c60f4dec0b2ee97aba586133fae267a82e1c`.
- Clean merged `main` matched `personal/main` at that merge commit. `make ship` passed
  all 695 tests and installed version `0.1.20` with `dirty=false`. Installed/dist
  executable SHA-256 was
  `65827a1cb2e42d99c99100bc812c000afad88142198e9668930d6ac3aa1f55aa` with byte
  parity; Team `DD2GCQJVB4` signing passed deep/strict validation and the app had no
  quarantine attribute.
- Merged-main Settings -> Computer Use repeated the compact self-test: protocol
  `2024-11-05`, helper `0.1.1`, command `computer_list_apps`, 32 apps, 190 ms,
  Accessibility proven, screenshots not required, and no default raw inventory.
- Merged S4-C used pinned OpenRouter `deepseek/deepseek-v4-flash-0731`, searched once,
  invoked the frozen nonexistent bundle once, preserved `APP_NOT_FOUND` as one failed
  tool separately from parent completion, and did not retry: marker
  `GB-S4-FAIL-MAIN-20260809T172106Z`, local tab
  `C5B71366-5B33-4881-A056-21ABE1B8839F`, backend
  `019fe78c-2ba5-78b1-8bc9-0d816156e870`, 3 calls / 45,575 tokens.
- Merged S4-D used native Grok 4.5 and exactly one `general-purpose` child
  `019fe78d-f7be-7c20-87c8-8805f9618f7c`. The child searched once, invoked
  `computer_list_apps` once, returned 35 apps, and settled 2/2 child receipts
  successfully; the parent only spawned, waited, collected, and emitted the marker.
  Receipt: `GB-S4-WORKER-MAIN-20260809T172106Z`, local tab
  `E9F55E2E-27ED-4E7E-AA10-8EBB7DEE8352`, parent backend
  `019fe78d-9ad5-79f3-b980-fcc27739d162`, 6 calls / 88,659 tokens.
- Final cleanup closed those two exact tabs and deleted those two exact parent
  backends. Parent deletion cascaded the child from the backend registry but left its
  exact local child directory; that single validated directory was moved to
  `~/.Trash/GrokBuild-S4-main-child-019fe78d-f7be-7c20-87c8-8805f9618f7c` for
  recoverability. Both markers then returned zero in live GrokBuild transcripts and
  `.grok/sessions`; no unrelated session or state changed. A quit/relaunch showed no
  Slice 4 smoke tab, and the final normal quit left zero GrokBuild-owned processes.
- CLI identity remained `grok 1.0.0 (3cd0d0cbcebe) [stable]`. Gate H is repeated on
  the clean final ledger merge below; the closing ledger-only commit changes no app
  source or acceptance behavior and therefore does not justify another billable
  provider prompt.
- Known residual risk: backend deletion can cascade a child from the registry without
  removing that child's local session directory. Slice 4 handled both observed cases
  by exact-ID, recoverable moves to Trash; broad cleanup remains forbidden. The typed
  receipt deliberately proves the list-apps command contract only; Accessibility and
  screenshot truth stays prerequisite metadata, not proof that a screenshot path ran.
- Exact next slice: Slice 5 — navigation-rail accessibility selection. Slice 5 remains
  forbidden until this closing ledger receipt is merged, final `main` is re-shipped,
  Settings -> App agrees with the final commit, and Gates F-H are green.

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

### Frozen Slice 5 candidate matrix — `20260809T174753Z`

Every lane uses one fresh disposable tab, Medium effort, the named route, and one
parent turn. The rail remains action-only throughout; the selected workspace/session
must stay bound to the real conversation route, and Settings must expose only its
actual selected pane. Stop on route drift, fallback, retry, an extra tool/worker,
lost tab/backend identity, a false rail selection, or accumulated actual usage already
at/above the 200,000-token ceiling before the next prompt.

- **S5-A — native Grok 4.5, marker `GB-S5-LIVE-20260809T174753Z`:** invoke the
  terminal exactly once with `/bin/sleep 5; /bin/echo GB-S5-LIVE-20260809T174753Z`,
  then return only that marker. While the command is live, open and close Sessions and
  return to the same conversation. No discovery, MCP, file, browser, worker, retry, or
  other tool is allowed.
- **S5-B — direct `gpt-5.6-terra`, marker
  `GB-S5-WORKER-20260809T174753Z`:** spawn exactly one `general-purpose` child, then
  only wait/collect it. The child invokes terminal exactly once with
  `/bin/sleep 5; /bin/pwd`, reports the exact path, and uses no other tool. While the
  child is active, open Security -> Permissions and return to the same conversation.
  The parent emits the marker; no second child, retry, MCP, browser, file mutation, or
  substitution is allowed.
- **S5-C — pinned OpenRouter `deepseek/deepseek-v4-flash-0731`, marker
  `GB-S5-MULTI-20260809T174753Z`:** invoke terminal exactly once with `/bin/pwd`,
  search exactly once for `grokbuild-computer-use__computer_snapshot`, then invoke
  that exact tool once against GrokBuild with semantic accessibility only and no
  screenshot. After settlement, open/close Plugins, switch to another existing
  protected session, then return to the exact test session. Emit the marker after the
  ordered receipts; no action, mutation, retry, worker, browser tool, or substitution
  is allowed.

### Slice 5 candidate receipt — 2026-08-09

- Gate A started from clean canonical `main` and `personal/main` at
  `24759a6275203da1be5fccc8bbb051ca2811826a` (tree
  `d5eafa4762a77779da922f5f8fd65bcd352ba58d`). The final signed candidate kept
  that HEAD stamp with `dirty=true`, passed all 700 tests, and installed version
  `0.1.20`; installed/dist executable SHA-256 was
  `2a0cd98992b2750fc91f58f525206b7a125fb4524baea154404400dd284aa46a`, Team
  `DD2GCQJVB4`, deep/strict valid, and unquarantined.
- Fresh AX trees proved the compact rail is action-only: New chat, Sessions,
  Plugins, and Security never retained selected state. Exactly one rendered
  persistent destination was selected: the active session when its row was
  visible, otherwise its project when the session row was hidden or unavailable.
  Sessions open/close, Plugins, Permissions, project switches, session switches,
  and keyboard-focus movement preserved that invariant; Settings exposed only its
  actual selected pane. Stable rail identifiers are
  `grok-rail-new-chat`, `grok-rail-sessions`, `grok-rail-plugins`, and
  `grok-rail-security`.
- S5-A used native Grok 4.5 and exactly one terminal call
  `/bin/sleep 5; /bin/echo GB-S5-LIVE-20260809T174753Z`; Sessions opened and closed
  during the live Stop state, the same session remained selected, and the command
  settled once successfully. Receipt: local tab
  `BD45C746-E8BA-4B27-8E60-935640F951E1`, backend
  `019fe7bb-a892-70e3-9df5-60b17f8a7e4b`, 2 calls / 32,055 tokens.
- S5-B used direct `gpt-5.6-terra` and exactly one `general-purpose` child
  `019fe7bd-d413-7b51-a4fa-289bc169a2e2`. The child invoked only
  `/bin/sleep 5; /bin/pwd`; the parent only spawned, waited, and collected. While
  live, Security -> Permissions was the sole selected Settings pane; returning
  restored the same selected session. Receipt: local tab
  `DED1031B-19EA-43A4-9A03-F6781B52F9A3`, parent backend
  `019fe7bd-649f-75c0-bd9c-439cb03a74dc`, 5 calls / 48,153 tokens.
- S5-C used pinned OpenRouter `deepseek/deepseek-v4-flash-0731` and exactly three
  ordered tools: terminal `/bin/pwd`, one discovery for
  `grokbuild-computer-use__computer_snapshot`, and one successful semantic-only
  snapshot of GrokBuild. It used no screenshot, action, retry, worker, browser, or
  substitute. After settlement, Plugins selected only its Settings pane and a
  protected-session switch returned to the exact test session. Receipt: local tab
  `4AEA8FFB-F511-4687-91ED-A8290FC5CBF1`, backend
  `019fe7bf-9646-79b0-bcb6-0a11fa6d39fb`, 3 calls / 52,775 tokens.
- Candidate total was 132,983 tokens, below the 200,000-token ceiling before every
  next prompt. All three exact tabs were closed and parent backends deleted. Parent
  deletion left only S5-B's validated child directory, which was moved recoverably
  to `~/.Trash/GrokBuild-S5-child-019fe7bd-d413-7b51-a4fa-289bc169a2e2` under the
  exact-ID cleanup authorization. All three markers then returned zero in live
  transcripts and `.grok/sessions` excluding immutable prompt history; final normal
  quit left zero GrokBuild-owned processes.

### Slice 5 completion receipt — 2026-08-09

- Content commit `751fe903ef3e6162af5e4a4132585412d8e1a600` (tree
  `84c6b938e7c790f0fe6e24b4df7a6e342407a570`) was pushed by ordinary non-force
  push to `personal/codex/grokbuild-audit-s5-navigation-selection`. Ready PR
  [#28](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/28) matched
  that exact reviewed head and eight-path scope, reported no required checks, and
  merged normally as `78b09b27e75ab79f53df5c4bb795eb622a5f315c`.
- Clean merged `main` matched `personal/main` at that merge commit. `make ship`
  passed all 700 tests and installed version `0.1.20` with `dirty=false`.
  Installed/dist executable SHA-256 was
  `031da8e07d2c20601d43a2e05b84772f95a63ada4d441a28bbf5c7f0da95d594` with byte
  parity; Team `DD2GCQJVB4` signing passed deep/strict validation and the app had
  no quarantine attribute.
- The complete merged-main AX round trip repeated New chat, Sessions open/close,
  Plugins open/close, Security -> Permissions open/close, hidden-session project
  selection, visible-session selection, a protected session switch, and Tab /
  Shift-Tab focus movement. Rail actions never reported selected; Plugins and
  Permissions were each the sole selected Settings pane; exactly one rendered
  project/session destination remained selected before and after focus movement.
- Merged S5-B used direct `gpt-5.6-terra` and exactly one `general-purpose` child
  `019fe7cc-0728-7561-bd62-d47e746522be`. The child invoked only
  `/bin/sleep 5; /bin/pwd`; the parent only spawned, waited, and collected, while
  Security -> Permissions round-tripped during the live turn. Receipt:
  `GB-S5-WORKER-MAIN-20260809T182900Z`, local tab
  `55729E5E-F380-4A6A-B91A-3F963C0601B0`, parent backend
  `019fe7cb-a7d7-7432-a0a4-9d4ea1a4c67a`, 5 calls / 48,066 tokens.
- Final cleanup closed that exact tab and deleted that exact parent backend.
  Parent deletion cascaded the child from the backend registry but left its exact
  local directory; only that validated directory was moved recoverably to
  `~/.Trash/GrokBuild-S5-main-child-019fe7cc-0728-7561-bd62-d47e746522be`.
  The merged marker then returned zero in live transcripts and `.grok/sessions`
  excluding immutable prompt history; no unrelated session changed. Final normal
  quit left zero GrokBuild-owned processes.
- CLI identity remained `grok 1.0.0 (3cd0d0cbcebe) [stable]`. This closing
  ledger-only change modifies no app source or acceptance behavior and therefore
  does not justify another billable provider prompt. Slice 6 remains forbidden
  until this closeout merges normally, final `main` is re-shipped, Settings -> App
  agrees with the closeout commit, and Gates F-H are green.

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
