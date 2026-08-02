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

- Source commit stamped into the bundle: `99a7b1dfa68fe51eeee7d4e37dc3759feba1beb0`
- Build receipt: `personal • codex/warm-glass-ui @ 99a7b1df` with `GrokBuildSourceDirty = false`
- `dist` / installed executable SHA-256: `215472a9bd56dbe3f06c7a922e47d1b432f6922e3f7d26198e04ef795278af7f`
- Automated verification: `make test` — **470 tests, 0 failures**; focused Slice 7 Settings/schema/lifecycle/subprocess suites — **58 tests, 0 failures**
- Signing: deep/strict pass for the app and bundled helpers under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`; quarantine absent
- Recoverable pre-Slice-7 install: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-7-20260801-2102.app`; named pre-Slice-6, pre-Slice-5, pre-Slice-4, and pre-Slice-3 rollback bundles remain intact
- Installed Computer Use proof: MCP Servers, Workflows, Skills, Plugins, Marketplace, Hooks, Compatibility, and App exposed their explicit scopes and honest retained state. A structured MCP name/executable draft survived a pane change and was reverted without Add/Update or persistence. The existing MCP inventory showed only environment names, Marketplace showed source provenance and separate trust gates, Hooks reported a successful empty inventory, Compatibility rendered the 13 current cells with Codex sessions-only, and App kept installed/update identity separate from its Unknown active-session receipt. Command-Q followed by exact `/Applications/GrokBuild.app` relaunch visibly reported the stamped personal receipt. `~/.grok/config.toml` remained mode `0600` and byte-for-byte stable; the v2 rollback payload remained 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. No provider send, Settings mutation, connection/Doctor/update check, backend, browser, helper, or owned child ran; settled CPU sampled 0.0% three times.
