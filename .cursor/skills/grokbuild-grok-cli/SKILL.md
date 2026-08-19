---
name: grokbuild-grok-cli
description: Works with grok CLI integration in GrokBuild — auth state, version checks, session resume, permission settings, MCP and extension management, and bundled browser skill. Use when changing GrokProcess, GrokCLIService, UpdateChecker, or grok-related settings UI.
---

# Grok CLI in GrokBuild

## Boundaries

GrokBuild is a UI shell. Core agent behavior (ACP, MCP, skills, plan mode, subagents) stays in the `grok` CLI.

`grok sessions delete <id>` removes indexed parent sessions only. Spawned
`session_kind=subagent` child directories stay unindexed (`No session found`
while the directory remains). That is a CLI residual. Do not add a GrokBuild
scraper. Gate F may move only proven leftover child dirs to a dated Trash
bundle after the CLI reports missing.

## Installed CLI (live, 1.0.4)

Re-derived 2026-08-15 (Phase 4) from process-zero, without printing secrets:

- `grok --version` → `grok 1.0.4 (d846eb93d94d) [stable]`
- `grok models` default selector is `grok-4.6` (not `grok-4.6-build`; usage already maps the `-build` alias)
- OpenRouter catalog ids use hyphens (`openai-gpt-4.1-mini`); harness preflight also accepts slash form
- `grok inspect --json` reports agents `general-purpose`, `explore`, `plan`; no `modes` key; `externalCompat.cells` count 13
- Auth still prints `You are logged in with grok.com.`

Do not rewrite historical 0.2.x receipts in this skill.

## Key APIs

```swift
// One-shot commands
try await GrokCLIService().run(["--version"])
await GrokCLIService.versionDisplayLine()

// Long-running agent
GrokProcess — grok agent … stdio, ACP events

// Updates
UpdateChecker.checkAppRelease()   // unused on this personal line; install with make ship
UpdateChecker.checkGrokCLI()      // grok update --check --json
```

Ordinary unarmed `GrokProcess.start` still locates the official CLI.
An armed v3 `HardBudgetLaunchContract` materializes one Keychain item through
`GrokArmedCredentialMaterializer` and `posix_spawn`s the leased candidate with
FD 198/197. Debug tests inject the Keychain client. The owner-local T5 E2E
(`GROKBUILD_SLICE4B3_RUNTIME_SELECTION`) leases the signed digest-staged pager
and drives that same production start path; it skips in CI and never reads live
Keychain. `AcceptanceBudgetGuard` schema-3 packets parse `credentialAuthorizationV3`
selectors; `ArmedV3DispatchExpectation` cross-binds them to the live custom
model and linked provider before `HardBudgetLaunchContract`. Spawn rechecks
that latch before `posix_spawn`. Armed `initialize` requires a matching nested
`v3Authority` before `.ready`. Schema-3 packets require 20M/19M/1M and cannot
ride the live v1/v2 4M governor; schema-2 stays 4M/3M/1M. Schema-2 packets
still supply `nil`. Ordinary
Send without an acceptance harness does not read Keychain. Native Grok routes
fail that bind (and still fail preflight if a contract is constructed directly).
4B.4 acceptance `session/load` cannot fall back to `session/new`; ordinary
unarmed Resume still can. During acceptance, `resumeTaskSession` refuses so
**Resume current task** cannot start an unallocated process. T2/T3 select the
retained tab through `governed_fresh_process_load`, then packet Send
prelaunches the allocated process with `resumeSessionID` (`session/load`).
Legacy continuation (`resumeAfterQuit`, `resume_saved_task`) is rejected at
schema. Schema-3 continuation dry-run and `_billable_v3` exist in
`scripts/acceptance/run.py` and still refuse `--billable` at the absolute
ceiling; paid 4C stays locked.

4B.5 owner-local lifecycle uses a signed digest-staged pager
(`1.0.5 (8226242)`, binary SHA-256
`f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b`) selected
through `GROKBUILD_SLICE4B3_RUNTIME_SELECTION`. It never replaces
`~/.grok/bin/grok`. Armed `session/prompt` waits at most 90s
(`GrokProcess.armedSessionPromptTimeout`). The pager source
`822624291de2b544605f439ad1349ae6bdc3cf10` detaches after-turn workspace work
and skips the 120s `live_ids` drain on zero-tool turns so ACP can return after
loopback `pong`. Tests: `Slice4B5LifecycleTests`, including
`hold_after_body` kill-after-response-before-settlement.

