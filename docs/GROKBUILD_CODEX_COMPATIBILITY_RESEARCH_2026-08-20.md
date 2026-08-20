# OpenAI Codex compatibility research — 2026-08-20

## Decision

Use OpenAI Codex as a public, licensed reference for presentation models and
client-state discipline. Do not embed or launch Codex, adopt its app-server as a
second control plane, or make GrokBuild speak Codex JSON-RPC. GrokBuild remains a
native SwiftUI client whose only agent protocol is Grok CLI ACP.

The Codex desktop interface shown in Jimmy's 2026-08-20 screenshot is a visual
composition reference only. The inspected `openai/codex` repository contains no
Swift implementation of that desktop shell. Its public TUI and protocol sources
can inform behavior, but they are not the screenshot's reusable macOS views or
assets.

## Inspected upstream

Repository snapshot: [`openai/codex` at `7ea7b293`](https://github.com/openai/codex/tree/7ea7b293696473a12ea48701e8f638fa6bb2aed0).

- [`codex-rs/app-server/README.md`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/app-server/README.md)
  defines the thread, turn, and item lifecycle, streamed notifications,
  projects, sections, approvals, plans, diffs, and generated schemas.
- [`Thread.ts`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts),
  [`Turn.ts`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/app-server-protocol/schema/typescript/v2/Turn.ts), and
  [`ThreadSection.ts`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/app-server-protocol/schema/typescript/v2/ThreadSection.ts)
  expose compact client-facing projections rather than UI-owned runtime state.
- [`ServerRequest.ts`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/app-server-protocol/schema/typescript/ServerRequest.ts)
  keeps approvals and user-input requests as explicit server-to-client requests.
- Codex TUI splits composer concerns into
  [`draft_state.rs`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/tui/src/bottom_pane/chat_composer/draft_state.rs),
  [`attachment_state.rs`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/tui/src/bottom_pane/chat_composer/attachment_state.rs), and
  [`footer_state.rs`](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/codex-rs/tui/src/bottom_pane/chat_composer/footer_state.rs).
- The repository is [Apache-2.0](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/LICENSE)
  and carries a [NOTICE](https://github.com/openai/codex/blob/7ea7b293696473a12ea48701e8f638fa6bb2aed0/NOTICE).
  Any future direct code reuse must retain the applicable license, modification,
  copyright, and notice obligations. This campaign currently copies no source.

## Compatibility map

| Codex public concept | GrokBuild source of truth | Safe adoption |
|---|---|---|
| Thread | `ChatStore` tab plus `SessionLayoutStore` and exact ACP session binding | Rail grouping, preview, recency, current status, project membership |
| Turn | One generation-bound prompt lifecycle in `ChatStore` | Started/running/failed/completed presentation and settled boundaries |
| Item | Existing `Message`, tool-call, plan, question, permission, and usage projections | A typed presentation enum only if a bounded F4 extraction needs it |
| `thread/list` and sections | Existing workspace/project/session stores | Pinned, Projects, and Recents sections with honest local ordering |
| `turn/plan/updated` | ACP `session/update` plan entries | Reuse the existing plan spine; do not synthesize steps |
| `turn/diff/updated` | Existing Git generation recording and changed-files projections | Coherent Review chip and diff disclosure; preserve attribution caveats |
| Approval server requests | ACP `session/request_permission` and existing `PermissionRequest` | Codex-style approval card hierarchy; answer only the ACP request |
| Composer draft, attachment, footer state | Existing composer bindings, context owners, settings, voice, and send path | Visually separate concerns without creating another store or send command |
| Project/worktree metadata | `WorkspaceStore`, `GitService`, and current branch receipts | Chips and rail context; no Codex project database or worktree mutation layer |

Codex app-server methods are not aliases for ACP methods. The presentation-only
translation is:

```text
Codex thread                 -> GrokBuild tab + Grok ACP session binding
Codex turn                   -> Grok ACP session/prompt generation
Codex item notifications     -> Grok ACP session/update projections
Codex approval request       -> Grok ACP session/request_permission
Codex interrupt              -> Grok ACP session/cancel
Codex project/section state  -> GrokBuild local workspace/session layout
```

## Pull now

These ideas are compatible and should shape the named frontend checkpoints:

1. F2: a sectioned rail with New chat, Plugins, Projects, Pinned/Recents session
   projections, one selected state, and the account/settings footer. Existing
   stores remain authoritative.
2. F3: separate draft, attachment/context, and footer-control presentation while
   retaining the single existing composer/send owner. Preserve disabled,
   sending, cancellation, history, mention, and attachment states.
3. F4: normalize the visible lifecycle around generation status plus discrete
   plan, tool, permission, question, diff, and answer presentations. Every card
   must be backed by an existing ACP or Git receipt.
4. F5: use project/session search, stable section identity, and responsive rail
   disclosure as client presentation patterns only.

## Do not pull

- Codex app-server, SDK, Responses API, authentication, model-provider, sandbox,
  shell execution, MCP execution, persistence, or worktree runtime code.
- Codex method names as fake ACP aliases or a protocol bridge hidden in Swift.
- Codex trademarks, product icons, screenshots, desktop assets, or pixel-exact
  proprietary layout details.
- Rust/TypeScript files copied into GrokBuild merely to preserve their shapes.
- Any behavior that lets the GUI claim a turn, tool, permission, model, session,
  or diff state that Grok CLI ACP and the existing local receipts did not prove.

## Adoption gate

Before any direct upstream source is copied, name the exact file and lines,
explain why a small native implementation is insufficient, record the Apache
license and NOTICE treatment, add focused tests, and keep the change inside the
active frontend checkpoint. Without that receipt, use the public behavior as an
architectural reference and write the Swift implementation locally.
