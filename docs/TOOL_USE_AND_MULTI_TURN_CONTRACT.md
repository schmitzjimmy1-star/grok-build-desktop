---
title: GrokBuild tool use and multi-turn operating contract
status: installed-app verified
verified: 2026-08-02
---

# GrokBuild tool use and multi-turn operating contract

Use this contract when a GrokBuild task needs terminal tools, built-in web
search, interactive browser control, native macOS Computer Use, or several
dependent turns. It describes the installed `0.1.20` personal build running
Grok CLI `0.2.118`; do not infer future capability from this dated receipt.

## Core operating rules

1. **Verify the live route before work.** The generation-bound session receipt,
   not the saved picker label, must name the requested model. Stop if the live
   model is missing or wrong.
2. **Keep one provider/model for the life of a tool-rich session.** Provider
   tool-call and tool-result encodings are not universally portable. After a
   web or tool turn, start a new session before changing provider or model.
3. **Discover MCP tools before the first call.** Browser and Computer Use
   servers are injected during ACP `session/new`/`session/load` and may still be
   connecting when a very fast model begins its first turn.
4. **Treat `server is still connecting` as readiness, not incapability.** Wait a
   few seconds and retry the exact tool in the same session. Do not invent a
   substitute tool, claim the named tool does not exist, or ask the user for a
   confirmation that the read-only request did not require.
5. **One action, observe, then decide.** Read tool output or refresh the current
   snapshot before choosing the next action. Never reuse stale browser or
   accessibility refs.
6. **Keep a short turn checkpoint.** After each material turn retain the goal,
   evidence obtained, state changed, and next action. Do not rely on hidden
   reasoning as durable state.
7. **Use the narrowest surface.** Terminal is for shell/files; built-in web
   search is for current public information; Browser Control is for page
   interaction; Computer Use is for native macOS UI.
8. **Respect the active permission receipt.** GrokBuild exposes the launch-time
   permission mode, sandbox, browser enablement, Computer Use enablement, and
   MCP server names. A mutable Settings label is not proof that the current
   process received them.

## Capability routing

| Need | Preferred surface | Required sequence |
|---|---|---|
| Read or change local files; run builds/tests | Terminal | Run the smallest explicit command, inspect exit/output, then continue |
| Current public facts or source discovery | Built-in web search/fetch | Search, inspect the returned sources, then answer with source-aware evidence |
| Navigate or interact with a website | Browser MCP | `browser_open_url` → `browser_wait_for_load` when needed → `browser_snapshot` → ref action → fresh snapshot |
| Inspect or control a native Mac app | Computer Use MCP | `computer_snapshot` → ref-based action → fresh snapshot or `computer_get` verification |
| Work spanning several dependent steps | Same model and session | End each turn with an explicit checkpoint; send the next request only after the prior turn completes |
| Change model/provider after any web/tool work | New session | Start clean, select the new model, verify the live receipt, then continue from a plain-text checkpoint |

Built-in web search and Browser Control are different capabilities. Web search
returns sources to the agent. Browser Control owns an automation browser and
can navigate, inspect, click, type, evaluate page JavaScript, and capture page
screenshots. Do not ask for “browser” when search is sufficient, and do not call
search when the task requires interaction with page state.

## Browser Control contract

Installed readiness at verification time:

- Browser Tools enabled.
- `agent-browser 0.33.0` detected at `/opt/homebrew/bin/agent-browser`.
- Managed runtime installed; the applied route used an isolated external Chrome
  automation profile over loopback CDP.
- Live browser: Chrome 151 at `http://127.0.0.1:9222`.

Available browser tools:

- `browser_open_url`
- `browser_snapshot`
- `browser_click_ref`
- `browser_type_ref`
- `browser_screenshot`
- `browser_eval_js`
- `browser_wait_for_load`

Browser workflow:

1. Open one exact URL.
2. Wait for navigation or dynamic loading when required.
3. Snapshot the current page and use only refs from that snapshot.
4. Click or type by ref.
5. Re-snapshot after every navigation or material DOM change.
6. Use screenshots for visual evidence and JavaScript only when snapshot/ref
   operations cannot answer the question.
7. Do not automate login, MFA, payment, consent, destructive account actions,
   or private-data transmission without the required user authorization.

The maintained browser bridge is `scripts/grokbuild-browser-mcp`. The upstream
runtime is [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser).

## Computer Use contract

Installed readiness at verification time:

- Computer Use enabled and local action policy set to Allow.
- Bundled `agent-desktop 0.6.0` ready.
- Accessibility and Screen Recording granted.
- Screenshots enabled.
- The app's end-to-end helper diagnostic successfully initialized and called
  `computer_list_apps` through the same MCP path used by Grok.

Available Computer Use tools:

- `computer_snapshot`
- `computer_screenshot`
- `computer_click`
- `computer_type`
- `computer_press`
- `computer_close_app`
- `computer_get`
- `computer_wait`
- `computer_list_apps`
- `computer_list_windows`
- `computer_permissions`

Computer Use workflow:

1. List apps/windows when the target is ambiguous.
2. Snapshot the exact app or surface.
3. Use refs from that snapshot for clicks, typing, reads, and waits.
4. Re-snapshot when a dialog, menu, window, or application state changes.
5. Prefer graceful `computer_close_app`; use force only with explicit authority
   that accepts possible unsaved-work loss.
6. Screenshot only when visual evidence is necessary or Accessibility cannot
   represent the state.
7. Never guess coordinates when a valid accessibility ref exists.

## Multi-turn checkpoint format

Use this compact plain-text checkpoint between dependent turns and when moving
work into a new session:

