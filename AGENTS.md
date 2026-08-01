# GrokBuild Desktop

Native SwiftUI macOS frontend for the `grok` CLI (`grok agent stdio`).

## Canonical worktree — hard stop

> [!CAUTION]
> Active work belongs only in
> `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`,
> on Jimmy's `schmitzjimmy1-star/grok-build-desktop` fork. The old
> `/Users/jimmyschmitz/Documents/Grok Builf` / `jimmmy-Jim/Grok-Build-GUI`
> line is retired evidence: do not build, install, or continue it. Read
> `CANONICAL_WORKTREE.md` and run its preflight before editing.

## Read first

1. `CANONICAL_WORKTREE.md` — immutable repository/worktree identity and retired-line stop rule.
2. `ARCHITECTURE.md` — app map, data flow, persistence keys, feature subsystems, and **“common tasks → files”** lookup for new chats.

## Cursor in this repo

- Rules: `.cursor/rules/` (architecture, SwiftUI, grok CLI integration, AppKit panels, **docs-and-tests**)
- Skills: `.cursor/skills/` (dev workflow, release, grok CLI checks)

## Grok CLI in this repo

GrokBuild stays close to the CLI. Do not reimplement CLI features (ACP, MCP, skills, permissions, plan mode) in the app unless the UI truly needs a thin wrapper.

When changing app behavior that touches the CLI:

1. Prefer existing services: `GrokProcess`, `GrokCLIService`, `ChatStore`, `UpdateChecker`.
2. Feature subsystems have their own services: `AgentBrowserService` (browser tools), `ComputerUseService` (desktop automation via `agent-desktop`, bundled at packaging time — packaging fails if it is missing; install with `npm install -g agent-desktop`), `CustomModelStore` (OpenAI-compatible models in `~/.grok/config.toml`).
3. Keep workspace/session state in `WorkspaceStore` and `SessionLayoutStore`.
4. Bundled grok skills live in `GrokBuild/Resources/Skills/` (`grokbuild-browser-control`, `grokbuild-computer-use`, `grokbuild-grok-web`) and are copied into the app bundle at build time. (`grokbuild-desktop` was removed 2026-07-31: it shipped in every build but no code ever installed or looked it up.)

## Code style

- Minimize diff scope; match surrounding Swift/SwiftUI conventions.
- AppKit panels (About, Updates) share `AboutStyle` metrics.
- Version strings: `VERSION` file, surfaced through `AppVersion`.
- Build with `make run` or `swift build`; do not require an Xcode project.

## Documentation, tests & Computer Use (required)

Every code change must ship with **updated documentation**, **tests**, and **Computer Use verification** in the same session — not as a follow-up.

1. **Tests** — run `make test`; add or extend `Tests/GrokBuildTests/` for new or changed behavior.
2. **Computer Use** — required for **every** code change (not only view files). `make run` to repackage/relaunch, then drive the running app with whatever computer-use tooling the current environment provides (the bundled `GrokBuildComputerUseMCP` helper and `agent-desktop` also work directly). Reach the state your change affects and confirm it in the live UI (e.g. restored transcripts, settings, tab switches).
3. **ARCHITECTURE.md** — update for new services, persistence keys, notifications, subsystems, or flows (canonical app map).
4. **README.md** — update for user-visible features or install/requirements changes.
5. **BUILDING.md** / **scripts/README.md** — update for build, release, packaging, or script changes.
6. **Skills / rules** — update `.cursor/skills/` or `.cursor/rules/` when workflows or integration contracts change.
7. **Bundled skills** — update `GrokBuild/Resources/Skills/*/SKILL.md` when agent-facing skill behavior changes.

See `.cursor/rules/docs-and-tests.mdc` for the full checklist.