4B.6 copies that exact signed pager into
`~/Library/Application Support/GrokBuild/candidate-runtime/<sha256>/` (or a
temp dest in tests) via `scripts/acceptance/harness/candidate_install.py`.
Ordinary `GrokProcess.start` does not scan that directory. Armed launch still
requires `--grokbuild-acceptance-runtime-selection-file=` plus budget/manifest/ledger.
Rollback unlinks only the selection sidecar after two process-zero samples.
Owner-local lifecycle tests install a copy first, then rerun the 4B.5 matrix
against it. 4C paid Send stays locked behind `require_absolute_ceiling_support()`;
`_billable_v3` must not call `resume_saved_task()`.

## Auth & status bar

- `GrokProcess.needsAuthentication` drives login banner and menu header.
- Post `.grokStatusChanged` with `status` and `authenticated` keys.
- Menu: "GrokBuild connected to grok cli" when authenticated.

## Permission settings

Stored in `UserDefaults` via `GrokSettingsKeys` — `allowRules`, `denyRules`, `permissionMode`, `selectedAgent`, etc. Passed to `GrokLaunchOptions` in `ChatStore`.

The running process exposes a credential-free `GrokLaunchReceipt`. Cards and ACP request disposition use that receipt: Always approve/YOLO select a real allow option, Deny unapproved selects rejection, and Ask/Auto remain interactive when the CLI asks. Never write an approved edit from GrokBuild; reply to ACP and let the CLI enforce sandbox, hooks, and deny rules.

## Turn completion and transcript truth

`GrokProcess` yields `.turnCompleted` through the same event queue as text/tool updates and waits for ChatStore acknowledgment. `TurnSettlementCoordinator` joins that queue barrier with the prompt RPC result and rejects stale generations after Stop/restart. Before acknowledgment, ChatStore flushes streaming text and reconciles the exact captured backend history file using occurrence-aware role/turn/content identity. Recovery runs for partial as well as empty transcripts and must remain idempotent.

Configuration reloads resume `ChatStore.durableGrokSessionID`; do not derive continuity from transient `process.sessionId` alone. A legitimate stale-load fallback reconciles the prior exact backend file and persists an explicit old-ID → new-ID recovery fork before another prompt.

**Stop boundary:** User Stop tears down the current process but first captures its local tab/backend/process-generation identity. `ChatStore` publishes a local `userStopped` Activity receipt with the next action; it is not a backend completion and not a generic failure. Only an exact continuity receipt may re-verify and resume that backend. A stale, missing, or mismatched receipt forces the next launch into a fresh, ledgered run with explicit copy.

## Native interaction ownership

Question, permission, and plan controls are thin views over direct ACP requests. Identity is the exact backend session plus JSON-RPC request id; a tool-call row may explain the request but must never supply an id to `respondToQuestion`, `respondToPermission`, or `respondToExitPlan`. Replays of one identity update one card, while distinct authoritative ids remain distinct. A decision writes one ACP response and resumes the blocked turn—never send a second marker prompt such as `[Plan approved]`, and never rewrite Grok's durable logs to make the UI appear settled.

## Session agent (`--agent`) — per tab

- **Per session tab.** Each tab launches with `ChatStore.effectiveAgentSelection` → `GrokAgentProfiles.launchArgument(for:)` → `GrokLaunchOptions.agent` → `grok --agent`.
- **Resolution:** explicit per-tab override (`SavedSessionRecord.agent`, set via `ChatStore.setSessionAgent`) when present, else the global default `grokbuild.selectedAgent` (Settings → **Agents** = default for **new** sessions). Non-overridden tabs adopt the default on next launch; overridden tabs keep their choice. Only overridden tabs persist a value (`persistedAgentSelection`).
- **Values:** `""` = grok default (no flag); any other value = discovered agent name.
- **UI:** `ChatView.agentStatusPill` menu (built-ins from `GrokAgentProfiles.builtInOptions` + discovered via `ChatStore.loadDiscoveredAgentsIfNeeded`). Picking one calls `setSessionAgent` → **restarts that tab's grok** (agents change only at launch) and posts `.liveSessionAgentChanged` → `persistSessionLayout()`.
- Discover agents via `GrokCLIService.listAgents(cwd:)` (parses `agents` from `grok inspect --json`). Keep this thin — grok owns agents/personas.

## Custom subagents (roles)

grok owns subagent orchestration (main agent delegates to subagents in parallel; gated by `--no-subagents` / Settings → Permissions "Disable subagents"). GrokBuild adds a thin CRUD editor for **roles** in Settings → **Agents** → "Custom subagents".

