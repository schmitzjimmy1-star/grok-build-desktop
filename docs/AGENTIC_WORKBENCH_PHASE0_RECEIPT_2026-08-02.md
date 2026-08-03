# Agentic Workbench Phase 0 Receipt — 2026-08-02

## Scope and gate

This receipt records the read-only Phase 0 baseline and the disposable live probes required by `docs/AGENTIC_WORKBENCH_MCP_MULTIPHASE_HANDOFF.md`. The implementation slice selected from this baseline is the MCP readiness barrier. The cross-provider history issue remains a spike because it did not reproduce on the current installed route.

Billable authorization for this campaign: **200,000 provider tokens maximum**, with no additional approval prompt before that ceiling.

## Canonical identity

- Worktree: `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- Branch: `main`
- HEAD: `7ead3abfaa8f3fc5e08c69976b4eb64252b0594b`
- `personal` remote: `https://github.com/schmitzjimmy1-star/grok-build-desktop.git`
- Installed app: `/Applications/GrokBuild.app`
- Installed source stamp: `eea6c9868154a38ab1f4c8ebe6263a2e7b8a5e6a`, personal `main`, clean
- Installed and `dist/GrokBuild.app` executable SHA-256: `cdd16ecda766a2d9497b9db7d6733ad91bf52cc998b4add32f7bb04d9cdfeb6f`
- `eea6c986` is an ancestor of current HEAD; the code-bearing delta is docs-only.
- Existing untracked user docs preserved unchanged: `docs/AGENTIC_WORKBENCH_MCP_MULTIPHASE_HANDOFF.md` and `docs/TOOL_USE_AND_MULTI_TURN_CONTRACT.md`.

The installed app passes deep/strict code-sign verification and has no quarantine attribute. Gatekeeper rejection is expected for this Apple Development, non-notarized build.

## Runtime baseline

- Installed GrokBuild: `0.1.20`; bundle ID `com.grokbuild.app`; channel `personal`.
- Installed Grok CLI: `0.2.118 (1e1687c1cf6a) [stable]`.
- Current Settings receipt: Grok signed in; OpenAI/ChatGPT, Kimi, and OpenRouter OAuth connected; four custom models configured.
- Computer Use: built-in `agent-desktop` ready; Accessibility and Screen Recording granted; screenshots enabled; Allow policy selected.
- Browser pane still reports `agent-browser not installed`, while the live ACP session starts the configured browser bridge successfully. This is a separate status/readiness coherence follow-up.
- A read-only process snapshot showed the installed app plus four existing Grok sessions and their browser/Computer Use helpers. No existing session was sent a probe or terminated.

## Disposable live probes

### MCP readiness race — reproduced

Fresh Terra session, with Browser and Computer Use MCP servers enabled:

- First required two-tool prompt: the assistant returned that “Computer Use and Browser Tools are still connecting” and made neither required call.
- Same-session retry: passed with the tool activity receipt showing `computer_snapshot`, `browser_open_url`, and `browser_snapshot`, followed by the required marker.
- Backend MCP event timing for the disposable session shows the three MCP servers starting before the first turn and completing initialization about 1.1 seconds after session creation. The first inference began before that initialization completed.
- Redacted backend session suffix: `e8417921e6a9`.

### Cross-provider tool history — not reproduced

Two fresh sessions completed a web-search turn and then switched in place to Grok 4.5:

- Terra → Grok 4.5: plain post-switch prompt passed; session suffix `80538bc546db`.
- OpenRouter DeepSeek → Grok 4.5: plain post-switch prompt passed; session suffix `e5c31e5bf1b`.

The historical `Invalid params` defect remains a documented risk, but current evidence does not justify changing provider-history semantics. Keep the operational guard—new session after provider-specific web/tool history—until a failing current receipt or a deterministic fixture exists.

## Provider-token ledger

The local Grok unified log records 13 provider model calls for the three disposable sessions:

- prompt tokens: `178,659`
- cached prompt tokens: `116,575`
- completion tokens: `1,003`
- reasoning tokens: `658`
- conservative tracked total (`prompt + completion + reasoning`): **`180,320`**
- remaining campaign ceiling: **`19,680`**

