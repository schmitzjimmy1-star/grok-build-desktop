# GrokBuild Desktop

Native SwiftUI macOS workbench for `grok agent stdio`.

## Hard identity stop

Work only in `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
on Jimmy's `schmitzjimmy1-star/grok-build-desktop` fork, installed as
`/Applications/GrokBuild.app`. Preserve `rimusz/grok-build-desktop` as read-only
upstream. Never build, install, publish, or borrow from the retired
`/Users/jimmyschmitz/Documents/Grok Builf` / `jimmmy-Jim/Grok-Build-GUI` line.

Before edits or acceptance, read and follow in order:

1. `CANONICAL_WORKTREE.md` — canonical identity and mandatory live preflight.
2. `ARCHITECTURE.md` — ownership, data flow, persistence, and file map.
3. `docs/OUTSTANDING.md` — current slice scope and Gates A–H when a campaign slice is active.
4. `docs/GROKBUILD_AGENTIC_COCKPIT_CAMPAIGN_2026-08-15.md` — current campaign.
   Historical campaign specs (`GROKBUILD_RESIDUAL_CLOSEOUT_2026-08-14.md` and the
   2026-08-13 spec) are closed campaigns, not current scope.

Stop on a path, branch, remote, installed-stamp, signing, hash, or dirty-state mismatch.

## Architecture boundary

Keep GrokBuild thin. The CLI owns ACP, MCP execution, skills, permissions, memory,
plan mode, and subagents. Prefer existing owners: `GrokProcess`, `GrokCLIService`,
`ChatStore`, `WorkspaceStore`, `SessionLayoutStore`, and `UpdateChecker`.
Feature owners are `AgentBrowserService`, `ComputerUseService`, and
`CustomModelStore`. Browser/Computer Use skills live under
`GrokBuild/Resources/Skills/`; `GrokBuildComputerUseMCP` and `agent-desktop` are
packaged helpers, not alternate runtimes. Keep session/workspace state in its existing
stores, minimize scope, and match surrounding Swift/SwiftUI conventions.

## Required verification for every code change

- Add or update behavioral tests in `Tests/GrokBuildTests/`; run focused tests, then
  `make test`.
- Package, sign, and install only through `make`; final acceptance uses `make ship`.
  It must prove stamp == HEAD, `dirty=false` on the committed build, dist/installed
  byte parity, deep/strict signing under Team `DD2GCQJVB4`, and no quarantine.
- Rebuild/relaunch and perform focused Computer Use acceptance against the real
  `/Applications/GrokBuild.app`. Reach the changed state and verify meaningful AX
  names/roles. Compilation or helper output is not installed-app proof.
- Update `ARCHITECTURE.md` for services, flows, persistence, notifications, or
  ownership; update `README.md` for visible behavior; update `BUILDING.md` or
  `scripts/README.md` for packaging/release changes; update bundled skills or
  `.cursor` rules/skills when their contracts change.
- Run `git diff --check` and review every intended path. Preserve unrelated changes;
  stage only the authorized slice. Commit/push/PR/merge only when authorized.

Money, auth, provider routing, model selection, entitlements, and signing require the
full receipt and explicitly authorized bounded live probes. Local UX/service changes
still require `make test`, `make ship`, and focused installed Computer Use.

Never hand-track a remembered hash or accept version `0.1.21` as identity. Re-derive
all receipts live. Always retain model/route, permission, continuity, MCP discovery vs
use, and process-generation boundaries; never invent provider fallback or success.
