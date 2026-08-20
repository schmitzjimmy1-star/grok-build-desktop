# Slice 4C edit map — 2026-08-19

Locked executor (steps 1–4) plus the pre-unlock drop-in (this slice) are in
tree. They do **not** authorize a paid Send, a pager rebuild, `grok update`,
unlocking `_billable_v3`, or narrowing `require_absolute_ceiling_support()`.

Product stamp is `18b2549` after the first 4C app-code `make ship`
(dirty leftover tree). Installed Mach-O SHA-256
`1aa3318ff207e0fe2a3dd8a108b1b3a3344058dec1027a3942f8e58661fa28c4`.
CLI leftover PR #7 is **merged** as `7e9f1ad`. Live Application Support
`runtime-selection.json` stays **absent** until a 4C packet arms it.

Frozen identity: `campaignId` `slice4c-bounded-paid`. Projection SHA-256
(excludes only live `runId`)
`e1fbfe81221c3f58d9c0ef0842610e90048d9cb5616347f00761a7d751e7b11c`.
`expectedCLIBuild` `1.0.5 (8226242)`. Catalog prices are
`pricingConfirmed: true` after live OpenAI Terra $2/$12 and OpenRouter
`deepseek/deepseek-v4-flash-0731` uncached-upper-bound confirm. The
brokered packet pins the live configured `-0731` model, not the family
catalog slug.

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
| `scripts/acceptance/run.py` | Add `_billable_4c`. Route 4C schema to it. Keep `version == 3` → no-arg ceiling refusal → `_billable_v3`. Schema-4 `--billable` now calls the ceiling dispatcher with the 4C manifest. | Do not arm `_billable_v3`. Do not make schema-3 mean paid. |
| `scripts/acceptance/run.py` `_billable_4c` | Clone **armed** `_billable_v2` control flow: preflight, authority, four-arg `launch_installed` every epoch, early stop, no retries. | Never `resume_saved_task()`. Never bare `launch_installed()`. |
| `scripts/acceptance/harness/preflight_v2.py` | `require_4c_unlock_predicate` exists. `require_absolute_ceiling_support(manifest, source_path=...)` delegates for schema-4 only. No-arg still raises the 4M lock. Schema-4 `preflight()` uses `require_4c_leased_runtime` (official 1.0.4 + pager 1.0.5). | Do not no-op. Do not pass on `schemaVersion==3`. Do not require official 1.0.5. |
| `scripts/acceptance/harness/authority_4c.py` | Arm-time live hashes on the Swift sidecar (`endpointSHA256` / `boundProvenanceSHA256`) and on the CLI document when a candidate is present. Native freeze is `sha256(b"nativeXAI")`. | Do not copy v2 `03a28d4` hashes. Do not write hashes into the committed JSON. Do not invent an xAI host. |
| `scripts/acceptance/harness/driver.py` / `candidate_install.py` | Reuse. | Do not loosen all-four-together. Never write `~/.grok`. |
| `official-provider-slice4-v2.json`, `fresh-process-continuation-v3.json` | Leave as locked fixtures. | Do not upgrade v2 to 20M or turn v3 into the paid matrix. |
| Swift armed spawn / resolver | Native freeze bind: mixed schema-3 `isValid`, `tryMakeNative`, leased spawn without Keychain, `campaignId` match. Ordinary lookup still never scans `candidate-runtime`. | Do not invent an xAI host. Do not send native on official 1.0.4. |

## Unlock predicate (not schemaVersion alone)

`require_4c_unlock_predicate` already encodes this and passes the committed 4C file / fails v2 and v3. It is **wired** from `require_absolute_ceiling_support` when both a schema-4 manifest and source path are supplied. After three reviews of installed `29c064f` + CLI `7e9f1ad`, that dispatcher accepts **only** all of:

1. Frozen `campaignId` `slice4c-bounded-paid`.
2. SHA-256 of the committed 4C manifest (projection excludes only live `runId`) equal to `e1fbfe81221c3f58d9c0ef0842610e90048d9cb5616347f00761a7d751e7b11c`.
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

Native schema-3 `credentialAuthorizationV3` bind is implemented: mixed
matrices validate, `tryMakeNative` binds grok-4.6 without a custom model, and
`GrokProcess.start` `posix_spawn`s the leased candidate with no Keychain
transfer. Do not send native on official 1.0.4. Live bind hashes stay out of
the committed matrix; arm-time authority still fills them.

## Step 5 runbook (native bind and ceiling dispatcher landed)

Stop before live Sends until the sidecar is armed. Native bind, ceiling
dispatcher, catalog prices, leased-runtime preflight, and the live `-0731`
OpenRouter pin are in tree. First 4C `make ship` landed dirty at `18b2549`.

0. ~~**Native Swift leftover.**~~ Landed: freeze `sha256(b"nativeXAI")`, optional
   sidecar `campaignId`, native spawn without Keychain. First 4C app-code
   `make ship` landed; installed Mach-O is `1aa3318f…`.
1. ~~**Narrow the ceiling.**~~ Landed: `require_absolute_ceiling_support(manifest,
   source_path=...)` delegates to `require_4c_unlock_predicate` for schema-4
   only. No-arg and schema-3 still raise the 4M refusal. `_billable_4c`
   `preflight()` uses the same dispatcher.
2. ~~**Confirm catalog prices.**~~ Landed: OpenAI Terra Input $2.00 / Output $12.00
   from developers.openai.com model docs; OpenRouter
   `deepseek/deepseek-v4-flash` live prompt/completion is below the frozen
   $0.09/$0.18 uncached upper bound. The brokered packet pins live
   `deepseek/deepseek-v4-flash-0731`. Identity SHA-256 is
   `e1fbfe81221c3f58d9c0ef0842610e90048d9cb5616347f00761a7d751e7b11c`.
2b. ~~**Leased-runtime leftover.**~~ Landed: schema-4 preflight keeps official
    grok at 1.0.4 and requires pager `1.0.5 (8226242)` / `f434fa4f…933b`.
    `require_runtime_floor()` still refuses official 1.0.4 for v2/v3.
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

## Native ACP handshake (GUI side, 2026-08-20)

Live native 4C `initialize` silence was a JSON-RPC non-response, not a
`v3Authority` refusal. GUI/harness changes in this worktree:

- Armed handshake RPCs wait 90s; ChatStore armed watchdog is 120s.
- Timeouts name the method and append redacted startup stderr.
- During `.starting`, stdout EOF or a dead child fails the pending RPC
  immediately. Do not wait for first stdout before `initialize`.
- `_billable_4c` waits for Stop turn or `grok-acp-error-banner` after Send.
  `send_may_be_live` stays false until that live-turn signal, so pre-prompt
  ACP failure does not click Stop.

These do not rebuild pager `1.0.5 (8226242)` or replace official grok 1.0.4.
They cannot ship until Jimmy commits; installed stamp remains the last clean
HEAD until `make ship`.

## Out of scope

Pager rebuild, official CLI replace, Darwin `setsid` “fix”, docs-only `make ship` to chase stamp, unlocking `_billable_v3`, reusing the v2/v3 manifests as the paid matrix, `resume_saved_task()`, retries, substitute models, Slice 5.