No further billable probes are planned in this slice.

## Ranked disposition

1. **Fix now — MCP readiness barrier.** Keep the ACP session non-ready until the initial MCP set has had a bounded, cancellable settle window. This prevents the first billable turn from racing tool discovery.
2. **Spike — cross-provider history translation or fail-closed guard.** Preserve the existing new-session rule and collect a deterministic failing fixture before altering history.
3. **Defer — structured run state, bounded multi-agent orchestration, MCP builder, and Chicago History Evidence Lab fixture.** These depend on the lifecycle/readiness boundary and should not be layered onto a race.

## Exit condition for the selected slice

Add a local deterministic readiness contract, cover it with Swift tests, run the full suite, rebuild/install the canonical app, and perform installed-app Computer Use verification without spending another provider call in this 200,000-token campaign.

## Selected slice implementation and installed acceptance — 2026-08-02

- Added `GrokBuild/Services/MCPReadinessPolicy.swift`: a cancellable 1.5-second settle barrier when MCP servers are configured. `GrokProcess` remains non-ready until that barrier completes, and `ChatView` keeps Send disabled while startup is in progress.
- Focused readiness tests: `4/4` passed. Full `make test`: `497/497` passed with zero failures. `git diff --check` passed.
- `make install` and `make run` completed. The installed `/Applications/GrokBuild.app` was quit, relaunched, and inspected through Computer Use; the UI rendered normally and the App settings receipt reported `Installed Version 0.1.20 Personal • main @ 7ead3abf (dirty)` with the canonical personal repository link.
- Final installed source stamp: commit `7ead3abfaa8f3fc5e08c69976b4eb64252b0594b`, channel `personal`, branch `main`, dirty `true`. Final installed and `dist/GrokBuild.app` executable SHA-256: `2d16e247ae771d311a8059ebdb29cafd29675a21dada8769dd5dcef46bc942aa`. Deep/strict code-sign verification passed and quarantine was absent.
- Recoverable predecessor backup: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-phase1-20260802-0142.app`.
- No provider call was made after the ledger above; tracked campaign usage remains `180,320 / 200,000`, with `19,680` remaining. The post-fix acceptance is local lifecycle/UI proof; no post-fix billable tool probe was run. Cross-provider history remains a spike.

## Phase 1 lifecycle receipt slice — 2026-08-02

- Added `MCPServerLifecycle`, `MCPServerStatus`, and `MCPReadinessPolicy` receipts. Configured servers now move through secret-free `Connecting`, `Ready`, `Failed`, and `Stopped` states at the GrokProcess generation boundary. The receipt deliberately reports no tool count because the installed CLI exposes no stable per-server capability event.
- `ChatStore` mirrors the current-generation receipts, and the Browser/Computer Use menus expose the exact server state and non-secret reason when a live tab has that server configured. A local-only tab correctly shows no fabricated live MCP receipt.
- Focused readiness/lifecycle suite: `6/6` passed. Full `make test`: `499/499` passed with zero failures. `make install` and `make run` completed; the installed `/Applications/GrokBuild.app` was relaunched and Computer Use inspected its App identity pane successfully.
- Final installed and `dist/GrokBuild.app` executable SHA-256: `549ea2e9c7846aebdb7e6c6716865a8107e4ceefc7e2d0ed3ad53566b07a6597`. Deep/strict signing verification passed and quarantine was absent. Recoverable predecessor: `/Users/jimmyschmitz/.Trash/GrokBuild-pre-mcp-lifecycle-20260802-0155.app`.
- No provider call was made during this follow-on slice. Usage remains `180,320 / 200,000`; cross-provider history remains a spike, and a live tool-required post-fix probe remains intentionally unclaimed because the selected tab had no backend and the remaining budget is not a safe basis for another large-context call.

## Next two-session acceptance authorization — 2026-08-02

- Authorization window: **up to 1,000,000 provider tokens across exactly the next two disposable GrokBuild acceptance sessions**.
- The earlier Phase 0 ledger (`180,320` tracked provider tokens under the prior `200,000` ceiling) is historical and is not silently rolled into this new window. The new window is tracked separately from zero.
- Route policy: use only the explicitly selected non-Kimi routes for the two sessions. **Kimi 3 is excluded from this window and must not be selected, started, or used as a fallback.**
- Planned session 1: fresh Terra session with Browser and Computer Use MCP readiness/tool-required acceptance.
- Planned session 2: fresh DeepSeek session with a bounded tool-history/provider-boundary probe, switching only after the tool-rich turn if the app offers that route.
- Publication, commit, push, PR, deployment, and destructive cleanup remain disabled by this authorization.
- Per-session backend IDs, route receipts, pass/fail disposition, and the new-window token ledger will be appended below after each session settles.

## Two-session non-Kimi acceptance receipt — 2026-08-02

### Session 1 — Terra MCP readiness and required tools

- Fresh disposable tab/backend: full backend session ID `019fc149-4cec-7760-ad1e-bbd283184f05`; UI receipt tab suffix `8DB4FF4D`; backend suffix `83184f05`; process generation `1`; PID `15924`.
- Requested and live-confirmed model: `gpt-5.6-terra`; agent `general-purpose`; effort `low`; permissions `Always approve`; Browser and Computer Use MCP servers enabled.
- Startup receipt: both `grokbuild-browser` and `grokbuild-computer-use` visibly moved `Connecting → Ready` before the settled result.
- Exact UI tool activity: `grokbuild-browser__browser_open_url`, `grokbuild-browser__browser_snapshot`, `grokbuild-computer-use__computer_list_apps`, and `grokbuild-computer-use__computer_snapshot`; all eight activity items completed successfully, including the two skill/tool-discovery steps.
- Acceptance marker: `GB_WINDOW1_TERRA_OK`.
- Classification: **pass**; this is post-slice installed-app proof of MCP readiness plus exact Browser/Computer Use execution.
- Unified-log usage for this backend: 4 inference calls; prompt `61,703`; cached prompt `50,340`; completion `424`; reasoning `70`; conservative tracked total `62,197`.

### Session 2 — DeepSeek web history and in-place Grok boundary

- Fresh disposable tab/backend: full backend session ID `019fc14a-58f2-7c51-a734-6fc4318087e7`; UI receipt tab suffix `8657769D`; backend suffix `318087e7`; process generation `1`; PID `16115`.
- Initial requested/live-confirmed model: `deepseek/deepseek-v4-flash-0731`; agent `general-purpose`; effort `low`; permissions `Always approve`; Browser and Computer Use MCP servers enabled and settled `Ready`.
- Turn 1 exact route evidence: unified log records one successful built-in `web_search` call; no Browser or Computer Use tool was used. Acceptance marker: `GB_WINDOW2_DEEPSEEK_WEB_OK`.
- Boundary action: the app switched the live process to `Grok 4.5`, confirmed by the UI and unified-log `model changed` / `backend_search: model switch` receipts. The process receipt's requested-model line remained the original DeepSeek value, so that stale display field is recorded as a UI coherence risk rather than silently treated as new-session proof.
- Turn 2 exact route evidence: no tool requested; live Grok 4.5 returned `GB_WINDOW2_GROK_AFTER_DEEPSEEK_OK`.
- Classification: **pass with receipt-coherence caveat**; the known invalid replay was not reproduced, and the current evidence still does not justify a code change to provider-history semantics.
- Unified-log usage for this backend: 3 inference calls; prompt `43,599`; cached prompt `18,496`; completion `154`; reasoning `79`; conservative tracked total `43,832`.

### New authorization-window ledger

- Exactly two fresh provider sessions were used; no third session was created or billed in this window.
- New-window conservative tracked usage (`prompt + completion + reasoning`): **`106,029 / 1,000,000` provider tokens**; remaining **`893,971`**.
- Cached prompt tokens observed but excluded from the conservative tracked total: `68,836`.
- Combined inference calls: `7` across the two backends. No Kimi model or Kimi fallback appears in either session's model-change records; the Kimi option was left untouched.
- Historical Phase 0 usage remains separately recorded as `180,320 / 200,000`; it is not merged into this new authorization window.
- No source files, build artifacts, settings, credentials, sessions, or remote state were changed by the acceptance probes. Publication remains disabled.
