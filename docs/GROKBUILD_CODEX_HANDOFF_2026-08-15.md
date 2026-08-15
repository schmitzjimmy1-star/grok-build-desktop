# GrokBuild → Codex handoff (Visual Quiet)

**Date:** 2026-08-15
**Audience:** Codex macOS app session
**Read first:** `CANONICAL_WORKTREE.md`, `AGENTS.md`, `ARCHITECTURE.md`, `docs/GROKBUILD_VISUAL_QUIET_CAMPAIGN_2026-08-15.md`, `docs/OUTSTANDING.md`

---

## P3D release snapshot (authoritative)

| Field | Value |
|---|---|
| **Remote** | `personal` → `schmitzjimmy1-star/grok-build-desktop` |
| **Release branch** | `main` |
| **P3D merge** | `1e11be228dba6321ba12bdd2933b9a240011a133` (`1e11be2`) |
| **Code/test commit** | `2e1deb7e2d135a007334096e5deace53a409dc6f` (`2e1deb7`) |
| **P3D publication** | PR #107 — *Promote live workers into the activity canvas* — merged |
| **P3 code merge** | PR #104 — *Visual Quiet Phase 3: overlay sidebar and quiet workbench chrome* |
| **Prior** | P1–P2 at `7a3006d` (PR #102) |
| **Worktree** | `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop` |
| **Installed app** | `/Applications/GrokBuild.app` via `make ship` only |
| **Version file** | `0.1.22` (identity is stamp + commit, not version alone) |
| **Upstream (read-only)** | `origin` → `rimusz/grok-build-desktop` — do not push |

At P3D closeout, local `main` and `personal/main` matched at `1e11be2`; the
code-bearing commit is `2e1deb7`. Run the canonical preflight in
`CANONICAL_WORKTREE.md` before any later work because HEAD may advance.

---

## Current app state (what Jimmy has now)

GrokBuild is a native SwiftUI macOS workbench for `grok agent stdio`. The CLI still owns ACP, MCP, skills, permissions, memory, plan mode, and subagents. GrokBuild owns project navigation, session tabs, composer, diff review, settings, browser/computer-use enablement, and the local update flow.

### Visual Quiet progress

| Phase | Screenshot plan (Jimmy’s six phases) | Actual campaign status |
|---|---|---|
| **P1** Cool tokens | Light loses cream; Dark cooler ink | **Merged** (`7a3006d`). Cool-neutral canvas/sidebar tokens in `AppTheme.swift`. |
| **P2** Quiet welcome | Smaller mark, compact chips | **Merged** (`7a3006d`). Path A: Ask/Build/Review chips, no detail paragraphs. |
| **P3** Header + composer *(screenshot)* | Icon-only Tasks/Review/inspector; slim task strip; tighter composer | **Accepted in two bounded pieces:** overlay/quiet chrome at `bb01c58`, closeout at `aff384c`, and P3C density at `6697530`. |
| **P3D** Live activity composition | Remove duplicate live Run card; show active workers confidently at right | **Merged and installed** (`1e11be2`, PR #107). |
| **P4** Accent sweep | Send/chips/CTAs stop macOS orange/brown | **Not started** |
| **P5** Cheap size | Sharper Dock icon; drop dead Workflows pill | **Not started** |
| **P6** Optional | Welcome-only file extract (not full ChatView split) | **Deferred** |

Jimmy redirected P3 twice on 2026-08-15. The shipped slice is **overlay sidebar + quiet chrome**, not the narrower “header + composer only” row in the early screenshot. Treat the campaign doc phase table as authoritative over the screenshot wording.

### What P3 (`bb01c58`) actually shipped

**Layout / sidebar**
- Codex-style **slide-over project sidebar** — chat canvas stays full width; backdrop tap dismisses.
- **Compact project/session rows** — session lists expand only for the selected project.
- **Settings on the account row** (`grok-sidebar-account-settings`); header gear removed.

**Header / titlebar**
- `.fullSizeContentView` titlebar; controls sit **just under traffic lights** via `TitlebarMetrics`.
- **`TitlebarGlyph`** — SF Symbols rasterized as non-template bitmaps so Dark vibrancy cannot paint icons black/invisible.
- **White icons on Dark** (`titlebarControlNSColor`); ink-on-stone on Light.
- **Filter + Session dashboard** moved from `SidebarView` to **`ChatTopBar`**, right of session title with `headerIconGap` — no collision with description text.
- Icon-only **Tasks**, contextual **Review**, **Run inspector** quick-look dropdown; **More actions** one-click ellipsis (`.menuIndicator(.hidden)`); **no header hairline**.

**Inspector / activity**
- **`RunInspectorQuickLook`** dropdown in header.
- Slimmer **right-side subagent tracker** in `ActivitySidebar`.

**Calmer chrome**
- Launch choices: three quiet text actions (not tinted banner).
- Task context strip **hidden when idle `.ready`**.

**Tests / docs**
- 894 tests green at merge time.
- Updated: `ARCHITECTURE.md`, `README.md`, `AGENTS.md`, campaign doc, parity/accessibility tests.

### P3 closeout complete

- Clean merged-main `make ship`: 894/0, `bb01c58`, `dirty=false`, signed Team
  `DD2GCQJVB4`, no quarantine, dist/install SHA-256 `9109250b74ef…`.
- Installed Computer Use accepted the overlay/sidebar/titlebar/account-row/
  inspector surface. Marker `GB-VQ-P3-20260815T154813Z` returned exactly
  `GB_VQ_P3_OK` on Grok 4.6; only its exact tab/backend was deleted.
- Two post-quit process-zero samples passed. Protected OK-F and backend
  `019ffdad-0d4f-7f42-a429-7ac12ad8198d` remain.

### P3C composer/task-strip density accepted

- Composer chrome is 11×7 inner, 20×5 outer, and shadow-free while every
  authoring action stays 36×36 and the editor still grows one-to-eight lines.
- The collapsed task contract is one `objective · phase` line plus disclosure;
  branch, model, worktree, review, tools, checkpoints, identities, and controls
  remain available inside it.
- Focused 52/0 and full 896/0 gates passed. Clean candidate `make ship` installed
  `6697530`, `dirty=false`, with signed/hash parity.
- Three bounded paid packets covered exact no-tool settlement, two ordered
  read-only tools, and two parallel workers. Coordination passed; the agentic
  answer's final-only wording is honestly partial because it emitted one progress
  sentence before the requested token.
- Exact cleanup removed all three parents and moved the two CLI-invisible child
  ledgers recoverably to Trash. Marker files are zero, protected OK-F remains, and
  two normal-quit process-zero samples passed.

### P3D live activity composition accepted

- The redundant live transcript Run card is gone; the task strip, tool trace,
  Stop control, inspector, and durable receipts retain the underlying truth.
- Current-turn workers occupy a 340-point right-side canvas. Compact cards keep
  assignments readable, hide raw parent prompts and technical receipts behind
  disclosures, and surface failed or unreconciled child tools as **Needs Review**.
- Focused 61/0 and full 897/0 gates passed. Clean candidate `make ship` installed
  `2e1deb7`, `dirty=false`, with signed/hash parity.
- Five bounded paid packets covered exact settlement, ordered tools, four-way
  coordination, Stop/recovery, and Dark appearance for 358,637 parent tokens.
  Coordination passed; final-only wording remains honestly partial where the
  agent emitted progress prose first.
- Exact Close Session removed all five parent tabs/backends; eight validated
  child directories were moved recoverably to the P3D Trash receipt. Marker
  files are zero and protected OK-F remains.
- Required **Test and Build App** passed on exact head `34e9520`; PR #107 merged
  as `1e11be2`. Merged-main `make ship` passed 897/897, and fresh installed UI
  proof reported `Personal • main @ 1e11be22` in the full Dark workbench.

---

## Screenshot review → possible next implementation

Jimmy attached a **six-phase roadmap** (cool tokens → quiet welcome → header/composer → accent → cheap size → optional extract). Use it as the product north star, but implement from **`docs/GROKBUILD_VISUAL_QUIET_CAMPAIGN_2026-08-15.md`**, which reflects redirects and file ownership.

### Immediate next work (recommended order)

**A. Phase 4 — Accent-leak sweep** *(proposed next; wait for explicit start)*
- Grep and replace `Color.accentColor`, raw `.orange`, unscoped `.borderedProminent`.
- Route through `AppTheme.Palette.accent`, `Palette.warning`, `Palette.link`.
- High-traffic files listed in campaign doc § Phase 4.
- Billable: `GB-VQ-P4-<UTC>` → `GB_VQ_P4_OK` in Light **and** Dark.

**B. Phase 5 — Cheap bundle lightening**
- Real AppIcon asset; drop duplicate PNGs.
- Delete unused `workflowsStatusPill` (defined, never mounted).
- Keep bundled `agent-desktop`.

**C. Phase 6 — Optional welcome extract**
- Move quiet welcome stack to its own view file only.
- **Not** the full leftover `ChatView` decomposition.

### Jimmy feedback already baked into `bb01c58`

- Dark titlebar icons were invisible → `TitlebarGlyph` + white fill.
- Header controls too high / inconsistent → `TitlebarMetrics.contentTopInset`, no negative offset into traffic-light row.
- Filter/Bell collided with session title → moved to header right with spacer gap.

### Hard stops (every phase)

- Do **not** touch `ChatStore`, ACP, `GrokProcess`, provider routing, or unbundle `agent-desktop`.
- Do **not** start leftover `ChatView` split unless Jimmy explicitly authorizes.
- Computer Use on **`/Applications/GrokBuild.app` only** for campaign acceptance.
- One phase → one branch → one PR → merge before the next slice.
- Protected sessions: OK-F tab and Aug 14 `(no summary)` `019ffdad-0d4f-7f42-a429-7ac12ad8198d` — never Clear Empty.

---

## Key files for the next editor

| Area | Files |
|---|---|
| Theme / titlebar glyphs | `GrokBuild/AppTheme.swift` |
| Titlebar metrics | `GrokBuild/MainWindowLayout.swift` |
| Overlay + filter state | `GrokBuild/ContentView.swift` |
| Header layout | `GrokBuild/Views/ChatTopBar.swift` |
| Sidebar overlay | `GrokBuild/Views/SidebarView.swift` |
| Inspector / launch / task strip | `GrokBuild/Views/ChatView.swift` |
| Worker activity canvas | `GrokBuild/Views/ActivitySidebar.swift` |
| Inspector projection | `GrokBuild/Models/ContextInspectorProjection.swift` |
| Parity tests | `Tests/GrokBuildTests/CodexShellParityTests.swift` |

---

## Verification checklist (definition of done)

- [ ] `make test` passes; extend tests for any behavior you change
- [ ] `make ship` → `/Applications/GrokBuild.app` with stamp == HEAD, `dirty=false` on committed build
- [ ] Computer Use snapshot/click proof on installed app
- [ ] Billable packet + Gate F cleanup when closing a product phase
- [ ] Update `ARCHITECTURE.md` / `README.md` / campaign ledger as needed

---

## One-line prompt for Codex

> Read `docs/GROKBUILD_CODEX_HANDOFF_2026-08-15.md` and `docs/GROKBUILD_VISUAL_QUIET_CAMPAIGN_2026-08-15.md`. P1–P3, P3C, and P3D are accepted and P3D is merged as `1e11be2` in PR #107. Phase 4 is proposed next, but do not start it without Jimmy's explicit authorization. Icon work, Settings redesign, provider/backend changes, and broad structural work remain out of scope.
