# GrokBuild Official Runtime Alignment Campaign — 2026-08-16

Status: **active; Slice 0 publication only.** Jimmy authorized a rigorous merge-per-slice
campaign on 2026-08-16. Every slice gets its own branch, explicit commits, ready
pull request, exact-head required checks, normal merge, merged-main installation,
and process-zero closeout before the next slice begins.

Baseline: clean `main == personal/main` at
`39471368ec906c1e7bd220af870c4604f0815e3d` (PR #113). The installed app is the
clean code-bearing ancestor `a437c018911358b87aae9bcc1e520eeeafc7e44f`; the
dist and installed executables match byte-for-byte. Installed CLI authority is
`grok 1.0.4 (d846eb93d94d) [stable]`. Official 1.0.5 source informed this
campaign, but no CLI upgrade is authorized by Slice 0.

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
| **0** | **Restore CLI execution ownership** | Disable ACP client FS/terminal capabilities; remove Swift reverse executors; fail surprise reverse execution closed; retain typed tool receipts. | **Candidate accepted; publication pending** |
| **1** | **Contain model-config corruption** | Refuse unsafe nested-model rewrites, add official nested-TOML fixtures, then choose a structure-preserving ownership boundary. | Locked |
| **2** | **Typed ACP control spine** | Add a version/capability-aware facade over each existing ACP connection; first methods are models, usage, session metadata, and bounded session updates. | Locked |
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

Publication is still pending. Slice 1 remains locked until the exact PR head is
CI-green, merged normally, and merged `main` passes install/parity/process-zero
closeout.
