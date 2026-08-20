# Codex continue — Slice 4C native ACP handshake

**Start at [`GROKBUILD_ACP_CLIENT_AIM.md`](../GROKBUILD_ACP_CLIENT_AIM.md).**
This file is campaign evidence only.

Ledger-9 (`RUN_ID=20260820T050226Z`) on installed `6af815f` failed:
`ACP session/prompt did not start, and no named ACP method failure was visible`.
Empty `tabId`. Not billed. Sidecar rolled back. Do not reuse ledgers 6–9.
Do not start another `--billable` run unless Jimmy asks.

---

Read this file before any 4C Send, pager rebuild, CLI upgrade, or `_billable_v3`
unlock. If it conflicts with the aim doc, the aim doc wins.

## Identity (re-derive live, do not memorize)

| Item | Canonical value |
|---|---|
| Worktree | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Branch | `cursor/official-runtime-s4c-locked-executor` |
| Fork | `schmitzjimmy1-star/grok-build-desktop` (`personal`) |
| Upstream | `rimusz/grok-build-desktop` (`origin`, fetch only) |
| Installed | `/Applications/GrokBuild.app` |
| Campaign | `slice4c-bounded-paid` |
| Version | `0.1.22` |
| Team | `DD2GCQJVB4` |
| Official CLI | `~/.grok/bin/grok` **1.0.4** (`39366f77…`). Do **not** `grok update`. |
| Leased pager | `1.0.5 (8226242)`, SHA-256 `f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b`. Do **not** rebuild. Darwin `setsid()` stays the known 4B.2 limit. |
| Sidecar source | `$HOME/Documents/Codex/GrokBuild-Slice4B5/runtime/runtime-selection.json` |
| Sidecar dest | `$HOME/Library/Application Support/GrokBuild/candidate-runtime/runtime-selection.json` |

Never point `GROKBUILD_SLICE4B3_RUNTIME_SELECTION` at
`Documents/Codex/GrokBuild-Slice4B3/` (`14da2ef77…`).

## Where this thread left the product

Native 4C `initialize` silence was a JSON-RPC non-response, not `v3Authority`
refusal. Two GUI/harness bugs stacked:

1. Empty `FileHandle` `availableData` when the stdout handler attaches is often
   **not** ACP close. Old code niled the handler and treated that as death.
2. `wait_for_acp_startup_outcome` walked only clickable `@` refs, so the error
   banner was invisible and the harness waited for Stop.

Fix in this HEAD (ACP language, keep-listening, AX text walk):

- Timeouts: `ACP initialize timed out.` (or `session/new` / `session/load`).
- Transport: `ACP initialize failed: stdio closed before the result.` /
  `ACP initialize failed: grok exited before the result.`
- Empty stdout while the child is still running: keep listening.
- Error banner: one AX static text, identifier `grok-acp-error-banner`.
- Harness walks every AX node. Stop turn means `session/prompt` started.
- ChatStore watchdog fallback uses the same ACP timeout text.
- Do **not** wait for first stdout before `initialize` (deadlock).

GrokBuild stays a thin ACP client: `initialize` → `session/new`|`session/load`
→ `session/prompt`. Stop is ACP cancel. Do not add pager builtins.

## Spent ledgers (none billed)

Ledgers 6–9 failed before `session/prompt`. They are evidence, not reusable.

- Ledger-8 `RUN_ID=20260820T044027Z` exit 2: user-visible
  `grok closed stdio before ACP initialize completed` (old copy). Harness
  waiter never saw the banner. `tabId` / `processGeneration` empty. Not a
  billed turn.
- Ledger-9 `RUN_ID=20260820T050226Z` exit 2: installed stamp `6af815f`,
  dirty=false, Mach-O `7a64e19c…`. Harness:
  `ACP session/prompt did not start, and no named ACP method failure was visible`.
  Empty `tabId`. Not a billed turn. Sidecar rolled back after two empty
  process-zero samples.

Packets remain: `S4C-NAT-CTRL` → `S4C-OAI-H-NO` → `S4C-OR-OW-NO`. Early stop.
No retries. No substitute models.

## Hard stops

- Do not unlock `_billable_v3`.
- Never `resume_saved_task()`. Never bare `launch_installed()`.
- Never native Send on official 1.0.4.
- Never click **Resume current task**.
- Do not `tee` the 4C runner under `set -e`.
- Do not pre-create the ledger file (`require_clean_test_ledger`).
- During `_billable_4c`, do not also drive GrokBuild with Cursor
  `user-grokbuild-computer-use`. Kill leftover `GrokBuildComputerUseMCP` /
  `agent-desktop` so process-zero can pass. Owned names: `GrokBuild`, `grok`,
  `GrokBuildComputerUseMCP`, `agent-desktop`.
- Preflight requires `grokbuild.selectedAgent` **absent** (Default).
- Sidebar collapsed hid `Project grok-build-desktop`;
  `defaults write com.grokbuild.app grokbuild.sidebarVisible -bool true`.
- Exclusive sidecar install: unlink existing `runtime-selection.json` first.
- After packets: quit + two distinct empty process-zero samples; unlink **only**
  the selection sidecar; restore `selectedAgent` if you changed it.
- Do not `make ship` a docs-only successor just to chase stamp == HEAD.
- Commit / push / PR / merge only when Jimmy asks.

## Next owner-local 4C command

Do **not** run this unless Jimmy asks. Ledger-9 is spent. Use a new path
(`ledger-10` or later). Stamp must equal HEAD with `dirty=false` on
`/Applications/GrokBuild.app`.

```bash
python3 -m scripts.acceptance.harness.candidate_install install \
  --source "$HOME/Documents/Codex/GrokBuild-Slice4B5/runtime/runtime-selection.json" \
  --dest "$HOME/Library/Application Support/GrokBuild/candidate-runtime"

python3 scripts/acceptance/run.py \
  --manifest scripts/acceptance/manifests/official-provider-slice4c-paid.json \
  --billable \
  --run-id "$(date -u +%Y%m%dT%H%M%SZ)" \
  --ledger /tmp/grokbuild-s4c-ledger-10.jsonl \
  --candidate-selection "$HOME/Library/Application Support/GrokBuild/candidate-runtime/runtime-selection.json"
```

Use a new ledger path if `ledger-10` already exists. Never reuse 6–9.

If `initialize` still times out after this ship, the remaining question is
whether the leased pager answers JSON-RPC on stdin. Do not rebuild the pager
or switch native to official 1.0.4 to “fix” it.

## Ship / ledger receipts

- Product commit: `6af815f24969f7eaeb5410f1356db8c8a90d1ea8`
- Installed stamp: `6af815f` (same), `dirty=false`
- Installed Mach-O SHA-256: `7a64e19c7d374ddaf84033573c787a32ac06374461a8a0a968ebff2c486b46a0`
- Team: `DD2GCQJVB4`
- Ledger path / `RUN_ID`: `/tmp/grokbuild-s4c-ledger-9.jsonl` / `20260820T050226Z`
- Exit code: 2
- Native packet outcome: no Stop, no named ACP banner visible to harness
- Billed?: no
- Sidecar after rollback: absent (`runtimeSelectionRemoved: true`)
- Process-zero samples: `2026-08-20T00:04:55-0500` and `2026-08-20T00:05:00-0500`; extra rollback samples `00:05:40` / `00:05:45`

## Out of scope

Pager rebuild, official CLI replace, Darwin `setsid` “fix”, unlocking
`_billable_v3`, `resume_saved_task()`, retries, substitute models, Slice 5,
writes to `origin`.