```text
Goal: <one sentence>
Completed: <tools/actions that actually succeeded>
Evidence: <exact non-secret result or receipt>
State changed: <none, or a precise reversible change>
Next: <one bounded action>
Constraints: keep this model/provider; refresh refs; do not repeat completed work
```

Tool calls and results may remain in the same session only while the provider
stays fixed. To change providers, copy only this plain-text checkpoint into a
new session. Do not copy raw provider tool-call JSON.

## MCP startup readiness gate

Before the first Browser or Computer Use action in a newly launched session:

1. Verify the session receipt shows Browser and/or Computer Use enabled and the
   expected MCP server name.
2. Discover the exact tool name.
3. Call one read-only readiness probe:
   - Browser: open `https://example.com`, then snapshot it.
   - Computer Use: call `computer_list_apps` or `computer_permissions`.
4. If the tool reports that its server is still connecting, wait briefly and
   retry the exact call in the same session.
5. Continue only after the tool receipt says Done. A discovered name, spinner,
   or Settings toggle is not a successful call.

This gate matters most for fast routes. Gemini 2.5 Flash and GPT-4.1 Mini both
reached their first Computer Use request before the MCP server was ready during
acceptance. The same-session retry succeeded for both.

## Installed model capability matrix

Every row below used a fresh installed-app session and a backend-confirmed live
model. Tests were read-only: terminal `pwd`, browser open/snapshot of
`https://example.com`, and Computer Use app listing/snapshot. No credential or
response body is retained here.

| Model route | Terminal | Browser MCP | Computer Use MCP | Multi-turn | Result |
|---|---:|---:|---:|---:|---|
| Grok 4.5 (`grok-4.5-build`) | Pass | Pass | Pass | Pass | Four turns completed: terminal, browser, Computer Use, then exact no-tool recall |
| OpenAI `gpt-5.6-terra` | Pass | Pass | Pass | Not separately isolated | One compound cross-tool turn passed; a separate built-in web-search turn also passed |
| Kimi `kimi-k3` | Pass | Pass | Pass | Not separately isolated | Compound cross-tool turn passed; slower completion, about 38 seconds of model thinking |
| OpenRouter DeepSeek V4 Flash | Pass | Pass | Pass | Not separately isolated | Compound cross-tool turn passed |
| OpenRouter Gemini 2.5 Flash | Pass | Pass | Pass after retry | Pass after retry | First compound turn stalled after discovering Computer Use; isolated first call reported server connecting; same-session retry passed |
| OpenRouter GPT-4.1 Mini | Pass | Pass after retry | Pass after retry | Pass after retry | First turn ran terminal while MCPs connected and misdescribed the tool table; explicit same-session retry passed all named MCP calls |

The Gemini and GPT-4.1 Mini results are **capable with a readiness caveat**, not
clean first-turn passes. Prompts should name the required surface and exact MCP
tools after readiness rather than accepting a guessed substitute.

## Verified acceptance receipts

| Session | Route / purpose | Billable total tokens | Model calls |
|---|---|---:|---:|
| `019fc106-923d-75d0-81aa-900044f2a562` | Grok four-turn terminal/browser/Computer Use/recall | 214,131 | 11 |
| `019fc109-4243-7592-927f-cd0e1e116b54` | Terra compound tool probe | 62,569 | 5 |
| `019fc10a-26fa-7191-ba45-c8f5327ce2f1` | Kimi compound tool probe | 59,657 | 4 |
| `019fc10b-7bad-73e0-b7c2-8e5c31e5bf1b` | DeepSeek compound tool probe | 63,375 | 4 |
| `019fc10c-48b5-7010-aca9-73d60c7b0b61` | Gemini compound partial/stall | 55,921 | 5 |
| `019fc10e-2e78-7ab2-85c5-918e59d27369` | Gemini isolated failure + retry pass | 45,938 | 4 |
| `019fc10f-5f07-7582-8ca5-fe880b1b8a64` | GPT-4.1 Mini first-turn partial + retry pass | 58,944 | 5 |
| `019fc110-f3a6-76e1-957b-c783f4e0177a` | Terra built-in web-search probe only | 22,855 | 2 |

Authorized capability probes used **583,390 total tokens**. A stale Computer Use
element index then accidentally triggered a separate `/review` turn in the
web-search session (671,290 tokens, 23 model calls). The review reported only
temporary findings artifacts; no source edit was requested. Its usage is
excluded from the capability total above but remains disclosed here as test
overhead.

## Known boundaries

- A provider switch after provider-specific web/tool history can fail with
  `Invalid params` before usage or a final answer. Start a new session.
- MCP injection at session creation does not currently block the composer until
  every server is ready. Use the readiness gate above.
- Provider catalogs and Settings toggles prove configuration, not successful
  tool execution.
- Tool discovery can return partial results while a server connects. Retry
  discovery or call the known exact tool after readiness.
- Browser refs and Computer Use refs are scoped to snapshots and become stale.
- Computer Use availability does not waive macOS permissions, Grok permission
  policy, sandbox rules, hooks, or user-confirmation requirements.
- A browser runtime is an isolated automation surface unless the user explicitly
  selects and authorizes a logged-in profile.

## Minimal reusable prompt

```text
Work in this session with the current backend-confirmed model. Use terminal for
local commands, built-in web search for current public facts, Browser MCP for
web-page interaction, and Computer Use MCP for native macOS UI. Before the first
Browser or Computer Use call, discover the exact tool and verify the MCP server
is ready; if it is still connecting, wait and retry the same call. Observe each
result before the next action, refresh snapshot refs after state changes, and
leave a short Goal/Completed/Evidence/State changed/Next checkpoint after each
material turn. Do not switch model or provider after web/tool history; start a
new session and carry over only the plain-text checkpoint. Never expose secrets
or perform destructive, authentication, payment, consent, or external-send
actions without the required user authorization.
```
