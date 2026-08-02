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

- Source commit stamped into the bundle: `1856cca4a77cd5ff39bffa23f337714bdd82357d`
- Build receipt: `personal • codex/warm-glass-ui @ 1856cca4` with `GrokBuildSourceDirty = false`
- `dist` / installed executable SHA-256: `5371d17205359756d52b56af352631c100c9ce3e77e1d024732d4d4efe95058e`
- Automated verification: `make test` — **460 tests, 0 failures**; focused Settings/runtime/lifecycle/browser/computer/agent/model suites — **125 tests, 0 failures**
- Signing: deep/strict pass for the app and bundled helpers under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`; quarantine absent
- Recoverable pre-Slice-6 install: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-6-20260801-2025.app`; named pre-Slice-5, pre-Slice-4, and pre-Slice-3 rollback bundles remain intact
- Installed Computer Use proof: all six priority panes visibly exposed their saved/draft/apply scope. An Agent default draft survived a Settings → App pane change and was reverted without Apply; Models, Permissions, Memory, Browser, and Computer Use each showed the shared honest future-session/current-tab contract. Browser diagnostics remained read-only, and Computer Use showed explicit permission-request buttons; none was invoked. Command-Q followed by exact `/Applications/GrokBuild.app` relaunch visibly reported the stamped personal repository/branch receipt. No provider send, connection test, backend, browser, helper test, or owned child ran.
