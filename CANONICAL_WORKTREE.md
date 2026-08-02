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
| Active release branch | `main` |
| Merged feature PR | `https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/1` |
| Merged provider-routing repair PR | `https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/2` |
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

## Current installed repair acceptance — provider routing and OAuth — 2026-08-02

- PR #1 merged as `c618bc214bfe4feb1f5a28190470f2cfa79f7fa2`. The first post-merge billable probe then exposed a release-blocking truth defect: a fresh tab saved as `gpt-5.6-terra`, and the launched CLI argv carried that selector, but ACP `session/new` retained Grok 4.5 and the first provider call was actually billed to `grok-4.5-build`. The backend receipt, not the picker label, caught the mismatch. The one affected call used 14,922 total tokens; no response body or credential is retained here.
- Repair commit `9304b7a1fe64ec13c27164bde12f0b6d33d0c8ba` makes startup reassert an explicit model through `session/set_model`, requires an exact effective-model readback before the composer can send, and fails closed on missing or wrong readback. Custom TOML table keys may match only their declared provider-facing `model` value, so `deepseek-deepseek-v4-flash-0731` can truthfully confirm `deepseek/deepseek-v4-flash-0731` without weakening the gate.
- Automated verification: focused ACP contracts **27/27**; full `swift test` **493 tests, 0 failures** in 15.468 seconds. Direct fake-ACP fixtures cover successful reassertion, wrong-model refusal, and exact custom table-key/provider-model alias confirmation.
- Repair candidate acceptance used clean stamp `9304b7a1fe64ec13c27164bde12f0b6d33d0c8ba` on `codex/fix-provider-launch-routing`; its `dist` and installed executable SHA-256 both equal `a2c5f23eca59b05261fdd2ba72f183ecbbeeecb9c45e3d7119d8fbb99652343b`.
- Direct provider acceptance used one minimal, explicitly authorized billable call per lane. OpenAI `gpt-5.6-terra` used 10,951 total tokens; Kimi `kimi-k3` used 12,481; OpenRouter API-key `deepseek/deepseek-v4-flash-0731` used 13,534; native `grok-4.5-build` used 14,914 and reported cost metadata. Each installed UI marker, live model receipt, backend history model, and one-call usage record agreed.
- OpenRouter S256 OAuth completed through the system browser and exact loopback callback. The installed provider card changed from **API key** to **OpenRouter OAuth**, reported 337 available models, and confirmed that the credential was saved in macOS Keychain. No key, authorization code, verifier, callback URL, or response body was copied into source, logs, tests, or receipts.
- Three distinct OAuth-backed OpenRouter models passed explicit installed-app billable acceptance: `deepseek/deepseek-v4-flash-0731` (13,459 tokens, 2,043 ms provider time), `google/gemini-2.5-flash` (10,917 tokens, 707 ms), and `openai/gpt-4.1-mini` (10,966 tokens, 3,007 ms). Each returned the requested exact marker, reported one model call, and matched the live and backend model IDs.
- User state changed intentionally for this authorized acceptance: the OpenRouter OAuth credential replaced the prior local connection, and Gemini 2.5 Flash plus GPT-4.1 Mini were added to the existing OpenRouter provider. `~/.grok/config.toml` remains owner-only mode `0600`, 2,308 bytes, SHA-256 `a5a079f739c151e202a9f3e133f0ae31a2a3b3caed748063e2f369b05b056dd5`. Existing direct OpenAI/Kimi entries, prior sessions, authenticated v3 authority, and all named rollback bundles remain retained.
- PR #2 merged as `eea6c9868154a38ab1f4c8ebe6263a2e7b8a5e6a`. The clean merged-`main` app is installed and visibly reports `Personal • main @ eea6c986`, version `0.1.20`; `dist` and installed executable SHA-256 both equal `cdd16ecda766a2d9497b9db7d6733ad91bf52cc998b4add32f7bb04d9cdfeb6f`. Deep/strict signing passes under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`; quarantine is absent. Five settled Models-pane samples were 0.0% CPU at 136,688 KB RSS with no owned child.
- Merged-main Settings acceptance still shows Grok signed in, OpenRouter as **OpenRouter OAuth**, and all three routed models: DeepSeek V4 Flash, Gemini 2.5 Flash, and GPT-4.1 Mini. The signed immediate rollback is `/Users/jimmyschmitz/.Trash/GrokBuild-pre-provider-routing-main-install-20260802-0038.app`; the pre-merged-main and pre-Slice-12 rollback bundles remain present.
- Known provider-switch boundary: a Terra web-search turn followed by an in-place switch to Grok produced `Prompt error: Invalid params` before any Grok usage or final response was recorded. A fresh disposable session switched GPT-4.1 Mini → Terra → Grok successfully when its history contained only plain assistant messages. This isolates the defect to cross-provider replay of provider-specific web/tool-call history, not OAuth, route selection, or silent fallback. Until history translation or isolation is implemented, start a new session before changing provider/model after a web or tool turn.
- This is an accepted personal development install. No tag, notarization, or public release is implied.

