---
name: grokbuild-dev
description: Builds, runs, and tests the GrokBuild macOS SwiftPM app. Use when developing GrokBuild, running make targets, fixing build failures, or working on SwiftUI/AppKit UI in this repo.
---

# GrokBuild development

## Quick start

```bash
make run          # build release + launch via open
make test         # swift test
swift build       # debug build
xed .             # open Package.swift in Xcode (optional)
```

## Before UI work

1. Read `ARCHITECTURE.md` for file layout.
2. Prefer `make` over ad-hoc `xcodebuild` (no `.xcodeproj`).
3. After Swift changes, run `swift build` or `make build`.

## Definition of done (every code change)

**Do not finish a task with code-only diffs.** Same session:

1. **`make test`** — must pass; add tests in `Tests/GrokBuildTests/` for behavior you changed.
2. **Computer Use** — required for **every** code change, not only SwiftUI view edits.
   For local iteration, `make run` relaunches `.build/GrokBuild.app`. For campaign
   or installed acceptance, quit every GrokBuild instance, `make ship`, then drive
   **`/Applications/GrokBuild.app` only** (`snapshot --app GrokBuild` is not proof
   if the running exec is `.build` or `dist`). Default: **`user-grokbuild-computer-use` MCP**; fallback: `agent-desktop` directly or Orca `computer-use` CLI. Service/persistence changes still need a live check of the user-visible outcome.
3. **`ARCHITECTURE.md`** — update source map, persistence, notifications, or common tasks → files when structure/flow changes.
4. **`README.md`** — update when users would notice the change.
5. **`BUILDING.md`** — update when build/packaging/scripts change.
6. **Skills/rules** — update relevant `.cursor/skills/` or `.cursor/rules/` if workflow changed.

Full checklist: `.cursor/rules/docs-and-tests.mdc`.

## Common tasks

| Task | Command |
|------|---------|
| Package .app | `make app` → `dist/GrokBuild.app` |
| DMG | `make dmg` |
| Clean | `make clean` |
| Unit tests | `make test` |
| Lifecycle v3 / true-MRU tests | `swift test --filter 'Session(LifecycleV3|Persistence)Tests'` |
| Slice 3 continuity / send-gate tests | `swift test --filter 'GrokSessionTranscriptImporterTests|SessionLifecycleV3Tests|ACPClientContractTests/testSavedBackendCannotStartOrSendBeforeContinuityGateAllowsIt'` |
| Slice 4 provenance / explicit recovery tests | `swift test --filter 'GrokSessionTranscriptImporterTests|SessionLifecycleV3Tests|ACPClientContractTests'` |
| Coherence Settings apply / reload / LRU tests | `swift test --filter 'SettingsTabTests|SettingsRuntimeContractTests|SessionLifecycleTests'` |
| Forward-slices Slice 5 agentic acceptance harness | `swift test --filter AcceptanceHarnessTests` |
| Forward-slices Slice 6 coordination seams | `swift test --filter 'SessionRuntimeRetentionTests|RunHistoryTests|AcceptanceHarnessTests|ACPClientContractTests|LifecycleAndSubprocessTests|BackgroundTaskTests|UsageAndRoutingTests|ComposerPresentationContractTests|CodexShellParityTests|SessionDashboardNavigationTests'` |
| Slice 7 Settings extensions / schema / cancellation tests | `swift test --filter 'SettingsExtensionContractTests|SettingsTabTests|CompatConfigTests|WorkflowRunTests|SessionLifecycleTests|SubprocessHygieneTests'` |
| Slice 0 synthetic fixtures | `Tests/GrokBuildTests/Fixtures/CoherenceRepair/` |

## Coherence profiling

The redacted `OSSignposter` contract lives in `PerformanceInstrumentation.swift` under subsystem `com.grokbuild.app`, category `Performance`. Capture the named lanes with Instruments → Points of Interest; never add prompts, rendered content, credentials, headers, environment values, raw histories, or absolute private paths as signpost metadata. Use `docs/GROKBUILD_SLICE_0_BASELINE_2026-08-01.md` as the pre-repair corpus/baseline and keep Computer Use transport time separate from product signpost duration.

Session lifecycle changes must run both the focused filter above and `make test`. Migration tests use isolated UserDefaults suites plus the pinned synthetic HMAC/CLI fixtures; do not point tests at the installed app's preference domain. Recovery fixtures must retain row provenance (root, worker, unknown/non-final) and prove that startup performs no candidate scan, a common prompt is review-only, Relink re-verifies an exact choice, and Continue as New starts no process before a real send.

Settings apply changes must keep `ConfigurationChange` narrow, route launch-affecting panes through `SettingsApplyRequest`, and run the coherence Settings filter plus `make test`. The fake ACP reconnect fixture is synthetic and provider-send-free; it must continue to prove that two streaming Applies share one restart and one exact tab/backend identity.

## grok CLI dependency

App requires `grok` on PATH or at `~/.grok/bin/grok`. User must run `grok login`. Test CLI: `grok --version`.

## Architecture reminders

- Process: `GrokProcess` + `ChatStore`
- Workspaces: `WorkspaceStore` + `SessionLayoutStore`
- Application menus and window lifecycle: `AppDelegate`
- Full map: `ARCHITECTURE.md`
- Do not commit unless the user asks.
