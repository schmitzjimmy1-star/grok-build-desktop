# GrokBuild residual closeout — 2026-08-14

Status: **Phase 2 complete pending merge**, driven from shipped `fa44cb25`.
Phase 3 is the only next action after this PR merges.
Jimmy authorized this campaign on 2026-08-14 after Slice 7 closed, including
billable prompts in every phase that needs them. True closeout means installed
proof, exact cleanup, and process-zero, not a green unit suite.

This follows Gates A–H in [`docs/OUTSTANDING.md`](OUTSTANDING.md) and the
identity stop in [`CANONICAL_WORKTREE.md`](../CANONICAL_WORKTREE.md). The
2026-08-13 campaign (Slices 0–7) is closed at merge `c0895eef092427d332c9c12eb4ed8211a1564626`
(PR #86) with installed stamp ancestor `150fbbe858a1c11f9447441bcbe717a88e59975b`.
Do not rerun those packets or reuse their markers.

## What this closes

These are the leftovers named after Slice 7, grouped so each phase has one job.

| Leftover | Close by | Not a fix |
|---|---|---|
| Installed stamp `150fbbe8` behind `main` `c0895ee` | Phase 0 `make ship` | Shipping docs-only code was forbidden then; this phase is the authorized identity close |
| Light appearance never photographed | Phase 1 signed Light shots | Do not fake Light by recoloring a Dark PNG |
| Composer AX is `Message composer`; visible placeholder is **Describe a task** | Phase 1 thin AX plus README | Do not rename `grok-message-composer` |
| Cursor Computer Use MCP was not loaded | Phase 2 | `agent-desktop` remains the fallback, not a failure |
| First-turn native Grok 4.6 sits near 148k tokens | Phase 1 ceiling, not a bug | Do not treat 100k as a fail |
| Unindexed child histories survive `grok sessions delete` | Phase 3 residual receipt | No GrokBuild scraper |
| Search-index / `prompt_history.jsonl` residue | Phase 3 classify-only | Do not edit those files |
| Leftover test threads still visible in Sessions | Phase 3 exact IDs only | User conversations stay protected |
| grok **1.0.4** advertised, **1.0.3** installed | Phase 4 | Config hash will change; ledger it |
| `ChatStore` / `ChatView` / `GrokProcess` / `ContentView` still huge | Phase 5 remaining pins only | Do not rewrite those files |
| No notarized personal release | Phase 6 | `origin` stays fetch-only |

## Hard stops (every phase)

- Canonical worktree only:
  `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- `personal` = `schmitzjimmy1-star/grok-build-desktop`. `origin` = `rimusz/grok-build-desktop`, fetch only.
- No force push, no branch deletion, no tags except the one Phase 6 release tag, no writes to `origin`.
- No retired `/Users/jimmyschmitz/Documents/Grok Builf` line.
- No app-side ACP, MCP runtime, provider fallback, or scheduler daemon.
- No **Clear Empty**. No delete-by-age, summary, or glob.
- Never delete user conversations, including `GB_MAIN_*`, VISUAL PASS, Reply-with-exact
  markers, Jimmy Codebase Query, weather, and any unnamed session that is not
  proven as a leftover test thread in that phase's inventory.
- Do not scrape or rewrite `~/.grok/sessions`, `session_search.sqlite`, or
  `prompt_history.jsonl`.
- Do not print secrets. Phase 4 may record the config file hash, size, and mode only.
- Computer Use preference: Cursor `user-grokbuild-computer-use` MCP, then
  `agent-desktop`, then Orca. Installed proof is `/Applications/GrokBuild.app` only.

## Publication

Each phase is one branch, one PR to `personal` `main`, required **Test and Build App**,
normal merge, then the phase's installed proof. Phase 0 and Phase 6 also `make ship`
after merge. Phase 5 may use multiple tiny PRs if a pin replacement splits cleanly;
never mix pin work with CLI, release, or appearance work.

Jimmy authorized billable prompts for this campaign. Every phase that can affect
live chrome, CLI identity, or updater behavior must run its frozen packet, not
skip it because the diff looks small.

## Marker and packet rules

```text
GB-C8-P<phase>-<PURPOSE>-<YYYYMMDDTHHMMSSZ>
```

New UTC run ID per packet. No Slice 6/7 markers, no `20260815T041847Z`, no
`20260815T033736Z`. One parent turn unless the phase table says otherwise.
Stop without retry if a required receipt is missing.

Native default is inherited New chat `grok-4.6` through the Grok CLI, launch
`--reasoning-effort low`, unless a phase names another lane. Record exact
model, route, process generation, local tab UUID, parent backend, child IDs,
tools, tokens, calls, and cost.

Suggested anomaly ceilings are stuck-run breakers. A fresh native Grok 4.6
first turn in the ~148k band is expected, not a defect.

## Checkpoint handoff

Every checkpoint ends with exactly three copy/paste sentences: identity and
result; live app/backend/process/usage/cleanup/risk (`none` if empty); one next
action plus hard stop. If work stops mid-phase, the same three sentences say
**incomplete**.

---

## Phase 0 — identity ship

**Purpose:** make the installed product and merged `main` name the same commit.

**Why this is first:** later Light shots, MCP proof, CLI probes, and a release
are worthless if Settings → App still points at `150fbbe8` while git is
`c0895ee` or later.

### Scope

- Re-derive Gate A live. Start from clean `main == personal/main`.
- Commit and merge this spec plus the ledger pointer if they are not already on
  `main` (docs-only PR, then ship the merge).
- `make test`, then `make ship` from that merged `main`.
- Prove stamp == HEAD, `dirty=false`, dist/installed SHA-256 match,
  Team `DD2GCQJVB4`, deep/strict, no quarantine.
- Settings → App must show `Personal • main @ <HEAD-8>` and the personal repo URL.
- Two process-zero samples after quit.

### Billable

None required. Ceiling: **0 tokens**. Do not send a chat prompt.

### Exit

Installed executable hash is new or proven identical-plus-stamp. Product diff
from the previous shipped ancestor is empty except `Info.plist` identity keys
written by `scripts/build-identity.sh`. Phase 1 may start only after this
receipt is in `OUTSTANDING.md`.

---

## Phase 1 — Light evidence and composer AX

**Purpose:** finish the public first impression Slice 7 left on the table.

### Scope

- Record the current Settings → App appearance, then Apply **Light**. Restore
  the prior appearance after shots. This is app appearance, not `~/.grok/config.toml`.
- Replace or add signed-installed Light screenshots:
  - `docs/images/grokbuild-app-light.png` — New chat, Ask/Build/Review,
    **Describe a task** visible, sidebar shown.
  - `docs/images/grokbuild-run-inspector-light.png` — settled docked inspector
    after the frozen packet below.
- Keep the existing Dark images. README first screenful shows Dark and Light
  and states the AX contract.
- Thin composer AX in `GrokBuild/Views/ChatComposer.swift`: keep identifier
  `grok-message-composer` and label **Message composer**. When the field is
  empty, accessibility value must include **Describe a task** (replace today's
  empty value `Empty`). Add or extend a focused test. Do not change send
  behavior.

### Frozen packet

One native parent turn only. Suggested ceiling: **200k** actual tokens.

| Field | Frozen value |
|---|---|
| Purpose | Populate Light inspector with the same shape Slice 7 showed in Dark |
| Tools | sequential `/bin/echo ALPHA`, `BETA`, `GAMMA`; two concurrent children echoing `LEFT` / `RIGHT`; one `wait_all` |
| Forbidden | `update_plan`, search/web, browser, Computer Use, write/edit, git, retries |
| Reply | exact `GB-C8-P1-…-PARENT ALPHA\|BETA\|GAMMA LEFT+RIGHT` |

Drive `/Applications/GrokBuild.app` after the Phase 0 ship. Prefer the Phase 2
MCP if that phase already landed; otherwise `agent-desktop` is allowed and
must be named in the receipt.

### Exit

Both Light images are from the signed installed app. AX tree shows **Session
dashboard**, **Run inspector**, **Message composer** with empty value containing
**Describe a task**, and **What do you want to work on?** Appearance is restored.
Exact test tab/backends cleaned under Gate F. Process-zero.

---

## Phase 2 — Cursor Computer Use MCP path

**Purpose:** stop treating the missing Cursor MCP as an undocumented surprise.

### Scope

- Discover whether `user-grokbuild-computer-use` is registered in this Cursor
  session. If it is not, install or enable it from the bundled helper docs
  without editing Claude Desktop or Codex config.
- Prove `snapshot` against `/Applications/GrokBuild.app` and that the running
  executable is `/Applications/GrokBuild.app/Contents/MacOS/GrokBuild`.
- Record the working verb set. If Cursor gating blocks a verb, name it and use
  `agent-desktop` for that verb only.
- If the MCP cannot be enabled, the phase still closes: write the blocked
  reason, keep the preference order, and do not invent a second Computer Use
  stack.

### Frozen packet

One native no-tool marker turn, same inherited `grok-4.6` route. Suggested
ceiling: **200k**. Reply exactly the phase marker. This packet exists to prove
the MCP can reach New chat, type, Send, and read the settled transcript, not
to exercise tools.

If Phase 1 already drove the Light packet through the MCP, reuse that receipt
and skip a second prompt.

### Exit

A later phase may call the MCP first. Fallback remains legal. Process-zero.

---

## Phase 3 — leftover test-thread hygiene

**Purpose:** remove only leftover test history, and close the child-delete gap
as a CLI residual instead of a fake GrokBuild feature.

### Scope

Live-inventory first. Do not use remembered IDs from chat.

Protect every user conversation. The protected set includes at least
`GB_MAIN_*`, VISUAL PASS, Reply-with-exact `GB_*` diagnostics, Jimmy Codebase
Query, New Buffalo weather, and any session whose summary is ordinary user
work.

Candidates for deletion must be proven leftover test threads: Slice 6/7
markers, Chrome DevTools list_pages probes, unnamed `(no summary)` rows whose
chat history is an exact leftover packet, or backends created by this
campaign. If the ID cannot be proven, keep it.

Cleanup order is Gate F. For unindexed `session_kind=subagent` directories
that `grok sessions delete` reports missing: prove non-symlink, canonical cwd,
and exact ledgered ID, then move only those directories to a dated
`~/.Trash/GrokBuild-C8-P3-child-backends-<UTC>` bundle.

Search `GB-C8-*`, `GB-S7-VIS-*`, and `GB-S6-*` in live transcript and backend
stores after cleanup. `prompt_history.jsonl` and `session_search.sqlite`
residue is expected. Do not edit them. Do not use **Clear Empty**.

Write the residual in `OUTSTANDING.md`: current grok CLI does not expose
spawned child histories to `sessions delete`. Automatic cleanup is rejected.

### Billable

None required unless inventory cannot classify a row without opening it. If a
prompt is required, it is a no-tool "reply exactly this marker and stop"
packet, ceiling **200k**, then that exact thread is deleted.

### Exit

Live leftover test IDs are absent. User sessions remain. CLI residual is
ledgered. Process-zero.

---

## Phase 4 — grok CLI 1.0.4

**Purpose:** take the advertised CLI update that Slice 7 was forbidden to touch.

### Scope

- Record pre-update: `grok --version`, config SHA-256 / bytes / mode `0600`,
  Settings → App CLI line.
- Update only through the official grok update path. Do not hand-edit
  `~/.grok/config.toml` except what that updater writes.
- After update, re-hash the config. Ledger the new hash. Diff key names only.
  Stop if unexpected provider, credential, or MCP stanzas appear.
- Settings → App must show Installed **1.0.4** (or the exact version the
  updater actually installed). If the updater lands a later patch, record that
  version and do not downgrade.
- `make test` still passes against the same app. No GrokBuild source change
  unless a test fixture pins `1.0.3` and must accept `1.0.4`.

### Frozen packet

One native no-tool marker after the update, inherited `grok-4.6`. Suggested
ceiling: **200k**. Prove live model, `Route: native xAI through the Grok CLI.`,
and process generation 1. No second route unless the first packet fails for a
CLI-identity reason; then stop and report, do not invent OpenRouter fallback.

### Exit

CLI version, config hash, and the marker receipt agree. Exact thread cleaned.
Process-zero. Later phases use this CLI.

---

## Phase 5 — remaining coordination-density pins

**Purpose:** finish the Slice 6 leftover that is actually closable: brittle
source-string pins for contracts already extracted. Not a ChatStore rewrite.

### Scope

- Inventory `Tests/GrokBuildTests/ACPClientContractTests.swift` methods that
  `String(contentsOf:)` `ChatStore.swift`, `ContentView.swift`, `ChatView.swift`,
  or `GrokChatChrome.swift`.
- Replace pins that now have a typed owner (`BackgroundTaskTracker`,
  `SessionRuntimeRetentionPolicy`, `RunHistory`, composer/top-bar types) with
  compile-time or behavior tests.
- Keep a few deliberate architecture tripwires. Do not add a second reducer,
  LRU policy, or export type.
- Do not change product copy, persistence schema, launch argv, or provider
  routing.
- File-size vanity is out of scope. `ChatStore` may stay large.

### Frozen packet

One native agentic smoke, same shape as Slice 6's accepted packet: three
ordered terminal echoes, two concurrent read-only children, one follow-up
turn, one deliberate Stop. Suggested ceiling: **250k**. New run ID. Prove no
receipt drift versus the Slice 6 closeout shape (ordered tools, two children,
`wait_all`, `userStopped`).

### Exit

Focused pin tests plus `make test`, `make ship`, installed Computer Use of the
packet, exact cleanup, process-zero. If the smoke exposes another layout loop,
stop the line and repair that loop before Phase 6.

---

## Phase 6 — personal notarized release

**Purpose:** publish one updater-visible release on Jimmy's fork so
"no release" is no longer an open leftover.

### Scope

- Bump `VERSION` from `0.1.20` to `0.1.21`. Version is not repository identity;
  the stamp is. About and Settings must show `0.1.21` after ship.
- Follow `.cursor/skills/grokbuild-release/SKILL.md`: personal target only,
  `make test`, docs for install/updates, then
  `make release RELEASE_TYPE=notarized` (or the current equivalent).
- Tag `v0.1.21` on the merged personal `main` only. No tag on `origin`.
- UpdateChecker must see the notarized release (title or notes include
  notarization). Unsigned releases do not count.
- Post-merge `make ship` so stamp == HEAD == the release commit.
- One installed Check Now (or equivalent) receipt that the new version is
  current. Do not click through an unrelated CLI upgrade here; Phase 4 already
  owns the CLI.

### Billable

One no-tool native marker after the shipped `0.1.21` build, ceiling **200k**,
only to prove the released binary still launches a native turn. If Phase 5's
shipped binary is the same commit that Phase 6 tags, reuse that packet and
skip a second prompt.

### Exit

Personal release published, updater-visible, installed stamp == tagged commit,
exact thread cleaned, process-zero. `origin` unchanged. Campaign complete.

---

## Ideas still rejected

- Reimplementing ACP, MCP execution, memory, skills, plan mode, or subagents.
- App-side provider fallback or claiming OpenRouter's downstream provider.
- A daemon or LaunchAgent to keep `/loop` alive.
- Persisting raw prompts, responses, credentials, or chain-of-thought.
- Auto-running matrices because a model exists.
- Treating `0.1.20` / `0.1.21` as repository identity.
- Pushing this campaign to `rimusz/grok-build-desktop`.
- Deleting historical user sessions to make Sessions look tidy.

## Current authorized phase

Execute **Phase 3 only** after Phase 2 merges. Re-derive identity live from
installed `fa44cb25` (do not `make ship` Phase 1 or 2 to chase stamp == HEAD).
Phase 2 proved Cursor `user-grokbuild-computer-use` against `/Applications/GrokBuild.app`
and recorded the host split versus grok's in-session `grokbuild-computer-use`.
Do not start Phase 4–6. End every checkpoint with the three-sentence handoff.