## Previous accepted installed receipt — Slices 11–12 — 2026-08-01

- Source commit stamped into the bundle: `4bffc490cb1c8b43650b2b918db007203cdbf992`
- Build receipt: `Personal • codex/warm-glass-ui @ 4bffc490` with `GrokBuildSourceDirty = false`; installed version remains `0.1.20` and the repository receipt points to `schmitzjimmy1-star/grok-build-desktop`.
- `dist` / installed executable SHA-256: `2899c861fd0edd70ea1a301911278906faff8059f72e775ee17854b263066b4e`
- Automated verification: final `make test` — **490 tests, 0 failures** in 14.404 seconds. The former order-sensitive legacy-transcript migration now uses sorted-key fingerprints and sub-millisecond `Date` equivalence; three consecutive pre-install full runs plus the final suite passed.
- Slice 11 installed acceptance: all fourteen Settings panes completed fresh AX round trips. Three saved tabs covered Grok 4.5, `deepseek/deepseek-v4-flash-0731`, and a temporary `gpt-5.6-terra` selection that was restored before quit. Exact relaunch recovered the saved DeepSeek/local-only state. The ten-minute soak collected 61 samples with max CPU 0.0%, RSS 22,096–114,544 KB, and zero children.
- Slice 12 authentication acceptance: Models reported the existing Grok CLI session **Signed in** through grok.com without inference. Existing Keychain-backed provider credentials migrated to non-secret **API key** provenance. Live catalog-only tests passed for OpenAI (**125** models), Kimi (**12**), and OpenRouter (**337**); no completion/provider prompt was sent. The installed OpenRouter editor exposed S256 browser connection, masked paste-key, local disconnect, remote-key management, and device-only Keychain disclosure without exposing the key.
- OAuth security/fixture receipt: the listener binds `127.0.0.1` on an ephemeral port, requires its random exact path, rejects a wrong path with 404, is cancellation/timeout bounded, exchanges only over HTTPS, and preserves the previous credential on failure. A new remote OAuth grant was intentionally not manufactured because it would rotate persistent account access; the real API-key route and all local OAuth/error contracts were accepted.
- Performance closeout: after one final installed OpenAI catalog validation, the Models pane settled at 0.1% CPU and about 60 MB resident with no owned child. The old dynamic relative-time label had reproduced roughly 14% CPU and was replaced by a static checked-at snapshot before the final build.
- Signing: deep/strict verification passes for `dist` and `/Applications/GrokBuild.app` under `Apple Development: jhschmitz1993@gmail.com (LS4SUB57QL)`, Team `DD2GCQJVB4`; quarantine is absent. This development build is not notarized and is not a public release artifact.
- Continuity/user state: exact final quit left no GrokBuild process; relaunch restored the saved DeepSeek tab, local messages, empty composer, and disabled Send. `~/.grok/config.toml` remains mode `0600`, 1,852 bytes, SHA-256 `54986189bf364f6abe7a06876425b576f9b02466177b181d4921640d4a62bce4`; the 67-file transcript digest remains `b2c7c44d313f6e42ba60b650b51cc524502e5e63cbda31b672873a919e9e3346`; preserved v2 remains 7,902 bytes at SHA-256 `b9d760c004f74f88996d75ee83df5a2f5636ded80c6863a996c63442d5bacad7`. Authenticated v3 authority remained present; only normal launch/validation metadata advanced.
- Immediate rollback: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-slice-12-20260801-232458.app` is the deep/strict-verified installed Slice 10 predecessor. Every older named rollback remains recoverable.
- Release decision: Slices 11–12 are ready for the existing draft PR. No merge, tag, notarization, or public release was performed.

## Previous accepted installed receipt — Slice 10 — 2026-08-01

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
