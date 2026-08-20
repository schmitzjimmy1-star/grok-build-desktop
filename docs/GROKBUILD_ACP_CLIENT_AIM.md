# GrokBuild aim — GUI, ACP, CLI

Read this first. Campaign ledgers and 4C runbooks are evidence, not the
product contract.

GrokBuild is a **thin ACP client**. It is a SwiftUI workbench for
`grok agent stdio`. It is not a second agent runtime, not a TUI pager, and
not a place to invent extra RPC methods.

```text
GUI  (GrokBuild)     ACP JSON-RPC over stdio     CLI  (grok)
  Send  ─────────────────────────────────────►    agent stdio
  Stop  ─────────────────────────────────────►    session/cancel
  chrome / errors  ◄──────────────────────────    initialize, session/*,
                                                  session/update, permissions
```

## CLI owns the agent

The installed `grok` process owns ACP as the server, MCP execution, skills,
permissions, memory, plan mode, subagents, and hard-budget enforcement.

- Ordinary use: `~/.grok/bin/grok` **1.0.4**. Do not `grok update`.
- 4C native only: leased pager `1.0.5 (8226242)` via an Application Support
  sidecar. That copy never replaces `~/.grok/bin/grok`. Do not rebuild it.
  Darwin `setsid()` stays the known 4B.2 limit.
- Do not unlock `_billable_v3`. That path is 4B.4 continuation, not 4C.

## ACP is the only language between GUI and CLI

Every live turn is this sequence. No other handshake.

1. Spawn `grok … agent stdio` (armed 4C uses the leased pager).
2. `initialize`
3. `session/new` or `session/load`
4. optional `session/set_model` before the first assistant response
5. `session/prompt` (this is the billed turn)
6. `session/update` / permission / question notifications while the turn runs
7. Stop is ACP cancel (`session/cancel` / teardown of that process generation)

Write `initialize` on stdin without waiting for the first stdout byte. Stdio
agents often block on the first stdin line.

An empty `FileHandle` readability fire while the child is still running is
**not** ACP close. Keep listening until the child has exited. True stdout EOF
or a dead child fails the pending method immediately.

Name every failure after the pending method:

- `ACP initialize timed out.`
- `ACP initialize failed: stdio closed before the result.`
- `ACP initialize failed: grok exited before the result.`
- `ACP session/new timed out.` / `ACP session/load …` when that RPC is pending
- `ACP session/prompt failed.`

The error banner is one AX static text (`grok-acp-error-banner`) whose label
is that full ACP message. Stop turn means `session/prompt` started.

Do not add `/remember`, `/flush`, `/dream`, `/agents`, or other pager builtins
as GUI commands. Those are TUI-only. Do not send marker prompts such as
`[Plan approved]`. Answer the ACP request and let the CLI continue the same
turn.

## GUI owns presentation only

GrokBuild (`GrokProcess`, `ChatStore`, `ChatView`) may:

- spawn and tear down one `grok agent stdio` per tab
- send the ACP methods above
- render transcript, permissions, model picker, and named ACP errors
- persist local tabs, workspace, and continuity receipts

GrokBuild may not:

- execute tools, MCP servers, or provider calls itself
- invent a fallback provider or rewrite an older launch
- click **Resume current task** during 4C (that is ungoverned `resume_saved_task`)
- send native 4C on official 1.0.4 (native uses the leased pager)
- wait for Stop after a handshake that never reached `session/prompt`

Send is what starts ACP. Ask / Build / Review only seed a draft. Fresh tabs
stay idle until Send.

## Honest 4C status (2026-08-20)

The 4C executor is in tree. Paid Sends have **not** billed. Native
`initialize` still does not produce a live `session/prompt`.

| Ledger | `RUN_ID` | Result |
|---|---|---|
| 6–8 | various | Failed before `session/prompt`. Old copy said stdio closed. Not billed. |
| 9 | `20260820T050226Z` | Installed stamp `6af815f`, dirty=false, Mach-O `7a64e19c…`. Harness: `ACP session/prompt did not start, and no named ACP method failure was visible`. Empty `tabId`. Not billed. |

Do not reuse those ledgers. Do not start another `--billable` run unless Jimmy
asks. The remaining question is why the leased pager does not return an
`initialize` JSON-RPC result the GUI can surface as either Stop or a named
ACP banner. Do not “fix” that by rebuilding the pager or switching native to
official 1.0.4.

Campaign leftovers: `docs/GROKBUILD_SLICE4C_EDIT_MAP_2026-08-19.md` and
`docs/GROKBUILD_SLICE4C_CODEX_CONTINUE_2026-08-20.md`. This file wins if they
conflict.

## Identity (re-derive live)

Canonical worktree, remotes, and installed path:
[`CANONICAL_WORKTREE.md`](../CANONICAL_WORKTREE.md).
Service map: [`ARCHITECTURE.md`](../ARCHITECTURE.md).
Campaign ledger: [`docs/OUTSTANDING.md`](OUTSTANDING.md).
