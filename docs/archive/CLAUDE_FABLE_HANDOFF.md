# GrokBuild UI Rescue — Completion Record and Claude Fable Handoff

## Purpose

This document records where the current GrokBuild Desktop work started, what was changed, what was verified, and what still needs a skeptical second pass.

The current repository is the maintained open-source GrokBuild Desktop codebase, not the older custom app that previously used the similar name **Grok Build**.

## Exact project identity

| Item | Current truth |
|---|---|
| Local repository | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| Upstream | `rimusz/grok-build-desktop` |
| Personal fork | `schmitzjimmy1-star/grok-build-desktop` |
| Base commit | `36866821397ea550c5fb6a7db2e4c7de35cd0f21` |
| Working branch | `codex/warm-glass-ui` |
| UI overhaul commit | `1a8fc22fef3fbdae7dae973fddb953f87eb9bc62` |
| Draft pull request | [schmitzjimmy1-star/grok-build-desktop#1](https://github.com/schmitzjimmy1-star/grok-build-desktop/pull/1) |
| PR state at handoff | Open, draft, clean merge state, no remote CI status posted |
| Local state at handoff | Clean; branch tracks `personal/codex/warm-glass-ui` |

The separate older custom SwiftUI/ACP project once located under `/Users/jimmyschmitz/Documents/Grok Builf` and installed as `/Applications/Grok Build.app` was retired previously. Do not confuse its old source, bundle identifier, cleanup history, or parity documents with this repository.

## Where we started

The upstream app was functional and impressively broad, but its presentation felt assembled feature-by-feature instead of designed as one native macOS product.

The starting problems were visible across repeated live reviews:

- Amber, red, green, purple, and blue accents competed for attention across the chat and Settings surfaces.
- Large capsules and thick rounded cards gave the app a padded “pillow UI” appearance.
- Monospace and terminal-oriented copy appeared in ordinary explanatory UI.
- The project sidebar consumed permanent space and Settings depended on it, preventing a clean full-width chat canvas.
- The top of the window contained redundant lines, controls, and menu/status affordances.
- The composer was visually heavy and its controls expanded into a large custom popover.
- Settings pages stretched across the window, used inconsistent proportions, and looked like separate utilities bolted together.
- The transcript type scale was too large, Thinking appeared in the wrong place, and the decorative assistant/star treatment added noise.
- The app opened like a floating utility instead of using the available 13-inch Apple Silicon MacBook Air canvas.
- A large custom status-bar menu duplicated normal macOS application commands.

The intended direction became:

> A warm, quiet, dark, native macOS workspace: mostly flat, only slightly curved, monochrome, restrained, responsive, and closer to the focus of Codex or Cursor than a developer dashboard. Controls should appear when needed and otherwise get out of the way.

## Design rules established during the pass

These are product decisions, not temporary implementation accidents:

1. Use native SF typography for ordinary UI. Reserve monospace for commands, code, paths, and diagnostics.
2. Keep color neutral. Use semantic color only where loss of meaning or safety would otherwise occur.
3. Prefer 4–8 point radii over large capsules.
4. Avoid decorative gradients, glowing accents, thick borders, and deep shadows.
5. Center reading and settings content at a deliberate maximum width instead of stretching it.
6. Allow the project sidebar to collapse completely.
7. Settings should own a compact navigation rail and should not require the project sidebar.
8. Keep the chat toolbar sparse: sidebar, new session, one overflow menu, and direct Settings access.
9. Keep the composer visually primary but mechanically simple.
10. Use standard macOS application menus instead of a duplicate status-bar application.
11. Target the usable logical canvas of a 13-inch Apple Silicon MacBook Air.
12. Thinking belongs immediately above the answer it produced, not below the completed response as a detached transcript footer.

## What was completed

### 1. Shared visual system

Added `GrokBuild/AppTheme.swift` as the visual source of truth for:

- the graphite canvas and sidebar;
- matte raised surfaces;
- monochrome status and text colors;
- compact 11/14/17 point type roles;
- 4/6/8 point radii;
- centered transcript, composer, and Settings widths;
- restrained borders and optional minimal shadow.

The existing `grokGlassSurface` name remains for call-site compatibility, but its implementation is now matte rather than a decorative glass gradient.

### 2. Native application shell

Reworked `GrokBuild/AppDelegate.swift` and removed `GrokBuild/StatusBarController.swift`.

The app now:

- uses a standard Dock/windowed application model;
- exposes About, Settings, update checks, Project, Session, and Window commands through normal macOS menus;
- removes the duplicate `NSStatusItem` application surface;
- uses a transparent title bar without separator rules;
- opens against the display’s available frame;
- retains single-instance and reopen behavior;
- keeps DEBUG update simulation in the application menu.

The related obsolete status-bar tests were removed and replaced with focused application-menu coverage.

### 3. Responsive primary workspace

Updated `GrokBuild/MainWindowLayout.swift`, `GrokBuild/ContentView.swift`, and `GrokBuild/Views/SidebarView.swift`.

The main window now:

- defaults to a 1440×900 logical canvas and fills the current screen’s visible frame;
- maintains an 1100×720 floor;
- keeps the visible sidebar compact;
- persists sidebar visibility;
- allows the sidebar to disappear entirely for a blank, focused chat canvas;
- automatically suppresses the project sidebar while Settings is open;
- gives Settings its own navigation rail rather than stacking two sidebars.

### 4. Minimal chat and composer

Substantially reworked `GrokBuild/Views/ChatView.swift` and supporting chrome/model files.

The chat surface now has:

- a centered 760 point reading column;
- an 820 point bounded matte composer;
- fewer permanent top-level controls;
- consolidated skills, workflows, research, and imagine actions;
- session controls hidden behind an explicit disclosure;
- a compact native Model/Effort menu instead of the oversized custom popover;
- a responsive four-card empty state;
- a restrained monochrome hierarchy;
- reduced capsule styling and decorative color.

### 5. Transcript hierarchy and Thinking placement

Updated `GrokBuild/Views/RichMessageView.swift`, `GrokBuild/Views/MessageBubble.swift`, and related parsing/layout tests.

Completed changes include:

- smaller native transcript typography;
- removal of the decorative assistant/star avatar;
- more deliberate Markdown headings, lists, quotes, tables, code, and dividers;
- Thinking attached immediately above the streaming or most recent assistant answer;
- less terminal-like presentation for ordinary prose;
- guarded Mermaid/LaTeX rendering so embeds do not reload unnecessarily.

### 6. Settings reformat

`GrokBuild/Views/SettingsView.swift` received the largest visual pass.

The new structure:

- centers each Settings page in a shared 760 point detail column;
- uses a compact 168 point navigation rail;
- standardizes control widths and card proportions;
- flattens visual treatments;
- removes most decorative feature colors;
- reduces oversized toggles, controls, and pill treatments;
- simplifies copy and information hierarchy;
- normalizes system icons and action placement;
- prevents pages from stretching into empty full-screen deserts.

Agents, Models, Memory, Workflows, Browser, Computer Use, MCP Servers, Skills, Plugins, Marketplace, Permissions, Compatibility, Hooks, and App remain represented. The work here was a visual and structural pass, not a complete feature-by-feature behavioral reimplementation.

### 7. Language and documentation cleanup

Updated:

- `README.md`
- `ARCHITECTURE.md`
- `BUILDING.md`
- `scripts/README.md`
- `.cursor/rules/`
- `.cursor/skills/grokbuild-dev/SKILL.md`
- `GrokBuild/Resources/Skills/grokbuild-desktop/SKILL.md`

The documentation now describes the standard application menu, collapsible sidebar, centered surfaces, theme tokens, transcript behavior, and screen-filling layout.

### 8. Regression coverage

Added or updated focused tests for:

- application-menu copy;
- transcript/Thinking attachment;
- compact human-readable model effort names;
- Settings navigation and proportions;
- MacBook Air-oriented window sizing;
- Markdown parsing behavior affected by the transcript pass.

Final local verification:

```text
make test
Executed 262 tests, with 0 failures

git diff --check
Clean
```

The development bundle was rebuilt, launched, and reviewed iteratively against the requested visual direction.

## Current runtime truth

At the final inventory:

- `/Applications/GrokBuild.app` was not present.
- The running app was `.build/GrokBuild.app`.
- The bundle reports version `0.1.20`.
- The bundle identifier is `com.grokbuild.app`.
- The development app had launched both `grokbuild-browser-mcp` and `GrokBuildComputerUseMCP`.
- `.build/` was approximately 777 MB and actively owned by the running development app.

The presence of the helper processes proves packaging and launch, not complete Browser or Computer Use acceptance.

## What was intentionally not claimed as complete

### Dead-code and architecture audit

This pass removed the obvious status-bar implementation, but it did not attempt a full reachability or target-membership audit.

Known leads include:

- `GrokBuild/GrokBuildApp.swift` is documented as an excluded legacy `@main` file.
- `SettingsView.swift` is approximately 5,215 lines.
- `ChatView.swift` is approximately 2,056 lines.
- `ChatStore.swift` is approximately 1,728 lines.
- `ContentView.swift` is approximately 1,412 lines.
- compatibility and migration paths still contain intentionally named legacy branches;
- some types may be source-present but excluded from the package target rather than truly dead.

Do not delete a “legacy” path merely because its name is ugly. Prove target membership, callers, persistence migration needs, and runtime reachability first.

### Load, compile-time, and runtime performance

No Instruments pass, Swift compiler timing audit, allocation profile, view invalidation study, or settings-lazy-loading benchmark was completed.

The large view and state files are strong refactoring candidates, but file length alone is not proof of runtime cost. Measure before cutting.

### Computer Use

The repository already contains:

- `GrokBuild/Services/ComputerUseService.swift`
- `GrokBuild/Services/ComputerUseSettings.swift`
- `GrokBuild/Services/ComputerUseSkillInstaller.swift`
- `GrokBuild/Services/ComputerUseCursorInstaller.swift`
- `GrokBuildComputerUseMCP/`
- `GrokBuild/Resources/Skills/grokbuild-computer-use/`
- `Tests/GrokBuildTests/ComputerUseIntegrationTests.swift`

What remains is a complete live acceptance pass:

1. permission onboarding for Accessibility and Screen Recording;
2. helper discovery and MCP startup;
3. settings draft/apply/restart behavior;
4. actual snapshot, click, type, scroll, and screenshot calls;
5. useful errors when permissions or the helper are missing;
6. confirmation that enabling the feature does not create runaway CPU or duplicate helper processes;
7. a minimal UI entry point that does not reintroduce dashboard clutter.

### Browser control caution

An earlier installed build had a built-in managed-browser failure that could drive CPU to roughly 99%. The extension-backed real-Chrome bridge worked better on that machine. Recheck current code and runtime behavior; do not assume either path is healthy from a toggle, process name, or MCP registration alone.

### Release and distribution

This branch has not been:

- merged to `main`;
- signed or notarized;
- published as a release;
- installed into `/Applications`;
- proven through remote CI;
- tested for update migration from the prior notarized build.

## Guardrails for the next pass

1. Read `AGENTS.md`, `ARCHITECTURE.md`, `README.md`, and `BUILDING.md` before editing.
2. Start from `codex/warm-glass-ui` at `1a8fc22`.
3. Preserve the clean draft PR and keep commits narrow enough to review.
4. Keep `origin` pointed at `rimusz/grok-build-desktop`; publish Jimmy’s work to the `personal` remote under `schmitzjimmy1-star`.
5. Do not overwrite upstream history or silently merge the draft PR.
6. Preserve the established minimal visual language unless a change has live evidence behind it.
7. Every behavior change needs tests, documentation, a rebuilt app, and live Computer Use verification.
8. Do not delete `.build/` while its development app or helpers are running.
9. Do not treat successful compilation, a running helper, or a green Settings label as feature acceptance.
10. Keep secrets, OAuth material, and local configuration out of commits and screenshots.

## Handoff to Claude Fable

Claude Fable: take this repository as an independent senior-engineering review. Do not assume the preceding implementation is correct merely because it builds or looks better.

Begin with a read-only deep analysis and produce an evidence-backed report before editing. Compare `origin/main` at `3686682` with `codex/warm-glass-ui` at `1a8fc22`, inspect Swift package target membership, trace runtime call sites, and launch the current development app.

Your analysis should answer four questions:

1. **What is genuinely dead or redundant?** Identify unreachable types, excluded legacy entry points, obsolete compatibility paths, duplicate settings components, unused assets, stale tests, and documentation that no longer matches behavior. Separate proven dead code from migration or fallback code that merely looks old.
2. **How can the app carry less weight?** Measure launch cost, memory, CPU, helper-process behavior, Swift compile time, `@Observable` invalidation breadth, Settings view construction, transcript rendering, WKWebView lifetime, persistence churn, and background services. Propose the smallest refactors that produce measurable wins. Pay special attention to `SettingsView.swift`, `ChatView.swift`, `ChatStore.swift`, `ContentView.swift`, `GrokProcess.swift`, and `CustomModelSettings.swift`.
3. **How should Computer Use become a trustworthy product feature?** Audit the existing service, settings, helper executable, bundled skill, permissions, MCP configuration, and tests. Then design and—only after the audit—implement the thinnest native UI needed to enable, diagnose, and use snapshot/click/type/scroll/screenshot actions without reintroducing clutter or duplicate processes. Prove it with real macOS interaction.
4. **Where can the UI/UX still become more native and polished?** Review spacing rhythm, type hierarchy, focus/hover/pressed states, keyboard navigation, VoiceOver labels, reduced-motion behavior, empty/loading/error states, popover sizing, Settings proportions, sidebar transitions, transcript density, composer behavior, and MacBook Air full-screen use. Preserve the quiet graphite palette, slight curves, native SF type, centered content, minimal composer, and collapsible sidebar.

Return the audit first with severity, evidence, exact files, expected benefit, regression risk, and a proposed commit sequence. Do not begin a sweeping rewrite. After approval, implement in small commits; run `make test`, rebuild and relaunch, verify every changed path through live Computer Use, update the governing documentation, and leave the branch and draft PR in a clean, reviewable state.
