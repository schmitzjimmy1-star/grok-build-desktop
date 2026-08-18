# Fable 5 Lightweight Decisions — GrokBuild

> July 31, 2026 · branch `codex/warm-glass-ui` @ `ac31979` (dirty worktree).
> Evidence in `FABLE_5_AUDIT_FINDINGS.md` (finding IDs F1–F22); execution order in
> `FABLE_5_IMPLEMENTATION_PLAN.md`.

The bar used throughout: a change must measurably improve ownership, correctness,
security, startup/resource behavior, interaction reliability, or maintenance cost.
Deleting lines, splitting files, or adopting frameworks scores zero by itself.

## 1. Verdict in one paragraph

At the time of this July audit, GrokBuild was a 16 MB arm64 SwiftUI shell with **zero
third-party dependencies**, Apple-only frameworks each mapped to a reachable feature, one
serialized TOML boundary, Keychain-held credentials, and Grok owning the agent runtime
through ordinary ACP. There is no second runtime, no embedded browser engine, no resident
helper. The audit found no performative-lightweight work worth doing on bundle bytes; the
real weight problems are *behavioral* — retained closed-session objects (F3), context-
dropping coarse reloads (F4), unbounded subprocess waits (F9/F10/F11/F17), and main-thread
I/O (F13). Fix those; leave the architecture alone.

## 2. Component decisions

