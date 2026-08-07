# Paste this into Claude Fable

```markdown
You are taking over a controlled, slice-by-slice redesign of GrokBuild's native macOS frontend. The target is the current OpenAI Codex experience in the ChatGPT desktop app—not OpenCodex's provider dashboard and not a generic developer dashboard.

## Canonical project identity

Work only in this folder:

`/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`

GitHub repositories:

- Jimmy's maintained repository and publication target:
  `https://github.com/schmitzjimmy1-star/grok-build-desktop`
- Local remote name for Jimmy's repository: `personal`
- Preserved third-party upstream:
  `https://github.com/rimusz/grok-build-desktop`
- Local remote name for upstream: `origin`

Current baseline at handoff:

- branch: `main`
- HEAD: `8b8801689f540f1715615d51cbccb1494cd736b3`
- installed app: `/Applications/GrokBuild.app`
- bundle identifier: `com.grokbuild.app`
- installed source repository stamp:
  `https://github.com/schmitzjimmy1-star/grok-build-desktop`
- installed source commit stamp:
  `8b8801689f540f1715615d51cbccb1494cd736b3`
- installed source dirty stamp: `true`

The similarly named historical line below is retired evidence and is not an implementation source:

- `/Users/jimmyschmitz/Documents/Grok Builf`
- `https://github.com/jimmmy-Jim/Grok-Build-GUI`
- historical product name: `Grok Build.app`

Do not build, open as a source root, modernize, publish, or copy code from the retired line.

## Read completely before acting

Read these files in order:

1. `AGENTS.md`
2. `CANONICAL_WORKTREE.md`
3. `ARCHITECTURE.md`
4. `docs/CLAUDE_FABLE_CODEX_PARITY_SLICES_2026-08-07.md`
5. `docs/UI_ACCEPTANCE_MATRIX.md`

The slice plan is authoritative for scope, placement rules, backend preservation, testing, installed-app acceptance, and stop conditions.

## Existing dirty work — preserve it

At handoff, these paths are modified or untracked:

```text
 M ARCHITECTURE.md
 M CANONICAL_WORKTREE.md
 M GrokBuild/AppTheme.swift
 M GrokBuild/ContentView.swift
 M GrokBuild/Services/ChatStore.swift
 M GrokBuild/Views/ActivitySidebar.swift
 M GrokBuild/Views/ChatView.swift
 M GrokBuild/Views/SidebarView.swift
 M README.md
 M Tests/GrokBuildTests/ACPClientContractTests.swift
 M Tests/GrokBuildTests/WorkbenchIntentTests.swift
?? GrokBuild/Models/ModelRouteContract.swift
?? Tests/GrokBuildTests/ModelRouteContractTests.swift
?? docs/CLAUDE_FABLE_CODEX_PARITY_SLICES_2026-08-07.md
?? docs/CLAUDE_FABLE_CODEX_PARITY_HANDOFF_PROMPT_2026-08-07.md
```

Treat all of it as intentional user work. Before editing, regenerate `git status --short`, record hashes for the dirty paths, and preserve them. Do not checkout, reset, clean, stash, overwrite, or reconstruct any dirty file from GitHub.

If current branch, HEAD, remotes, installed identity, or dirty inventory differs from this prompt, stop and reconcile the difference before mutation. Current local truth wins over this handoff only after you show the evidence.

## Design authority

The primary visual fixtures are Jimmy's photographs of the current Codex desktop experience:

- `/tmp/codex-remote-attachments/019fde3b-ae3c-7a83-ade1-9cc6fc26ac34/D43438DA-24F2-4A2E-B2CB-227465289479/1-Photo-1.jpg`
- `/tmp/codex-remote-attachments/019fde3b-ae3c-7a83-ade1-9cc6fc26ac34/D43438DA-24F2-4A2E-B2CB-227465289479/2-Photo-2.jpg`

If those temporary files no longer exist, stop and ask Jimmy to reattach them. Do not substitute screenshots of OpenCodex or a community clone.

First-party behavioral references:

- OpenAI Codex app introduction:
  `https://openai.com/index/introducing-the-codex-app/`
- Desktop quickstart:
  `https://learn.chatgpt.com/docs/quickstart`
- Code review behavior:
  `https://learn.chatgpt.com/docs/code-review`
