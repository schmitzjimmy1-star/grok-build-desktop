# GrokBuild leftover closeout — 2026-08-15

Status: **Phases 1–2 complete, awaiting merge.** Phase 3 (`ChatView` split)
stays deferred. Phase 4 waits for a new campaign.

This is the leftover list after three senior-engineer audits of the personal
line. It exists so we can finish what we actually wanted without treating
closed campaigns as open work.

Auditors: [dead-code](956b07cf-dc7e-4c26-8552-cbee3c39415a),
[leftover-slices](f0e44471-4b66-46e1-96a0-e1f2186fcd7d),
[identity-poison](0ebadb89-c284-45bd-92f4-7aa430c8de53).

## What is already done

| Campaign | Status |
|---|---|
| 2026-08-13 verification slices 0–7 | Closed |
| 2026-08-14 residual closeout C8 phases 0–6 | Closed |
| 2026-08-15 Agentic Cockpit C9 phases 1, 3, 4 | Closed |
| Personal notarized `v0.1.22` | **Not outstanding.** Install with `make ship` under Apple Development. |

Do not conflate C8 Phase 4 (CLI 1.0.4) with C9 Phase 4 (OpenRouter probe).

## Every leftover, grouped

### Phase 1 — Ledger truth, dead stub, notarize-doc poison (complete)

Safe cleanup. No `ChatView` split. No updater retarget. No origin writes.
No `make ship` just to chase a docs-only HEAD after this phase merges.

| Leftover | Action |
|---|---|
| Empty `GrokBuild/Models/Agent.swift` placeholder | Delete. Assert it stays gone. |
| `OUTSTANDING.md` still titled Authorized & Planned | Point at this spec. C9 closed except deferred ChatView. |
| `docs/AGENTIC_ROADMAP.md` says nothing is implemented | Historical banner. File refs already shipped. |
| `docs/archive/README.md` says the app was retired | Superseded banner. App is active. |
| `docs/FRONTEND_BACKEND_PARITY_REPAIR_SLICES_2026-08-02.md` `ready for scoped execution` | Mark historical. |
| `docs/UI_ACCEPTANCE_MATRIX.md` “Installed today” still shows sidebar Activity/Agents | Label that column pre–Slice-1 baseline. |
| `BUILDING.md` mid-file notarize / GitHub `(Notarized)` instructions | Personal line: `make ship` only. |
| `.github/workflows/README.md` “required for in-app updates” | Personal line does not dispatch notarized releases. |
| `.cursor/rules/grok-cli-integration.mdc` UpdateChecker = notarized app | App feed off. Install with `make ship`. |
| `AGENTS.md` stamp == HEAD with no docs-only carve-out | Do not ship docs-only merges just to chase stamp. |
| `README.md` grok 1.0.3 + zip/dmg as the install story | CLI 1.0.4. Install with `make ship`. |
| `Makefile` `dmg` still calls `notarize` when `NOTARY_PROFILE` is set | Never notarize. Always package the DMG. |
| `scripts/release.sh` unsigned notes tell people to notarize | Remove that CTA. |

Billable packet: new chat only. Marker `GB-LEFTOVER-P1-<UTC>`. Prompt:
`Acceptance packet. This is a no-tool check. Do not use tools, workers, or
update_plan. Reply with exactly GB_LEFTOVER_P1_OK and stop.` Ceiling 200k.
Gate F deletes only that exact session. Leave protected `OK-F` and Aug 14
`(no summary)` `019ffdad-0d4f-7f42-a429-7ac12ad8198d` alone.

Exit: `make test`, candidate `make ship` (`dirty=true` until commit), Computer
Use Settings → App, one billable no-tool marker, Gate F. Jimmy confirmed
2026-08-15 and authorized Phase 2 plus commit/push/merge.

### Phase 2 — Process hygiene (complete, no product UI)

| Leftover | Action |
|---|---|
| `release.yml` still dispatchable, default `notarized` | Default `unsigned`. Personal fork refuses `notarized`. |
| Stale personal feature branches (`codex/grokbuild-c9-p4-routing`, etc.) | Deleted from `personal` after Jimmy authorized Phase 2. |
| Local git tags `v0.1.21` / `v0.1.22` tracking rimusz | Local `git tag -d` only. Origin tags untouched. |
| Branch-protection pin for **Test and Build App** | Live-checked 2026-08-15. Still pinned. No waiver. |
| `CANONICAL_WORKTREE.md` frozen PR #1 / #2 | Replaced with merged PR history. |

### Phase 3 — ChatView decomposition (only if re-authorized)

This is the only remaining **product** slice from C9. Jimmy skipped it once.

Extract `TopBarView.swift`, `ComposerBarView.swift`, and `WelcomeStateView.swift`
from `ChatView.swift`. Preserve AX ids and source-contract tests. No visual
redesign.

### Phase 4 — Optional architecture (out of scope unless a new campaign)

`ChatStore` / `GrokProcess` / `ContentView` splits, `BoundedProcess` DRY,
searchable model picker, generic OAuth/ACP backends, persistent `/loop`
LaunchAgent. Prior campaigns deferred or rejected these.

## What we will not treat as leftovers

- Historical receipts inside `OUTSTANDING.md`
- `UpdateChecker` / updater stack (CLI updates are live; app feed is off)
- `scripts/notarize.sh` (kept for upstream/CI parity; `make notarize` refuses)
- Legacy session-layout and config migrations
- Bundled browser / Computer Use skills
- Standing contracts B-1–C-4 and the grok CLI child-session visibility gap
- Installed stamp `b9bf633` vs later docs-only HEAD (expected until a code ship)

## Hard stops

Canonical worktree only. `personal` only. No force push. No origin writes.
No notarized GitHub release. No ChatView split in Phase 1. No updater
retarget. Computer Use against `/Applications/GrokBuild.app` only.
