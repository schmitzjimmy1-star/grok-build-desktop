# Slice 4C edit map — 2026-08-19

Locked executor (steps 1–4) plus the pre-unlock drop-in (this slice) are in
tree. They do **not** authorize a paid Send, a pager rebuild, `grok update`,
unlocking `_billable_v3`, or narrowing `require_absolute_ceiling_support()`.

Product stamp stays `29c064f` until the first 4C **app-code** `make ship`.
CLI leftover PR #7 is **merged** as `7e9f1ad`. Live Application Support
`runtime-selection.json` stays **absent** until a later 4C packet arms it.

Frozen identity: `campaignId` `slice4c-bounded-paid`. Projection SHA-256
(excludes only live `runId`)
`934506fac65bc58c2d17ff373a71835cfbe53f862204d9f1c6c99ab38d0967e5`.
`expectedCLIBuild` `1.0.5 (8226242)`. Catalog prices stay
`pricingConfirmed: false`.

## Reviews (complete)

- Containment: GO. Armed spawn fails closed. Darwin `setsid()` stays the known 4B.2 limit.
- Harness: NO-GO for unlocking `_billable_v3`. That path calls bare `launch_installed()` and would Send on official 1.0.4.
- Identity: pins re-derived live (official CLI `39366f77…`, pager `f434fa4f…`, installed Mach-O `55d85de4…`, Team `DD2GCQJVB4`).

## New files

| Path | Job |
|---|---|
| `scripts/acceptance/manifests/official-provider-slice4c-paid.json` | Frozen 4C matrix. `campaignId` is a product id, not `runId`. 20M/19M/1M. First packets: native → smallest direct → smallest brokered. `continuation: null` on those three. Do not overwrite v2/v3 fixtures. |
| `scripts/acceptance/harness/schema_4c.py` | Load/validate 4C only. Do not extend `schema_v3.py` into a paid matrix. |
| `scripts/acceptance/harness/authority_4c.py` | Four armed paths for `launch_installed`. CLI hard-budget document uses 20M/19M/1M and `expectedCLIBuild` `1.0.5 (8226242)`. Do not set `campaignId = runId`. |
| `scripts/acceptance/tests/test_4c_paid_lock.py` | Wrong `campaignId`/hash refuse. Schema-3 fixture still cannot Send. `_billable_v3` stays unarmed. Dry-run without Send. |

## Existing files

| File | Change | Must not change |
|---|---|---|
| `scripts/acceptance/run.py` | Add `_billable_4c`. Route 4C schema to it. Keep `version == 3` → ceiling refusal → `_billable_v3`. | Do not arm `_billable_v3`. Do not make schema-3 mean paid. |
| `scripts/acceptance/run.py` `_billable_4c` | Clone **armed** `_billable_v2` control flow: preflight, authority, four-arg `launch_installed` every epoch, early stop, no retries. | Never `resume_saved_task()`. Never bare `launch_installed()`. |
| `scripts/acceptance/harness/preflight_v2.py` | Pre-unlock: `require_4c_unlock_predicate(manifest, source_path=...)` exists and raises `PreflightError`. Unlock commit only: replace the unconditional `require_absolute_ceiling_support()` raise and the no-arg `main()` call. | Do not no-op. Do not pass on `schemaVersion==3`. Do not call the helper from the ceiling function until step 5. |
| `scripts/acceptance/harness/authority_4c.py` | Arm-time live hashes on the Swift sidecar (`endpointSHA256` / `boundProvenanceSHA256`) and on the CLI document when a candidate is present. Native freeze is `sha256(b"nativeXAI")`. | Do not copy v2 `03a28d4` hashes. Do not write hashes into the committed JSON. Do not invent an xAI host. |
| `scripts/acceptance/harness/driver.py` / `candidate_install.py` | Reuse. | Do not loosen all-four-together. Never write `~/.grok`. |
| `official-provider-slice4-v2.json`, `fresh-process-continuation-v3.json` | Leave as locked fixtures. | Do not upgrade v2 to 20M or turn v3 into the paid matrix. |
| Swift armed spawn / resolver | Prefer no change on this locked slice. | Ordinary lookup still never scans `candidate-runtime`. |

## Unlock predicate (not schemaVersion alone)

`require_4c_unlock_predicate` already encodes this and passes the committed 4C file / fails v2 and v3. It is **not** wired. After three reviews of installed `29c064f` + CLI `7e9f1ad`, `require_absolute_ceiling_support` may accept **only** all of:

1. Frozen `campaignId` `slice4c-bounded-paid`.
2. SHA-256 of the committed 4C manifest (projection excludes only live `runId`) equal to `934506fac65bc58c2d17ff373a71835cfbe53f862204d9f1c6c99ab38d0967e5`.
3. Ceiling triple: absolute 20M, allocatable ≤ 19M, reserve 1M.
4. Packet order: `nativeXAI`, then first `directProvider`, then first `brokeredOpenRouter`.

Mismatch raises `PreflightError` before runtime discovery, app launch, Keychain, or Send. `_billable_v3` + `fresh-process-continuation-v3.json` must still fail this predicate after unlock.

## Four-arg launch (every 4C epoch)

```text
launch_installed(
  budget_file=authority.authorization,
  cli_manifest_file=authority.cli_manifest,
  budget_ledger_file=authority.ledger,
  runtime_selection_file=authority.runtime_selection,
)
```

## Sidecar