- Current desktop/Codex changes:
  `https://learn.chatgpt.com/docs/whats-new`
- Official public Codex source and app-server protocol:
  `https://github.com/openai/codex`

Research boundaries:

- `openai/codex` is authoritative for public thread, turn, review, diff, and approval protocol boundaries. Its public repository does not contain the proprietary desktop frontend, so it is not pixel-level visual source code.
- `lidge-jun/opencodex` is a provider proxy with a React management dashboard. Its dashboard is explicitly the wrong design target.
- Community Codex clients can inform separation of concerns but cannot override Jimmy's photographs or OpenAI's product behavior.

## Product objective

This is not a color facelift. Replace the remaining GrokBuild workbench information architecture with a native SwiftUI translation of Codex:

- restrained left navigation with projects and nested chats;
- compact task header;
- conversation-first center canvas;
- inline changed-files summary and real Review action;
- one wide `Do anything` composer;
- no Details shelf or project telemetry under the composer;
- no permanent Agents or Connections sections in the left sidebar;
- compact top-right contextual inspector with Subagents, Computer Use, Sources/context, and an optional deep Run details entry;
- dedicated Git Review pane for diffs, staging, reverting, and comments.

Current visible defects include:

1. `showComposerDetails`, `composerDetailsToggle`, and `composerDetailsDisclosure` still create a developer telemetry shelf beneath the composer.
2. `SidebarView` still renders Agents, Connections, and Activity-style operational lanes as permanent navigation.
3. `ActivitySidebar` is still a tall run-evidence dashboard rather than the compact contextual inspector shown in the photographs.
4. Review, usage, route receipts, project status, worker state, and Activity are duplicated across multiple surfaces.

## Runtime and backend boundary

Preserve GrokBuild's existing runtime. Do not migrate it to Codex app-server and do not import OpenCodex.

Keep intact unless the authorized slice explicitly names a narrow projection change:

- `grok agent stdio` and `GrokProcess`;
- `ChatStore` session/runtime authority;
- transcript persistence and lazy resume;
- continuity ledger and fail-closed recovery;
- generation-bound model/provider receipts;
- `RunEvidenceLiveProjection` and `RunEvidenceSnapshot` factual semantics;
- subagent lifecycle and stale-generation rejection;
- Git diff and Review operations;
- Keychain credentials and provider endpoint policy;
- MCP attachment semantics;
- Browser and Computer Use permission gates;
- approvals, rich Markdown, Mermaid, math, tables, attachments, and voice.

Moving a fact to its correct visual home is authorized within the slice. Weakening its evidence contract is not.

## Slice execution rule

Execute exactly one explicitly authorized slice per task. Do not roll into the next slice because tests are green or the next change looks nearby.

For every slice:

1. State the exact slice objective and file scope.
2. Run canonical identity and dirty-worktree preflight.
3. Preserve unrelated work.
4. Add or update focused tests.
5. Run focused tests, `make test`, `git diff --check`, and `make ship`.
6. Kill the stale installed process and relaunch `/Applications/GrokBuild.app`.
7. Perform Computer Use acceptance against the installed app in the exact changed state.
8. Verify `dist` and installed executable hashes match.
9. Verify `codesign --verify --deep --strict`, TeamID `DD2GCQJVB4`, and no quarantine.
10. Update required documentation and the slice receipt.
11. Stop and provide the exact next-slice handoff from the plan.

Do not send a billable/provider prompt for UI-only acceptance. Do not commit, push, create a PR, merge, publish, or modify GitHub unless Jimmy separately authorizes publication.

## Current authorization

Execute **Slice 0 only** from:

`docs/CLAUDE_FABLE_CODEX_PARITY_SLICES_2026-08-07.md`

Slice 0 is evidence-only. Preserve the dirty worktree, freeze the installed visual/source baseline, create or update the parity matrix, and add the focused red-baseline inventory tests. Do not modify production code. Do not start Slice 1.

At completion, report:

- canonical path, branch, HEAD, remotes, and installed identity;
- exact dirty baseline and preservation receipt;
- screenshots/states captured;
- parity-matrix path;
- tests and command results;
- installed-app observations;
- anything that blocked faithful comparison;
- the exact three-sentence Slice 1 handoff from the plan.
```
