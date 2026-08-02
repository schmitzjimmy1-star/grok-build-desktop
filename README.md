# GrokBuild Desktop App

> [!IMPORTANT]
> This checkout is Jimmy's maintained personal GrokBuild line:
> `schmitzjimmy1-star/grok-build-desktop`, branch `codex/warm-glass-ui`, installed
> as `/Applications/GrokBuild.app`. The older `jimmmy-Jim/Grok-Build-GUI`
> project is retired and must not be built or installed. See
> [`CANONICAL_WORKTREE.md`](CANONICAL_WORKTREE.md) before making changes.

GrokBuild Desktop App is a native SwiftUI macOS workbench for the [`grok`](https://grok.com) CLI. It is built for project work: persistent workspaces, resumable build sessions, git branches and worktrees, agents, tools, workflows, tasks, memory, skills, plugins, and reviewable output.

You can also install GrokBuild just to manage custom OpenAI-compatible models in **Settings → Models** (Keychain-backed provider credentials plus a CLI-compatible `~/.grok/config.toml`; no project or session needed), then use them in the grok TUI.

![GrokBuild Desktop App showing the project sidebar, session UI, and composer](docs/images/grokbuild-app.png)

## Requirements

- macOS 26 (Tahoe) or later
- The `grok` CLI installed, usually at `~/.grok/bin/grok`
- A logged-in CLI session — run `grok login` in Terminal before starting your first session (not needed if you only manage custom models)

## Quick Start

### Start with a project

1. Install and sign in to the `grok` CLI (`grok login`).
2. Use the signed personal build at `/Applications/GrokBuild.app`, or build it from this canonical checkout. Upstream releases do not contain the personal repair line.
3. Open GrokBuild Desktop App and choose **Add Project**.
4. Pick a folder. It can be a code repo, a docs folder, or a scratch workspace.
5. Start a session. GrokBuild Desktop App launches `grok agent stdio` for that project and streams it in the app.

### Custom models only

If you mainly use the grok TUI or CLI and just need a UI for providers and models:

1. Install the `grok` CLI and open GrokBuild Desktop App (no project or `grok login` required for this path).
2. Open **Settings → Models**.
3. Install a provider, use its declared connection method, run **Test connection**, then add one or more returned OpenAI-compatible models. OpenRouter supports S256 browser OAuth or a pasted API key; local Ollama needs no credential; the other official presets use API keys.
4. Provider secrets are stored in macOS Keychain with device-only accessibility. GrokBuild projects only the CLI-required model copy into owner-only (`0600`) `~/.grok/config.toml`, so `/model <id>` still works in the grok CLI/TUI and in GrokBuild sessions.

GrokBuild does not load provider credentials from a project `.env` file. A custom or local endpoint may use an unverified model ID only through the explicit advanced path.

**Test connection** proves the key, endpoint, catalog response, and configured-model visibility. The Grok CLI still owns actual chat/tool routing, so a catalog can pass while a particular CLI completion endpoint or tool combination is unsupported; that failure is reported separately instead of being mislabeled as bad authentication.

## What GrokBuild Desktop App Is

GrokBuild Desktop App owns the macOS workbench: project navigation, durable session tabs, branch/worktree controls, build-oriented composer, diff review, settings, browser/computer-use enablement, and the local app update flow. The transcript is the record of work performed by an agent inside a project; GrokBuild is not designed or evaluated as a general-purpose chatbot. A common lightweight use is **Settings → Models** alone: manage custom providers and models for the shared `~/.grok/config.toml` without opening a project or starting a session.

It is **not** a replacement for the CLI. The `grok` CLI still owns agent reasoning, ACP, MCP tools, models, skills, subagents, plan mode, permissions, memory, hooks, plugins, and `AGENTS.md` instructions.

## Install

Jimmy's maintained app is built from this checkout and installed at
`/Applications/GrokBuild.app`. Its About panel and Settings → App show the
personal repository, branch, exact source commit, and dirty-state receipt; do
not accept `0.1.20` alone as proof of source identity. The preserved
[`rimusz/grok-build-desktop`](https://github.com/rimusz/grok-build-desktop)
remote is upstream reference, not the owner of the installed personal repair
line.

Release assets are versioned, e.g. `GrokBuild-v0.1.10.app.zip` and `GrokBuild-v0.1.10-macOS.dmg`.

## Feature Highlights

### Sessions

- Streaming agent sessions for `grok agent stdio` with Markdown, compact thinking disclosures placed above their assistant answers, live tool cards, permission prompts, plan/question cards, and diff review.
- Multi-tab sessions with lazy restore, resumable grok sessions, a session browser, and provenance-safe transcript recovery from grok's on-disk `chat_history.jsonl` when possible. Imported worker output remains visible but never proves root-conversation identity.
- Each local tab transcript is stored as an owner-only, atomic file under Application Support with a small metadata sidecar. Saved v1 preference blobs are copied and verified before use, then retained as rollback input for this release; tab switches update layout metadata without rewriting every transcript.
- Restore metadata is loaded off-main and only the selected tab hydrates its message body; rich Markdown parsing and visible Mermaid/display-LaTeX sizing are bounded by a process-local cache with explicit WebKit teardown. Readers can detach from streaming output without losing their place, then use the accessible **Jump to latest** action when ready.
- Session restore uses the last tab you intentionally activated—not the tab with the longest transcript. Empty or divergent saved selections cannot outrank a viable recent transcript.
- Model and session-agent choices preserve intent: inherited tabs keep following their project/global default, while a picker choice remains an explicit per-tab override. Legacy saved models remain conservatively classified until the next explicit choice.
- The v3 session layout is committed with a separate integrity marker while the v2 layout remains untouched as rollback input. A failed/mismatched migration opens the legacy layout read-only instead of pretending the workspace is empty.
- Saved Grok backends are checked against the exact local transcript before they start. Exact/prefix matches resume normally; missing, incomplete, divergent, or composite histories keep local work readable, show a redacted continuity explanation, preserve the draft, and block Send instead of risking the wrong conversation. Recovery is explicit: **Relink** opens a bounded, redacted candidate review and re-verifies the selected history, while **Continue as New** durably records the predecessor and waits until the next real submission to create a backend. One matching prompt never auto-binds a tab. Local-only work creates a fresh backend lazily on first send, and fallback/fork relationships are retained in the authenticated v3 ledger.
- Adaptive neutral visual system with a compact native SF type scale, centered reading column, flat matte surfaces, restrained corner radii, no decorative avatars or status pills, and real System/Light/Dark appearance support. Contrast, reduced transparency, reduced motion, and large text keep the same task hierarchy across modes.
- Compact composer controls for model, mode, context usage, voice dictation, attachments, and one **Skills and workflows** menu for skill, research, workflow, and imagine commands. The adjacent workbench status row is visible by default and exposes project, branch/worktree, a redacted process/model receipt, session agent, Browser Tools, Computer Use, Workflows, Tasks, and Memory.
- Build-oriented empty state with four quick starts: map architecture, implement a scoped change, review the working tree, or diagnose build/test failures.

### Project Workflow

- Collapsible project sidebar with pinned projects, recent sessions, session rename/close, one-click **New Project** onboarding, and an on-demand project filter. The chat toolbar keeps a sidebar toggle visible in the full-width canvas, moves secondary actions into one menu, and opens Settings directly.
- Full-width Settings workspace with one compact internal navigation rail and a centered 760 pt content column; opening Settings never brings the project sidebar back or stacks two sidebars together. Switches use one small trailing control column, permission editors stay shallow and neutral, and Marketplace sources stack above the full-width plugin list instead of squeezing it into a split view. Technical monospace typography is reserved for actual commands and diagnostic logs.
- Settings mounts only the selected pane, so hidden diagnostics and loaders stop instead of quietly chewing resources. All fourteen panes now use the shared state contract: editable values survive pane changes as parent-owned drafts, inventories preserve a last successful result as stale on refresh failure, and row-local work stops with the hidden pane when safe. An edit is never persisted until **Apply** or an explicit row action, every action states its persistence/restart/trust scope, and receipts distinguish Draft, Saved, Restart required, Live, Unknown, success, partial, and failure without leaking credentials. Future-only defaults say so; launch-affecting changes restart only the current live tab. Narrow windows and accessibility text stack form rows instead of crushing labels.
- Workbench focus order follows the task path from controls to transcript to composer, and Settings focuses the selected pane after sidebar navigation. Rich code exposes language and Copy, tables expose a linear row description, and Mermaid/LaTeX expose selectable source when a rich preview cannot render. VoiceOver receives terminal action results and continuity/model warnings without a streamed-token announcement storm.
- Per-tab **model** selection and per-project **reasoning effort** through one compact native menu with the models directly visible and an Effort submenu. Model labels distinguish Saved, Pending, Requested, Live, Rejected, and Unknown; an accepted ACP request without an effective-model readback never masquerades as live confirmation. Fresh chats seed this list from the installed `grok` CLI and fall back to Grok 4.5 while ACP connects.
- Git branch/worktree management from the session status row.
- `Open in` menu for Finder, Cursor, VS Code, Terminal, iTerm, and Zed.
- **Grok and provider sign-in** — **Settings → Models** shows coarse local Grok sign-in state and can launch the resolved CLI's xAI browser flow (`grok login --oauth`) without storing its session. OpenRouter supports exact-loopback S256 OAuth or paste-key setup; every other preset declares API-key or keyless connection explicitly.
- **Custom models (standalone)** — OpenAI-compatible providers and models in **Settings → Models** with device-only Keychain-backed provider secrets, typed catalog validation, redacted diagnostics, native Chat Completions / Responses / Anthropic Messages routing, and atomic owner-only writes to `~/.grok/config.toml`. GrokBuild-only UI hints and credential provenance live in a non-secret sidecar, so the CLI config contains only fields Grok understands. OpenAI preset models default to the Responses API. Usable on its own (no project/session); models are then available in the grok CLI/TUI and in GrokBuild sessions.

### Agent Capabilities

- **Main agents** — browse agents discovered by `grok inspect --json`, choose a drafted default for future sessions, or override the active tab from Session controls. Applying the default never rewrites an existing tab override or claims that a running tab changed agent.
- **Custom subagents (roles)** — create reusable roles with a name, optional model, and instruction. GrokBuild Desktop App writes them to `[subagents.roles.*]` in `~/.grok/config.toml` and stores instructions in `~/.grok/prompts/<name>.md`.
- **Using subagents** — keep the main agent as Default and prompt normally; grok delegates to matching subagents automatically, or you can ask for one by name (for example, *"use the researcher subagent to map the auth flow"*). **Run as custom role** in the agent picker runs the whole session as that role instead of spawning a child subagent. To block spawning child subagents, use **Settings → Permissions**.
- Inspect hooks, plugins, marketplace sources, compatibility layers, skills, and MCP servers from Settings with retained checking/empty/stale/error states. Plugin and marketplace mutations require explicit trust and show row-local receipts. MCP setup uses structured stdio/http/sse fields, preserves ordered argument boundaries, supports user/project scope, and redacts stored environment/header values; the installed CLI stores those values literally, so adding a secret requires a disclosure acknowledgment. Compatibility follows the current `externalCompat.cells` schema (including Codex sessions-only support) instead of treating malformed inspection output as an empty success.

### Optional Automation

Enable Browser and Computer Use from **Settings → Browser** / **Settings → Computer Use**, then **Apply and Restart**, or use the matching items in Session controls when a session is active.

- **Browser control** — let Grok drive a real Chromium browser via `browser_*` MCP tools backed by [`agent-browser`](https://agent-browser.dev). Use a managed automation profile or attach to Chrome, Brave, Edge, Arc, or another Chromium browser over CDP.
- **Computer Use** — let Grok drive native macOS UI via `computer_*` MCP tools backed by [`agent-desktop`](https://github.com/lahfir/agent-desktop) (bundled into the app at packaging time), with an allow/block action policy, screenshot gating, command timeouts, deterministic main-window targeting, a dedicated graceful/explicit-force `computer_close_app` contract, and optional Cursor MCP integration. Editing a screenshot draft never asks macOS for Screen Recording; that prompt is gated behind the explicit **Request Screen Recording** action after the setting is applied.
- **Memory** — experimental and off by default. Enable it from Settings, browse saved memories, and add "Remember" notes from Session controls.
- Applying a launch-affecting Memory change restarts only the exact current live tab; a streaming turn queues and coalesces the restart. Success requires a matching newer process receipt, while a reconnect fork is disclosed as partial instead of false green. Tabs with no live process simply use the saved value when they next start.
- **Background tasks** — scheduled `/loop` tasks plus background shells, monitors, and subagents mirrored under Session controls. Schedules only fire while GrokBuild Desktop App is open and that session process is alive (inactive tabs may be stopped by LRU eviction).
- **Rhai workflows** — enable in Settings → Workflows (`[workflows] enabled` in config.toml, shared with the grok TUI). Session controls list runs, saved `.grok/workflows/` scripts, and deep research. This is separate from the Skills and workflows menu in the composer.
- **Session tools** — fork session (new tab with `--fork-session`), share link (`/share` + clipboard), `/btw` aside panel, create-skill sheet, and multi-session dashboard grouped by status.
- **Documents and spreadsheets** — use grok's document skills (`xlsx`, `docx`, `pptx`) to create, read, edit, and reformat Office files from paths in your workspace. Spreadsheet skills may need [LibreOffice](https://www.libreoffice.org/) installed for some conversions.

### App Experience

- A normal windowed Mac app with standard application menus, native SF Symbols, and no redundant status-item applet. Settings → App owns System/Light/Dark appearance selection and applies it without restarting a session.
- Grouped vertical Settings navigation keeps all configuration areas readable without a fourteen-tab horizontal traffic jam.
- In-app update panels for both GrokBuild Desktop App and the `grok` CLI. App updates are offered only for signed and notarized releases.
- Adaptive SwiftUI design with accessibility labels for interactive status controls plus native link elements, spoken equation labels, and table header/cell summaries in rich results. Rich rendering is detached from the main actor and reuses parsed content where message identity, content, width, appearance, and render version still match.

## Permissions & Privacy

- GrokBuild Desktop App talks to the local `grok` CLI; your prompts, tool calls, model routing, auth, and CLI-side storage follow the CLI's behavior.
- Browser control uses a separate managed Chromium profile by default. If you attach to an existing browser over CDP, Grok can interact with that browser window.
- Computer Use requires macOS Accessibility permission. Screenshots require Screen Recording and are optional.
- **Settings → Permissions** separates interactive **Ask**, **Auto**, and **Always approve** behavior from advanced automation modes. **Deny unapproved (CI)** is explicitly described as deny-by-default headless behavior, not as a low-interruption interactive mode. Permission cards describe the launched process receipt, not an unapplied Settings draft; an unexpected ACP request under Always approve is safely answered without blocking, while explicit deny rules, hooks, and sandbox limits still apply.
- Permission rules and launch policy remain in a local draft until Apply. Applying them restarts only the current live tab, and its old live receipt remains visible until a matching newer process receipt proves the replacement.

## Building from source

### Minimal setup

You only need **Xcode Command Line Tools**:

```bash
xcode-select --install
```

That is enough to compile the app, create the `.app` bundle and DMG, and codesign/notarize.

```bash
make build          # build the release binary
make test           # run unit tests
make run            # build release + launch from .build/GrokBuild.app
make run-debug      # build debug + launch — includes menu **Simulate Updates**
make app            # create dist/GrokBuild.app
make dmg            # create the .app + DMG
```

See [BUILDING.md](BUILDING.md) for packaging, signing, notarization, and GitHub releases.

### Opening a self-built (unsigned) app

Local builds from `make app` / `make run` are unsigned. macOS Gatekeeper may block them the first time you open a copied `.app` (for example after moving `dist/GrokBuild.app` to `/Applications`):

1. **Right-click** `GrokBuild.app` → **Open**, then confirm **Open** (bypasses the block once).
2. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the blocked-app message.
3. Or remove the quarantine attribute:
   ```bash
   xattr -cr /path/to/GrokBuild.app
   ```

Self-built apps do not receive in-app upgrade offers. Use a notarized GitHub release for one-click updates, or keep rebuilding from source.

### Recommended for SwiftUI work

If you plan to edit the SwiftUI code, install the **full Xcode** IDE from the App Store for:

- SwiftUI Previews (live canvas) — the biggest advantage
- Better debugging tools (view hierarchy, environment inspection)
- A smoother experience with complex SwiftUI views

You can still build from the terminal with `make` or `swift build` with full Xcode installed:

```bash
xed .          # open Package.swift in Xcode
```

### Signing & notarization

```bash
cp .env.example .env   # optional: SIGN_IDENTITY, NOTARY_PROFILE
make signed SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
make notarize NOTARY_PROFILE=AC_PASSWORD
make release RELEASE_TYPE=notarized
```

Signing requires a **Developer ID Application** certificate, and notarization requires App Store Connect access. Full details: [BUILDING.md](BUILDING.md).

### Developer documentation

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | **Start here** — app structure, data flow, persistence, updates, common tasks → files |
| [AGENTS.md](AGENTS.md) | Agent/copilot entry point |
| [BUILDING.md](BUILDING.md) | Build, sign, notarize, release CI |
| [docs/OAUTH_OPENROUTER_ACP_PLAN.md](docs/OAUTH_OPENROUTER_ACP_PLAN.md) | Follow-on plan for endpoint hardening, OAuth/OpenRouter, optional ACP backends, cache audit, and Dock persistence |

Debug builds (`make run-debug`) include **GrokBuild → Simulate Updates** for testing the update UI without publishing releases. It is compiled out of release builds (`make run`, `make app`, GitHub releases).

## License

[Apache License 2.0](LICENSE). GrokBuild Desktop App is an independent desktop client for the Grok Build CLI and is not affiliated with, endorsed by, or sponsored by xAI.