- **Schema (installed grok, verified via `~/.grok/README.md`):** roles live in `~/.grok/config.toml` as `[subagents.roles.<name>]` with `description`, `model` (empty = inherit parent session model), and `prompt_file`. Personas (`[subagents.personas.*]`, tone-only, no model) and `[subagents.toggle]` / `[subagents.models]` are *not* managed by the app. The third-party `~/.grok/user-settings.json` `subAgents` array is a different CLI — **not** what xAI's grok uses.
- **Storage:** `SubagentRole` + `SubagentRoleStore` in `CustomModelSettings.swift` mirror `CustomModelStore` — minimal targeted TOML edits that preserve all other content and unmanaged role keys (for example `default_capability_mode`); each instruction is written to `~/.grok/prompts/<name>.md` and referenced via `prompt_file`. Relative `prompt_file` values resolve from the user's home directory. Removing a role deletes its GrokBuild-managed prompt file.
- **UI:** `SubagentRoleEditor` sheet (name/model/instruction/description). Model picker options come from `CustomModelStore.load()` + `grok-build`. Reserved names (`general`, `general-purpose`, `explore`, `plan`, `vision`, `verify`, `computer`) are rejected. Roles are a separate concept from the read-only discovered-agents list — `grok inspect --json` does not report them — but custom role names are shown under **Run as custom role** in Settings' default-agent picker and the chat agent pill menu. Choosing one in those pickers runs the whole session as that role; to spawn it as a child subagent, ask for it in chat.
- **Why edit the file directly:** grok's `/agents` (`/config-agents`) TUI manager is a pager builtin, not exposed over `grok agent stdio` (same limitation as `/remember`). Covered by `AgentsAndCapabilitiesTests`.

## Browser backend

Browser tools are provided by the bundled `agent-browser` CLI (`BrowserSettings.swift`), exposed to grok as an stdio MCP server (`grokbuild-browser`) via `AgentBrowserService.browserMCPConfig`; managed or external Chromium over CDP. (grok's native `browser_tab` was evaluated and removed — it wasn't exposed to sessions in practice.)

## MCP and extension Settings (installed CLI 1.0.4)

- Build MCP commands from `GrokMCPServerDraft`; never split or join a command line. Stdio uses repeated `--env KEY=value`, then `--`, executable, and each argument as its own process argument. HTTP/SSE use repeated `--header NAME: VALUE` and a validated `http`/`https` URL.
- Scope is explicit: `--scope user` or `--scope project`; project operations require the selected workspace as `cwd`.
- The current CLI does not advertise a secret-reference syntax. Environment/header values are literal CLI config values, so the UI requires the disclosure acknowledgment and must retain only names in inventory/receipts. Redact authorization, bearer, token, key, secret, password, URL credentials, diagnostic arguments, and output before display or error propagation.
- `grok inspect --json` exposes compatibility through `externalCompat.cells`. The current fixture has 13 cells: six Cursor, six Claude, and Codex sessions only. Decode current schema strictly, retain legacy-array compatibility, and surface malformed current data as an error rather than empty success.
- Skills, hooks, plugins, and marketplace commands are one-shot bounded work. Preserve the last successful inventory as stale on refresh failure; cancel hidden-pane work; require explicit trust for plugin/source mutation and destructive confirmation for uninstall/removal.

## Scheduled tasks (mirror of grok `scheduler_*`)

grok owns scheduling (`scheduler_create`/`list`/`delete`, `/loop`); the ACP surface is prompt-only, so GrokBuild can't call these tools directly. Instead it **observes** them: `GrokProcess` detects scheduler tool-call `session/update`s (`SchedulerToolParsing.schedulerName`) and yields `AcpEvent.schedulerActivity(payload:)`; `ChatStore` feeds them to `ScheduledTaskTracker` → `ChatStore.scheduledTasks`, rendered by `ChatView.tasksStatusPill`.

- **Authoritative refresh:** `scheduler_list` output replaces the mirror; create/delete update incrementally (correlating `tool_call` rawInput with completing `tool_call_update` rawOutput).
- **Actions drive grok via prompts** (cost a turn): `refreshScheduledTasks()` (`scheduler_list`), `createScheduledTask(interval:prompt:)` (`/loop`), `cancelScheduledTask(_:)` (`scheduler_delete`).
- **Wire shape (verified live, grok 0.2.93):** the initiating `tool_call` carries `_meta."x.ai/tool".name` = `scheduler_*` and `rawInput`; the **completing** `tool_call_update` carries **`rawOutput`** but **no `_meta`**, and `rawOutput.type` is **CamelCase** (`SchedulerCreate` / `SchedulerList` / `SchedulerDelete`). Detection must match `_meta` name OR a **case-insensitive** `rawOutput.type` prefix — see `SchedulerToolParsing`.
- **`/loop` caveat:** the `/loop` slash command is handled by the CLI and does **not** emit a `scheduler_*` tool call, so the pill only updates after **Refresh** (or when grok schedules via its tool, e.g. natural-language requests). The mirror only reflects the live session; schedules fire only while that session's grok process is alive (LRU-capped). Covered by `ScheduledTaskTests` (includes the real captured create→list sequence).

