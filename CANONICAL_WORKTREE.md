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

- Source commit stamped into the bundle: `68de2a9d5b774fc98fd5c126247fcd834d316c65`
- Build receipt: `personal • codex/warm-glass-ui @ 68de2a9d` with `GrokBuildSourceDirty = false`
- `dist` / installed executable SHA-256: `5908269a804b9af80421cdf8a476317fd4d3c52afa2b6f7bf48307000afb3d21`
- Automated verification: `make test` — **475 tests, 0 failures**; focused Slice 8 persistence suite — **47 tests, 0 failures**
- Signing: deep/strict pass for the app and bundled helpers under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`; quarantine absent
- Recoverable pre-Slice-8 install: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-8-20260801-2119.app`; pre-Slice-7, pre-Slice-6, pre-Slice-5, pre-Slice-4, and pre-Slice-3 rollback bundles remain intact
- Installed Computer Use proof: authenticated v3 lifecycle and continuity boundaries were unchanged. A visible local marker transcript restored, rendered its local-only recovery boundary, and kept Send disabled; command-Q followed by exact `/Applications/GrokBuild.app` relaunch restored it again. Its 33 legacy v1 transcript entries remain intact, while 33 verified v3 bodies, 33 metadata sidecars, and one migration marker reside in an owner-only transcript directory. Selecting another tab did not change the complete transcript-tree digest. No provider send, backend resume, Settings mutation, browser, helper, `grok agent`, or owned child ran; settled CPU sampled 0.0% three times. Gatekeeper assessment is not release proof: this development-signed bundle is not notarized.
