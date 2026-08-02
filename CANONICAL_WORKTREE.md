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

- Source commit stamped into the bundle: `3b5e1988ef79d8fb0d6b80bfbbcb84259b9399c1`
- Build receipt: `personal • codex/warm-glass-ui @ 3b5e1988` with `GrokBuildSourceDirty = false`
- `dist` / installed executable SHA-256: `002ccb8a32f852e64895228afd445aed2f4c7a7cd2d5519d34dc86980d8d529d`
- Automated verification: `make test` — **479 tests, 0 failures** in 14.166 seconds; focused Slice 9/performance, Settings, persistence, Markdown, and v3 lifecycle suites — **90 tests, 0 failures**
- Signing: deep/strict pass for the app and bundled helpers under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`; quarantine absent. Gatekeeper assessment remains rejected because this development-signed build is not notarized.
- Immediate recoverable pre-Slice-9 install: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-9-20260801-215323.app`, stamped with the preserved signed Slice 8 commit `68de2a9d5b774fc98fd5c126247fcd834d316c65`; the named pre-Slice-8, pre-Slice-7, pre-Slice-6, pre-Slice-5, pre-Slice-4, and pre-Slice-3 rollback bundles remain intact.
- Installed Computer Use proof: exact relaunch visibly restored `GPT-CENTRAL-RESUME-BASE-0731` and `GPT-CENTRAL-RESUME-FOLLOWUP-0731`, showed the local continuity boundary, and kept Send disabled. Models → Memory → Models retained the three-provider/three-custom-model inventory; three complete fourteen-pane Settings sweeps passed. No provider send, backend resume, Settings Apply, browser/helper action, `grok agent`, or owned child ran. Warm sweeps sampled 0.0% CPU at 83,120–89,152 KB RSS; relaunch sampled 0.0% CPU at 57,088–70,576 KB RSS; Command-Q left no GrokBuild or helper child.
- User-state receipts: `~/.grok/config.toml` remained mode `0600`, 1,852 bytes, SHA-256 `54986189bf364f6abe7a06876425b576f9b02466177b181d4921640d4a62bce4`; the 67-file transcript tree remained digest `b2c7c44d313f6e42ba60b650b51cc524502e5e63cbda31b672873a919e9e3346`; v2 remains 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. The app-owned update/last-flush receipt advanced during normal read-only launch/quit, but no Settings Apply or user transcript/config mutation was performed.
