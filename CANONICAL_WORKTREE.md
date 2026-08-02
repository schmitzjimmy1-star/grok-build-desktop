# CANONICAL GROKBUILD WORKTREE — DO NOT SUBSTITUTE

> [!CAUTION]
> This is the only maintained GrokBuild application line. Grok, GPT, Claude,
> Codex, and human operators must use this worktree for every active repair,
> build, installation, and acceptance pass.

## Maintained line

| Identity | Canonical value |
|---|---|
| Local worktree | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Jimmy's repository | `https://github.com/schmitzjimmy1-star/grok-build-desktop` (`personal`) |
| Preserved upstream | `https://github.com/rimusz/grok-build-desktop` (`origin`, fetch/reference only) |
| Active feature branch | `codex/warm-glass-ui` |
| Draft PR | `https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/1` |
| Installed app | `/Applications/GrokBuild.app` |

The commit changes whenever work is committed, so never freeze a mutable HEAD in
this permanent identity table. Resolve it with `git rev-parse HEAD`. Packaged app
bundles stamp `GrokBuildSourceRepository`, `GrokBuildSourceBranch`,
`GrokBuildSourceCommit`, `GrokBuildSourceDirty`, and `GrokBuildBuildChannel` into
`Contents/Info.plist`; About and Settings → App surface the same receipt.

## Retired duplicate — reference only

`/Users/jimmyschmitz/Documents/Grok Builf` and
`https://github.com/jimmmy-Jim/Grok-Build-GUI` are the retired custom ACP GUI.
They are preserved as historical evidence only. **DO NOT BUILD, INSTALL, OR CONTINUE
that line** unless Jimmy explicitly reactivates it in a new request.
Its old app name was `Grok Build.app`; the maintained installed product is
`/Applications/GrokBuild.app`.

## Mandatory preflight

Before changing or accepting GrokBuild:

```bash
pwd
git status --short --branch
git remote -v
git rev-parse HEAD
plutil -p /Applications/GrokBuild.app/Contents/Info.plist
shasum -a 256 dist/GrokBuild.app/Contents/MacOS/GrokBuild \
  /Applications/GrokBuild.app/Contents/MacOS/GrokBuild
```

Stop on any path, branch, repository, or bundle mismatch. The stamped commit is
the exact clean source used to compile the installed binary. It must equal HEAD
or be an ancestor followed only by receipt/documentation commits; prove the
latter with:

```bash
git merge-base --is-ancestor <stamped-commit> HEAD
git diff --quiet <stamped-commit>..HEAD -- \
  GrokBuild GrokBuildComputerUseCore GrokBuildComputerUseMCP \
  Package.swift VERSION Makefile scripts
```

A model provider selected *inside* GrokBuild (Grok, GPT, OpenRouter, Kimi) never
changes which application repository owns the workbench.

## Current accepted installed receipt — 2026-08-01

- Source commit stamped into the bundle: `760281c3d136ffe14ac911206b3a5bb79e140610`
- Build receipt: `personal • codex/warm-glass-ui @ 760281c3` with `GrokBuildSourceDirty = false`
- `dist` / installed executable SHA-256: `d46319b537e40a54fd0de3773dfd58dbd8e205bdef699c03f9182879f34e2039`
- Automated verification: `make test` — **448 tests, 0 failures**; focused provenance/lifecycle/source-contract suites — **69 tests, 0 failures**
- Signing: deep/strict pass for app and helpers, Team `DD2GCQJVB4`; quarantine absent
- Recoverable pre-Slice-4 install: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-4-20260801-192858.app`; the named pre-Slice-3 rollback remains at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-3-20260801-1857.app`
- Installed Computer Use proof: the missing-backend surface visibly exposed **Continue as New** and **Relink…**, candidate review remained read-only, Settings → App showed the personal repository/branch/`760281c3` receipt, and graceful quit/relaunch preserved readable local work with zero owned backend/helper children