## Background tasks (richer Tasks pill)

Same mirror pattern as schedulers, extended in `BackgroundTaskStore.swift`:

- **Kinds:** scheduled (`scheduler_*`), background `run_terminal_command` (when `background: true` in rawInput), `monitor`, subagent tools (`spawn_subagent`, etc.).
- **ACP:** `GrokProcess` yields `AcpEvent.backgroundActivity(payload:)`; `ChatStore.backgroundActivities` feeds `ChatView.tasksStatusPill` (sectioned menu).
- Covered by `BackgroundTaskTests`.

## Rhai workflows vs skill chips

Two different grok features — do not conflate them in UI copy:

| Feature | What it is | GrokBuild surface |
|---------|------------|-------------------|
| **Skill chips** | User-invocable skills from `grok inspect` (`/design`, `/review`, …) | `SkillSlashCommands` composer chips |
| **Rhai workflows** | Background scripts in `.grok/workflows/`, `/workflow` tools | `[workflows] enabled` in config.toml (`WorkflowsConfigStore`), `WorkflowsSettingsPane`, `workflowsStatusPill`, `SavedWorkflowsPanel` |

`WorkflowsConfigStore.setEnabled` posts `.workflowsConfigChanged` so the chat pill refreshes without restart.

## Memory (cross-session)

The app owns the **toggle**; grok owns storage/index/injection. `grokbuild.memoryEnabled` (Settings → **Memory**) maps in `ChatStore.restartProcess` via `GrokMemoryFlag.argument(noMemory:experimentalMemory:)`:

- `true` → `--experimental-memory`; `false` → `--no-memory` (grok gives `--no-memory` absolute priority, so the app never emits both). It's a launch flag — **app-scoped**, not written to `~/.grok/config.toml`, so the grok TUI is unaffected. Supersedes the old Permissions "Disable memory" toggle (`grokbuild.noMemory` key is now legacy/unused).
- **Files:** `MemoryStore.swift` enumerates `~/.grok/memory/` (global `MEMORY.md`, `<slug-hash>/MEMORY.md`, `<slug-hash>/sessions/*.md` newest-first); `MemoryBrowserPanel.swift` is a read-only viewer (copy/reveal/delete-session, session-only guard). `ChatView.memoryStatusPill` (label "Memory", **only rendered when memory is enabled** — no off-state pill) surfaces Browse / Remember / Open Memory Settings.
- **ACP limitation (verified live, grok 0.2.93):** enabling memory registers `memory_search`/`memory_get` + first-turn recall, but `/remember`, `/flush`, `/dream`, `/memory` are **TUI pager builtins** and are **not** in `availableCommands` over `grok agent stdio`. So **Remember** writes a note directly to global `MEMORY.md` (`MemoryStore.appendGlobalNote`; grok's watcher reindexes it) via `ChatStore.remember`; flush/dream are not surfaced (they run automatically / in the TUI). Do not add `/flush`/`/dream` prompt actions — they'd be treated as literal text. Covered by `MemoryStoreTests` + `GrokMemoryFlag` tests.

## Bundled skills

Skills ship under `GrokBuild/Resources/Skills/` and install to `~/.grok/skills/` when features are enabled:
- `grokbuild-browser-control` — `BrowserSkillInstaller`
- `grokbuild-grok-web` — `BrowserSkillInstaller` (installed alongside browser-control when browser tools enabled; drives grok.com web features like Imagine/skills/connectors via browser tools)
- `grokbuild-computer-use` — `ComputerUseSkillInstaller`
- `grokbuild-desktop` — retired from the packaged runtime; do not restore it as a self-hint

Browser **quick presets** (`BrowserPreset` in `BrowserSettings.swift`) apply runtime/session-name/CDP settings for common targets (e.g. `.grokCom`).

## After changing CLI integration

Same session, before finishing:

1. **`make test`** — extend `UpdateCheckerTests`, integration tests, or service tests as appropriate.
2. **`ARCHITECTURE.md`** — GrokProcess/ACP flow, persistence keys, notifications, feature subsystem table.
3. **`README.md`** — if user-visible CLI/settings behavior changed.
4. **This skill** + `grok-cli-integration.mdc` — if APIs or update-check behavior changed.
5. **Bundled skill `SKILL.md`** — if install path, tools, or agent instructions changed.

## Workspace instructions

Per-project `AGENTS.md` in workspace roots is surfaced in the sidebar; this repo's root `AGENTS.md` applies when GrokBuild desktop is the workspace.