1. Today: live selection **absent**. Pager copy `f434fa4f…933b` retained.
2. Arm: `python3 -m scripts.acceptance.harness.candidate_install install --source "$HOME/Documents/Codex/GrokBuild-Slice4B5/runtime/runtime-selection.json" --dest "$HOME/Library/Application Support/GrokBuild/candidate-runtime"`
3. Never point `GROKBUILD_SLICE4B3_RUNTIME_SELECTION` at `Documents/Codex/GrokBuild-Slice4B3/` (`14da2ef77…`).
4. After process-zero: rollback with two **distinct** empty timestamps. Unlink only the sidecar.

## Tests that must keep 4B.4 from Sending

- `AcceptanceHarnessTests.testSlice4B4Schema3BillableStillRefusesAbsoluteCeiling`
- `test_v3_install.test_paid_unlock_and_billable_v3_stay_locked` (`_billable_v3` has no `runtime_selection_file=`, no `resume_saved_task()`, no “later unlock path”)
- `test_v3_continuation.py` source pins on `_billable_v3`

## Implementation order

1. ~~`schema_4c` + dry-run 4C manifest. Still fully locked.~~ Landed.
2. ~~`_billable_4c` + `main` routing **behind** the still-unconditional ceiling refusal.~~ Landed.
3. ~~`authority_4c` + four-arg launch + install/rollback reuse.~~ Landed.
4. ~~Tests: v3 fixture still cannot Send; 4C dry-run only.~~ Landed.
5. **Separate unlock commit.** Do not start this commit until Jimmy says so. Runbook below.

Native schema-3 `credentialAuthorizationV3` bind remains the first leftover
inside step 5. Do not “fix” it by sending native on official 1.0.4. Live bind
hashes stay out of the committed matrix; arm-time authority now fills them.

## Step 5 runbook (not started)

Stop before this list unless Jimmy explicitly unlocks paid Send.

0. **Native Swift leftover (do this before any armed Send).** Campaign packet
   one is `nativeXAI` / `grok-4.6`. The prepared sidecar still has
   `managedProviderID` / `authScheme` null on that packet. Schema-3
   `AcceptanceBudgetManifest.isValid` requires every packet
   `credentialAuthorizationV3 != nil`, so a mixed 4C sidecar currently
   fail-closes in Swift. `ArmedV3DispatchExpectation` also refuses native
   `grok-4.6` without a live custom model + provider. `GrokProcess.start` only
   `posix_spawn`s the leased candidate when `credentialAuthorizationV3` is
   present; otherwise it locates official `~/.grok/bin/grok` 1.0.4.
   `ACPControlPlane.authorizes` would then take the 4M path. Solve that bind
   in Swift (or an equivalent fail-closed native-on-candidate path) before
   Sends. Do not send native on official 1.0.4. App-code changes wait for the
   final 4C `make ship`.
1. **Narrow the ceiling, nothing else.** In `scripts/acceptance/run.py` `main()`,
   schema-4 `--billable` must load the 4C manifest and call
   `require_4c_unlock_predicate(manifest, source_path=args.manifest)` **before**
   `_billable_4c`. Replace the unconditional raise inside
   `require_absolute_ceiling_support()` so it cannot remain a no-arg lock that
   `main()` still hits first. Keep schema-3 `--billable` on the old
   unconditional refusal (`fresh-process-continuation-v3.json` plus
   `_billable_v3` must still fail). Do not call `require_4c_paid_identity`
   from the ceiling function if that would let v3 sneak through.
2. **Confirm catalog prices.** Committed `pricingConfirmed` is false and
   non-native `frozenPricing.campaignConfirmed` is false. Dollar figures are
   unconfirmed copies of v2 catalog snapshots. Confirm live catalog, then
   flip those flags. `_billable_4c` already calls `require_4c_send_ready`.
   Recompute `FROZEN_MANIFEST_SHA256` after that JSON edit.
3. **Arm the live sidecar inside a 4C packet**, not as unlock itself:

   ```bash
   python3 -m scripts.acceptance.harness.candidate_install install \
     --source "$HOME/Documents/Codex/GrokBuild-Slice4B5/runtime/runtime-selection.json" \
     --dest "$HOME/Library/Application Support/GrokBuild/candidate-runtime"
   ```

   Never point `GROKBUILD_SLICE4B3_RUNTIME_SELECTION` at
   `Documents/Codex/GrokBuild-Slice4B3/` (`14da2ef77…`).
4. **Owner-local armed Sends.** Native → smallest direct → smallest brokered.
   Four-arg `launch_installed` every epoch. Early stop. No retries. No
   `resume_saved_task()`. No `_billable_v3`.
5. **Rollback** after process-zero with two **distinct** empty timestamps.
   Unlink only the sidecar. Keep the historical same-second
   `rollback-receipt-v1.json` at `2026-08-19T17:53:24-0500` as evidence.
6. **Receipts.** Retain model/route, permission, continuity, MCP discovery vs
   use, and process-generation boundaries.

### Tests that must keep 4B.4 from Sending after unlock

- `AcceptanceHarnessTests.testSlice4B4Schema3BillableStillRefusesAbsoluteCeiling`
- `test_v3_install.test_paid_unlock_and_billable_v3_stay_locked` (`_billable_v3` has no `runtime_selection_file=`, no `resume_saved_task()`, no “later unlock path”)
- `test_v3_continuation.py` source pins on `_billable_v3`
- `test_4c_paid_lock.test_schema3_billable_still_cannot_send`
- `Slice4B5LifecycleTests` pin that `_billable_v3` stays unarmed

## Out of scope

Pager rebuild, official CLI replace, Darwin `setsid` “fix”, docs-only `make ship` to chase stamp, unlocking `_billable_v3`, reusing the v2/v3 manifests as the paid matrix, `resume_saved_task()`, retries, substitute models, Slice 5.
