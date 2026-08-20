# GrokBuild frontend rebuild — 2026-08-20

## Decision

This campaign is a rebuild and rethink of GrokBuild's native macOS frontend, not
another refinement pass over the accepted Visual Quiet shell. The target is the
calm composition demonstrated by the public `msk-labs/grok-build-gui` screenshot:
a pale macOS window, a persistent Codex-style project/session rail, a spacious
conversation canvas, compact workspace and branch controls, and a bottom-docked
composer.

The reference supplies product ideas only. GrokBuild remains native SwiftUI. Do
not copy source, assets, stylesheets, components, dependencies, Electron/React
architecture, runtime restoration, embedded-browser implementation, terminal
implementation, or backend behavior from that repository.

OpenAI Codex compatibility research and the presentation-only adoption map live
in [`GROKBUILD_CODEX_COMPATIBILITY_RESEARCH_2026-08-20.md`](GROKBUILD_CODEX_COMPATIBILITY_RESEARCH_2026-08-20.md).
That note permits selected public client-state patterns, not a Codex runtime or
second protocol layer.

## Identity and branch

- Canonical worktree:
  `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- Canonical repository: `schmitzjimmy1-star/grok-build-desktop`
- Read-only upstream: `rimusz/grok-build-desktop`
- Canonical app: `/Applications/GrokBuild.app`
- Bundle ID: `com.grokbuild.app`
- Signing team: `DD2GCQJVB4`
- Baseline: personal `main` at
  `532dea26c520428c908913f1f34c2d6a049bcebe`
- Accumulating branch: `codex/frontend-rebuild-com-grokbuild-app`

Every checkpoint is committed with exact paths and pushed to that branch. Do not
open or merge a pull request until the exit gate is complete and Jimmy accepts
the coherent candidate. Do not delete the branch between checkpoints.

## Ownership boundary

This campaign may replace presentation composition, navigation hierarchy,
spacing, color, typography, surfaces, and responsive layout. It must reuse the
existing `WorkspaceStore`, `ChatStore`, `SessionLayoutStore`, `GrokProcess`, and
feature services. The official CLI continues to own ACP sessions, tools, MCP,
skills, permissions, memory, plan mode, subagents, and runtime persistence.

Paid 4C, provider calls, credentials, auth, CLI upgrades, model routing, release
signing changes, new entitlements, session deletion, and generic backend work are
out of scope. The historical broad `ChatView` split remains forbidden unless a
checkpoint names one small extraction with unchanged ownership and tests.

## Visual contract

The rebuild should feel closer to Codex and the reference screenshot than to the
current dark operations console:

- cool graphite/black default canvas with quiet separators and restrained blue accent;
- full-height left rail containing New chat, Plugins, projects, and sessions;
- simple title bar with the current conversation and only essential utilities;
- generous empty/welcome state rather than dashboard density;
- workspace and branch chips directly above the composer;
- wide bottom-docked composer with add-context, permission mode, model/effort,
  voice, and send controls;
- transcript content centered in a readable column, with tool/review detail
  disclosed on demand;
- Light remains the pale original-reference treatment: white canvas, mist-gray
  rail, and black typography. It is a complete appearance, not a recolored dark
  shell.

This is not pixel cloning. Native macOS accessibility, keyboard behavior,
window resizing, reduced motion, existing truth labels, and failure authority
remain first-class.

## Checkpoints

### F0 — campaign and branch contract

Land this document plus the explicit workflow exception. No product behavior
changes. Receipt: clean identity preflight, exact branch, diff check, commit, push.

### F1 — adaptive design system

Replace the current glass-heavy visual tokens with restrained adaptive palettes,
typography, radii, separators, focus, and selection. F2 supersedes the initial
fresh-install Light default with the requested cool graphite/black default while
preserving the original pale reference as the explicit Light appearance.
Keep component ownership unchanged. Add token and contrast contracts. Focused
tests only; no install unless F1 and F2 land together as the shell milestone.

### F2 — window shell and Codex-style rail

Recompose `ContentView`, `SidebarView`, and the minimal top-bar surface into the
new full-height rail plus calm workspace shell. Preserve project/session actions,
badges, accessibility identifiers, and responsive reachability. Organize the
existing projections as New chat, Plugins, Projects, Pinned/Recents, and the
account/settings footer; do not add a Codex project or thread store. This is the
first full-suite, `make ship`, light-mode Computer Use milestone.

### F3 — navigation cleanup, welcome state, and bottom composer

Rebuild the project/session rail almost entirely around roomy custom rows and one
clear route per destination. Recents owns session discovery in the rail; do not
also render a top-level Sessions action. The account footer remains the single
Settings entry, while Settings itself uses a compact categorized picker instead
of mounting a second full-height sidebar. Flatten routine Settings cards into
separated content sections while preserving warning, credential, receipt, and
failure boundaries that carry meaning.

Rebuild the empty conversation around a spacious prompt, workspace/branch chips,
and the bottom-docked composer. Reuse existing workspace, Git, context, model,
permission, voice, send, settings-value, and inventory owners. Do not invent a
second command, settings, session, or runtime owner. Focused tests and a checkpoint
commit, then stop before F4.

### F4 — transcript, tool activity, and review presentation

Restyle the readable transcript column, assistant trace, tool activity, diffs,
changed-files summary, and Review entry points as one coherent light surface.
Preserve ACP status/failure/recovery authority and command-argument disclosure.
The locked implementation is one assistant-turn story: checkpoint-derived status,
bounded public reasoning stages, readable tool receipt rows with on-demand detail,
answer, and the turn-attributed changed-files handoff. The handoff owns the single
closed-state Review action for attributed changes; unattributed repository dirt
remains on the header Review route. Both continue to open the existing preview
owner. User prompts stay compact and visually subordinate, while the same semantic
tokens preserve the hierarchy in cool-charcoal Dark and pale mist-gray Light.
This is the second full-suite, `make ship`, installed transcript milestone.

### F5 — secondary panes and responsive states

Align session browser, plugins, settings entry, activity inspector, preview,
browser, and narrow-window behavior with the rebuilt shell. Do not add Electron
terminal/file-tree/browser copies merely because the reference advertises them.
F5 begins with a visual-chrome checkpoint: rebuild project-folder rows with a
clear icon/label/disclosure hierarchy, place a quiet separator between top
chrome and content, keep update banners below the traffic lights, and remove
purple/lavender action chrome. Dark maps interactive chrome to white/near-white;
Light maps the same semantics to black/charcoal. Blue remains reserved for real
links, while warning, failure, and success retain their semantic colors.

Installed acceptance may include one explicitly authorized, bounded, no-retry
billable prompt that exercises a read-only CLI-owned tool so the transcript,
tool receipt, and usage projection are visually proven together. That proof
does not unlock or modify the separate 4C runtime, budget, provider, credential,
or routing campaign. Focused tests per bounded checkpoint.

### F6 — tranche exit

Run the full suite, clean `make ship`, light and dark installed Computer Use,
keyboard/accessibility checks, narrow and wide window checks, exact bundle/signing
identity, dist/install parity, quarantine check, and two process-zero samples.
Review the entire cumulative diff against baseline. Only then may Jimmy authorize
one PR for the coherent tranche and an exact-head merge.

## Checkpoint receipt

Each commit records:

- checkpoint name and exact intended paths;
- focused tests run and result;
- whether full `make test` or `make ship` was required by the milestone;
- current branch and HEAD;
- confirmation that bundle identity, runtime ownership, locked 4C, credentials,
  provider traffic, and unrelated work were untouched;
- the next bounded checkpoint.

Failures remain failures. A green focused test is not installed acceptance, and a
historical screenshot is not proof of current behavior.