| Component | Bytes / cost | Decision | Reason / trigger to revisit |
|---|---|---|---|
| Main SwiftUI app | 13.7 MB | **Keep** | Release-built, symbol-stripped-enough, no debug resources ship |
| `GrokBuildComputerUseCore` | (static lib) | **Keep** | Test seam + shared contract; delete only if Computer Use exits the product |
| `GrokBuildComputerUseMCP` | 196 KB | **Keep** | Correct isolation: per-call actuator spawn, pipe drain, SIGTERM→SIGKILL |
| Bundled `agent-desktop` | 2.25 MB | **Keep** | One canonical owner (`ComputerUseService`), packaging hard-requires it, version-smoked at build |
| Browser MCP bridge script | 5.5 KB | **Keep** | Reachable, registered per-session, tiny |
| Skill `grokbuild-browser-control` | 2.7 KB | **Keep** | Installed by `BrowserSkillInstaller` when enabled |
| Skill `grokbuild-grok-web` | 3.4 KB | **Keep** | Same installer, same gate |
| Skill `grokbuild-computer-use` | 3.0 KB | **Keep** | Installed by `ComputerUseSkillInstaller`; SKILL.md drift-guarded by tests |
| Skill `grokbuild-desktop` | 1.0 KB | **Delete (recommended, needs Jimmy's OK)** | Zero references in Swift source; never installed, never looked up (F18). If it has an intended future consumer, document the owner instead — limbo is the worst option |
| Update installer helper | 1.8 KB | **Keep + Fix** | Flow is right (wait-PID → swap → relaunch); fix merge-copy/quarantine/self-overwrite (F7) and TeamID skip (F6) |
| App icon / menu-bar PNGs | 309 KB | **Keep** | No duplicate payloads found |
| SwiftPM third-party deps | 1 as of Official Runtime Alignment Slice 4 | **Exact-revision exception: `swift-toml`** | Foundation has no TOML 1.0 parser; valid official nested/quoted/partial Grok config proved the handwritten detector could corrupt bytes. The parser validates only; targeted rewriting and CLI runtime ownership remain unchanged. See `ARCHITECTURE.md` and `THIRD_PARTY_NOTICES.md`. |
| WebKit linkage | — | **Keep** | Reachable via `PreviewPane` (product feature), not stray |
| Speech/AVFAudio linkage | — | **Keep** | `VoiceInputService` is lazy and permission-gated |
| `GitService` + PR flow | — | **Keep + Fix** | Deliberate product feature behind explicit clicks; fix pipe deadlock (F10); `git add -A` bluntness is a product choice to revisit, not dead code |
| Updater stack (Scheduler/Checker/AppUpdater/Panel) | ~1.4 K LoC | **Keep + Fix** | In-app updates are a core product promise (notarized-only, verified); fix F6/F7/F13/F20 |
| `ComputerUseCursorInstaller` | — | **Keep** | User-initiated only, merge-preserving edits of `~/.cursor/mcp.json`, symmetric uninstall |
| Dual build pipeline (SPM resources + script copies) | — | **Keep as-is, document** | No double-ship in artifacts; SPM copies serve `swift test`. Unifying is churn without measurable gain |
| Large view files (`SettingsView` 5.4 K, `ChatView` 2 K, `ContentView` 1.4 K) | — | **Fix selectively, not by line count** | Only the three seams that carry behavior: Models pane persistence → its view model (makes F16 testable); status-pill cluster → injected values (kills per-render disk I/O, F13); shared scaffold for the six CLI panes (fixes F15 once). Everything else: leave |
| `NotificationCenter` usage (18 names) | — | **Keep** | Inventory showed symmetric teardown, no leaks; typed replacement is stylistic — deferred |
| Cross-process TOML locking | — | **Defer** | Still no reproduced GrokBuild↔CLI collision; in-process serialization + atomic rename is proven |

## 3. Weight and resource consequences (measured)

- Bundle: unchanged by this run (+1 source file compiles into the existing binary; test
  code ships nowhere). No payload over 100 KB lacks an owner. Only reclaimable dev disk:
  `.build/` 815 MB (rebuildable; delete only on request).
- Idle behavior: app not running at baseline; no listeners, no timers in source, update
  check every 24 h is the only periodic work. The measurable idle-RSS win available is
  F3 (closed sessions retained) — behavioral, not bytes.
- The slice implemented this run adds: 1 request-time guard, 1 per-fetch redirect
  delegate (allocated per catalog check, no resident state), 2 enum cases. Cost ≈ zero;
  removes an entire credential-exfiltration class.

## 4. OpenRouter / OAuth decision

**Approve OpenRouter as a small optional provider adapter — API-key path first, then
one-click OAuth — with zero new dependencies.** Current OpenRouter documentation
(fetched live this run) confirms the flow is unusually native-friendly:

- `https://openrouter.ai/auth?callback_url=…&code_challenge=…&code_challenge_method=S256`,
  loopback callbacks supported on any port, no app registration required.
- Code exchange at `POST https://openrouter.ai/api/v1/auth/keys` returns a
  **user-controlled API key** — not an access/refresh token pair. No refresh machinery,
  no token rotation, no expiry bookkeeping.

Consequences for the plan already written in `OAUTH_OPENROUTER_ACP_PLAN.md`:

1. The credential envelope needs `oauthIssuedKey` but **not** a refresh-token state
   machine for OpenRouter. Keep `oauthTokenSet` in the model for future providers; build
   nothing that uses it yet.
2. The loopback listener can be exactly what the plan specifies: ephemeral, random path,
   single callback, bounded timeout, S256 (send it even though OpenRouter marks it
   optional-but-recommended — plain would be a needless downgrade).
3. "Disconnect locally" deletes the Keychain entry + TOML projection; remote revocation
   stays a dashboard action (document this in the card; key-management API is not part of
   the documented flow).
4. Endpoint policy and keyless-auth preservation were prerequisites — **landed this run**.
   Remaining prerequisite: credential metadata envelope (slice 4).
5. Gates unchanged: opt-in, "via OpenRouter" labeling everywhere, no silent fallback,
   catalog-success ≠ working (CLI `Reply OK` smoke required, explicitly authorized,
   billable).

Value over the working direct OpenAI/Kimi paths: catalog breadth behind one credential
and one-click setup — worth an adapter, not a runtime. Rejected: any OpenRouter Swift
SDK (native URLSession suffices; `dependencies: []` holds).

## 5. ACP / Goose decision

**Keep Grok as the only wired backend now; approve a bounded Goose spike later — the
audit removed the main unknown.** Evidence (F-ledger §2): `GrokProcess` speaks standard
ACP for everything load-bearing; the xAI-specific surface is a short enumerable list
(`x.ai/exit_plan_mode`, `x.ai/ask_user_question`, `_meta.isReplay`/`totalTokens`/
`model.Ok`, FS_NOT_FOUND fallback, CLI arg vector, slash-command reliance, tool-name
sniffing for scheduler/workflow pills). Nothing outside `GrokProcess`/`ChatStore` assumes
Grok internals; sessions already bind one-store-one-process.

Spike preconditions (unchanged from the plan doc, now concrete): extract
`ACPProcess` + `AgentBackendDescriptor` seams *without* moving behavior; the spike must
consume initialize capabilities/authMethods instead of ignoring them (fixes the
string-sniffed auth detection as a side benefit); backend-namespaced session IDs;
no second SDK in the app target. Success = fixture-driven compatibility evidence;
failure = write down why Grok stays exclusive. Do not schedule before the F3/F4
lifecycle fixes — a second backend multiplies any session-lifecycle bug.

## 6. Rejected alternatives (with reasons)

| Alternative | Rejected because |
|---|---|
| Embedding Cursor harness / OpenAI Agents SDK / Claude Agent SDK / OpenHands / Node orchestration | Duplicates Grok's ownership; adds a second runtime to a 16 MB shell; violates the product invariant |
| OpenRouter Swift SDK | Flow is 2 endpoints + PKCE; URLSession/CryptoKit cover it; would break `dependencies: []` |
| Generic OAuth issuer platform / OpenAuth server | One real provider (OpenRouter) with a key-issuing flow doesn't justify an issuer engine; two providers with proven need can reopen |
| Background daemon / menu-bar keeper for Dock persistence | Already solved by OS pinning + stable identity (verified live); a resident process is the exact anti-goal |
| In-app Mac cleaner | Storage report shows 2.6 MB of app cache — there is nothing to clean that isn't durable user data or CLI-owned |
| Splitting `SettingsView`/`ChatView` by line count | Only the three behavior-carrying seams pay for themselves; the rest is churn against a dirty worktree |
| Replacing NotificationCenter wholesale | Audit found symmetric teardown and no leaks; stylistic |
| Cross-process TOML lock | No reproduced collision; complexity without evidence |
| Universal (x86_64) builds | macOS 26 minimum makes Intel moot; arm64-only is the right default (worth one line in BUILDING.md) |
| Stripping/dSYM pipeline changes | dSYMs already don't ship; symbol stripping would degrade crash triage for ~nothing (binary is 13.7 MB) |
| Deleting `.build`/caches during audit | Destructive; not authorized; reported instead |
