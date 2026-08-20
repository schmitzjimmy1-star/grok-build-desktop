---
name: grokbuild-computer-use
description: Guides GrokBuild desktop automation through Computer Use MCP tools. Use when the user asks to inspect or control native macOS apps, menus, dialogs, forms, Safari, Finder, or system UI through agent-desktop.
---

# GrokBuild Computer Use

## Available Tools

The complete surface (nothing else exists):

- `computer_snapshot` — accessibility-tree snapshot with refs (`@e3`); supports `app`, `surface`, `skeleton`, `root`, `include_bounds`, `max_depth`.
- `computer_click` — click a snapshot ref.
- `computer_type` — type text into a snapshot ref.
- `computer_press` — press a key or shortcut (`cmd+s`, `escape`, `return`). Also the way to scroll (arrow/page keys); there is no scroll tool.
- `computer_close_app` — close one exact app gracefully; `force: true` is an explicit termination path that may discard unsaved work.
- `computer_get` — read a property (for example `value`) from a ref.
- `computer_wait` — wait for time, element state, text, window, or menu.
- `computer_screenshot` — capture the screen (only when enabled in GrokBuild settings; needs Screen Recording).
- `computer_list_apps` — list running GUI applications.
- `computer_list_windows` — list visible windows, optionally per app.
- `computer_permissions` — report agent-desktop's macOS permission state.

## Default Choice

Use Computer Use for native desktop UI, system dialogs, app menus, Finder, Safari, and workflows that are not reachable through Browser Control.

If both Browser Control and Computer Use are available:

- Prefer `browser_*` tools for websites in a Chromium browser.
- Prefer `computer_*` tools for macOS apps, Safari, system UI, and cross-app workflows.

## Safe Workflow

When the user asks to use the computer:

1. Start with `computer_snapshot`.
2. Use refs from the snapshot for `computer_click`, `computer_type`, `computer_get`, and `computer_wait`.
3. Use `computer_screenshot` only when visual evidence is needed or the accessibility tree is insufficient.
4. If the UI is dense, request a skeleton snapshot, then drill down with the root ref.
5. If a ref is stale or ambiguous, re-run `computer_snapshot` and retry with the new ref.
6. When several windows exist, use `computer_list_windows`; target the visible positive-size main window, not hidden menu/helper windows. App snapshots automatically anchor to that best window when possible.
7. Close apps with `computer_close_app`, then verify the app is absent with `computer_list_apps`. Use `force: true` only when the user explicitly authorizes termination and accepts possible unsaved-work loss.

Do not guess coordinates when a snapshot ref is available.

## Campaign acceptance

Drive `/Applications/GrokBuild.app` only. Do not also Shell `agent-desktop` or grok's in-session `grokbuild-computer-use` against the same GrokBuild window.

- Settings tabs: `grok-settings-tab-app`, `grok-settings-tab-computerUse`, and `grok-settings-tab-<rawValue>` for the rest.
- Installed identity: `grok-app-build-identity` (Settings → App).
- Upgrade indicator: `grok-upgrade-indicator` in the workspace rail. Never click it during acceptance; that opens the CLI/app update panel. If dismissal is necessary, use its **Dismiss until next launch** context-menu action.
- Keep official grok CLI at the campaign pin. Do not click **Update grok CLI**.

Packaging looks for `agent-desktop` at `~/.grokbuild/computer-use/agent-desktop` when Homebrew is missing. `AGENT_DESKTOP_PATH` still wins when set.

## Permissions

Computer Use depends on macOS permissions:

- Accessibility is required for snapshots and app actions.
- Screen Recording is required for screenshots.

If tools report missing permissions, ask the user to open Settings -> Computer Use and grant the requested macOS permission.

## Safety

- Ask before destructive UI actions, account changes, payment actions, or sending messages externally.
- Do not automate passwords, MFA prompts, passkeys, or consent dialogs without explicit user instruction.
- Prefer step-by-step actions over long autonomous loops.
- Never emulate app close with a forced arbitrary shortcut. Use `computer_close_app` so the target app and force choice are explicit.
- If an action is blocked by policy, explain the local setting that blocked it.

## Useful First Tests

```text
List open apps using Computer Use and tell me which app is focused.
```

```text
Take a Computer Use snapshot of Finder and summarize the visible controls.
```
