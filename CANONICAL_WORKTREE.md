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

## Current accepted installed receipt — Slice 10 — 2026-08-01

- Source commit stamped into the bundle: `22e95f31d9986d89129164477f5026fafd792174`
- Build receipt: `personal • codex/warm-glass-ui @ 22e95f31` with `GrokBuildSourceDirty = false`
- `dist` / installed executable SHA-256: `05114763add8d07f5fc390e2ff57d139b0f984d009126f663dcefc1d0d136d8d`
- Automated verification: `make test` — **482 tests, 0 failures** in 14.473 seconds; focused `SettingsTabTests` — **16 tests, 0 failures**. Slice 10 scroll, appearance, table-fallback, accessibility, and rich-content source contracts are included in the full suite.
- Installed accessibility acceptance: the clean exact bundle reported the `22e95f31` receipt, exposed independent `grok-appearance-system`, `grok-appearance-light`, and `grok-appearance-dark` buttons, and stayed alive through Dark apply → Light apply (the former crash path) → Dark restore. Chat AX order exposed workbench controls → transcript → composer; the preserved local markers, continuity boundary, empty composer, and disabled Send survived quit/relaunch.
- Crash regression: the pre-fix segmented-picker report remains preserved at `/Users/jimmyschmitz/Library/Logs/DiagnosticReports/GrokBuild-2026-08-01-223824.ips`; no newer GrokBuild report appeared after the fixed accessibility sequence. The fix is the independent-button appearance surface with a visible selected checkmark, avoiding the AppKit `NSSegmentedCell` accessibility press path.
- Signing: deep/strict verification passes for the app and bundled helpers under `Apple Development: jhschmitz@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`, timestamp `2026-08-01 22:51:42`; quarantine is absent. Gatekeeper assessment remains rejected because this development-signed build is not notarized.
- Backend boundary: no provider send, Test Connection, backend resume, `grok agent`, browser/helper action, or owned provider child ran. After quit, no GrokBuild process remained; after exact relaunch, settled CPU was `0.0%` across the final two one-second samples at 116,080 KB RSS.
- User-state receipts: `~/.grok/config.toml` remained mode `0600`, 1,852 bytes, SHA-256 `54986189bf364f6abe7a06876425b576f9b02466177b181d4921640d4a62bce4`; the 67-file transcript tree remained digest `b2c7c44d313f6e42ba60b650b51cc524502e5e63cbda31b672873a919e9e3346`; preserved v2 remains 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`; appearance is intentionally `dark` after the existing-install migration. Authenticated v3 remained present; the current raw snapshot/commit/flush receipts hash to `9d3242d17af7852d44fde495a2f14b32c10cf7f331da90754d1a7643faa63e82`, `873c0d26e648a87a84e60ce30b9c4e1f9d42067701062a4057b7f9f2cae56e67`, and `938a3defe145555b60b7803ed807480a14f6d01c2ea7e599a3db8d55b0ad5b65`; normal lifecycle receipts may advance, but no authenticated v3 continuity or provider state was changed.
- Rollback bundles remain recoverable: Slice 9 `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-10-20260801-223428.app` (stamp `3b5e1988ef79d8fb0d6b80bfbbcb84259b9399c1`), its `dist` twin, the reproduced-crash checkpoint `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-10-crash-20260801-224215.app`, the fixed pre-checkmark checkpoint `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-10-pre-checkmark-20260801-224938.app`, and the prior named Slice 9/8-and-older bundles.
