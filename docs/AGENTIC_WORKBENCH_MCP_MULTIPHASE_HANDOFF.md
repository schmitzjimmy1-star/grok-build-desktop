---
title: GrokBuild agentic workbench and MCP builder multiphase handoff
status: ready to execute
researched: 2026-08-02
---

# GrokBuild agentic workbench and MCP builder multiphase handoff

> Paste everything below this line into a fresh implementation task. This is
> an execution handoff, not a claim that the work has already been completed.

## Mission

Continue the canonical GrokBuild desktop application as an **agentic project
workbench**, not a chatbot with a file picker. The finished product should make
goals, plans, workers, tool activity, evidence, approvals, budgets, checkpoints,
and resumable outcomes legible while keeping Grok CLI as the agent runtime and
GrokBuild as the thin native macOS shell.

Repair the known tool/session defects first, then add bounded multi-agent work,
an MCP-building workflow, and installed-app acceptance using a realistic
American-history MCP project. Treat the existing American History Gateway as a
reference for evidence discipline, bounded provider work, host boundaries,
secret-safe receipts, and release truth. Do not turn it into a dependency or
silently modify/deploy that separate repository.

The outcome is not “the model said it used tools.” The outcome is a live,
installed GrokBuild run that visibly decomposes a goal, waits for its tools,
routes bounded work, executes and verifies tool calls, survives multiple turns,
hands work between workers without corrupting history, builds and tests an MCP,
and leaves auditable, secret-safe receipts.

## Canonical identity and starting truth

- Worktree: `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop`
- Maintained remote: `personal` → `https://github.com/schmitzjimmy1-star/grok-build-desktop.git`
- Upstream remote: `origin` → `https://github.com/rimusz/grok-build-desktop.git`
- Starting branch and local HEAD at handoff creation: `main` at
  `7ead3abfaa8f3fc5e08c69976b4eb64252b0594b`
- Installed app: `/Applications/GrokBuild.app`, version `0.1.20`, source stamp
  `eea6c9868154a38ab1f4c8ebe6263a2e7b8a5e6a`
- Installed source repository stamp:
  `https://github.com/schmitzjimmy1-star/grok-build-desktop`
- Grok CLI capability receipt: `--agents`, `--no-subagents`, `--max-turns`,
  `--worktree`, `--json-schema`, tool allow/deny, web-search control, permission
  modes, and `grok agent stdio` are present in the installed CLI.
- Preserve the existing uncommitted
  `docs/TOOL_USE_AND_MULTI_TURN_CONTRACT.md`. It is governing input, not trash.
- The retired `/Users/jimmyschmitz/Documents/Grok Builf` /
  `jimmmy-Jim/Grok-Build-GUI` line is evidence only. Never build, install,
  modernize, publish, or resume it.

Before editing, run the complete identity preflight in `CANONICAL_WORKTREE.md`.
Fetch the maintained remote read-only and reconcile local, remote, installed,
and dirty state. If any identity differs, stop before mutation and report the
exact mismatch.

## Governing documents

Read these completely before implementation:

1. `AGENTS.md`
2. `CANONICAL_WORKTREE.md`
3. `ARCHITECTURE.md`
4. `docs/TOOL_USE_AND_MULTI_TURN_CONTRACT.md`
5. `docs/ARCHITECTURE_AUDIT.md`
6. `docs/OAUTH_OPENROUTER_ACP_PLAN.md`
7. `docs/UI_ACCEPTANCE_MATRIX.md`
8. `docs/GROKBUILD_COHERENCE_ACCESSIBILITY_REPAIR_PLAN_2026-08-01.md`

For the American History Gateway reference case, read but do not edit unless a
new, explicit scope says otherwise:

1. `/Users/jimmyschmitz/Desktop/Projects/MCP Servers/active-mcp-servers/american-history-gateway-mcp-server/AGENTS.md`
2. `CURRENT_STATE.md`
3. `README.md`
4. `docs/ARCHITECTURE.md`
5. `docs/OPERATIONS.md`

Current behavior beats inherited prose. Historical plans and receipts are
provenance, not present-tense acceptance.

## Research basis to apply

This handoff follows current primary-source guidance rather than generic agent
hype:

- MCP separates hosts, one client per server, and servers; it separates tools
  (actions), resources (context), and prompts (reusable interaction templates).
  Capability discovery, exact schemas, notifications, progress, and durable
  Tasks exist so clients do not have to guess readiness or behavior. MCP does
  not define the application's agent orchestration.
  [MCP architecture](https://modelcontextprotocol.io/docs/learn/architecture)
- Effective agents combine instructions, tools, handoffs, guardrails,
  structured output, sessions, and tracing. A handoff transfers control and
  relevant history; a specialist used as a tool returns its result to the
  manager. Keep those two behaviors distinct.
  [OpenAI Agents](https://openai.github.io/openai-agents-python/agents/),
  [handoffs](https://openai.github.io/openai-agents-python/handoffs/), and
  [tracing](https://openai.github.io/openai-agents-python/tracing/)
- Choose the smallest orchestration pattern that fits: sequential chaining for
  dependent stages, routing for specialist selection, parallel workers only for
  independent work, an orchestrator-worker pattern for decomposition, and an
  evaluator-optimizer loop only when an explicit rubric can stop it.
  [Anthropic, Building Effective AI Agents](https://resources.anthropic.com/building-effective-ai-agents)
- The official MCP Registry is discovery metadata, not a safety or quality
  certificate. Verify namespace, source repository, version, permissions,
  schemas, transport, and secret handling before enabling a server.
  [MCP Registry](https://modelcontextprotocol.io/registry/about)
- Prefer a narrow tool surface. GitHub's official server supports read-only mode
  and tool/toolset allowlists; the official filesystem reference server scopes
  allowed roots; Playwright's official MCP uses structured accessibility state
  and warns that MCP browser control is not a security boundary.
  [GitHub MCP](https://github.com/github/github-mcp-server),
  [filesystem reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem),
  [Playwright MCP](https://github.com/microsoft/playwright-mcp)

Do not install a fashionable pile of MCPs. Start from the job, select the
minimum capabilities, and progressively disclose additional tools only when a
worker has a reason to use them.

## Authorization and safety envelope

When Jimmy pastes this handoff and says to execute it, that authorizes scoped
local code/document/test changes in the canonical GrokBuild worktree, app
rebuild/sign/install, and installed-app Computer Use acceptance. Preserve user
state, provider credentials, retained sessions, rollback bundles, and unrelated
dirty work.

The following remain separate gates:

- Ask once before the first billable provider test. Record the approved cap in
  tokens, calls, or dollars and stop at it. Never treat a prior run's billing
  authorization as unlimited.
- Authentication, consent, external sends, purchases, destructive account
  changes, secret rotation/revocation, and deployment of another app require
  exact scope.
- Commit and push only if the executing request explicitly includes
  publication. Never force, prune, mirror, delete, or rewrite history.
- Never print or persist API keys, OAuth codes, PKCE verifiers, bearer tokens,
  callback URLs containing secrets, provider response bodies, private prompts,
  or hidden reasoning. Keychain remains credential truth; receipts contain
  provider/model IDs, counts, durations, statuses, and redacted errors only.

Use the least-powerful permission mode that can complete each test. Destructive
or external-write tools default off. One integration owner makes shared-source
edits; workers return findings or isolated patches rather than racing on the
same files.

## Known defects and outstanding work

Treat this as the starting backlog, then verify each item live before editing:

1. **MCP readiness race.** Browser and Computer Use servers can still be
   connecting when a fast model begins its first turn. Gemini 2.5 Flash and
   GPT-4.1 Mini required same-session readiness retries during installed-app
   acceptance. The composer/process currently does not provide a reliable
   tool-required readiness gate.
2. **Cross-provider tool-history corruption.** A provider/model switch after a
   web or tool turn can fail with `Invalid params` before usage or a final
   answer. Plain switches in a clean session passed. Provider-specific tool
   history must be isolated or translated, never replayed blindly.
3. **Agent work is insufficiently legible.** Grok CLI owns plans, subagents,
   tools, permissions, and scheduled work, but GrokBuild should show the goal,
   active phase, worker ownership, tool status, approvals, budgets, checkpoints,
   and completion evidence as project-work state rather than a chat scroll.
4. **Multi-agent behavior lacks an installed acceptance matrix.** Prove
   manager/specialist routing, parallel independent workers, handoff history,
   cancellation, budget enforcement, failure containment, and single-owner
   integration. Do not call ordinary multiple tool calls “multi-agent.”
5. **MCP building lacks a first-class, evidence-backed workflow.** A user should
   be able to inspect an existing server or scaffold a narrow one, define tools,
   resources, and prompts correctly, validate schemas/transports/security,
   exercise it in Inspector/host, and retain release receipts.
6. **Tool evidence and stale references need stronger affordances.** Browser and
   Computer Use refs expire after state changes. Tool cards should distinguish
   discovered, connecting, ready, running, succeeded, failed, cancelled, and
   stale; a spinner or Settings toggle is not proof.
7. **Usage governance needs a product surface.** Multi-agent and evaluator loops
   can multiply calls rapidly. The user needs per-run limits, current usage,
   worker/tool breakdowns, cancel/stop, and a final disclosed receipt.
8. **Deferred architecture remains deferred without new evidence.** Generic
   OAuth issuers, refresh-token sets, richer OpenRouter telemetry, arbitrary ACP
   backends/Goose, AG-UI, LiteLLM, full OpenHands hosting, broad notification
   rewrites, and cosmetic file splitting are not smuggled into this campaign.

## Product contract: agentic, not chatbot-shaped

Keep the existing quiet native design. Do not add a dashboard carnival. At a
minimum, an active project run must expose:

- one explicit goal and current acceptance contract;
- a short ordered plan with pending, active, blocked, failed, and completed
  states;
- worker lanes with role, assigned scope, current action, and terminal outcome;
- tool calls attached to the plan step and worker that caused them;
- approval requests at the consequential boundary, not as constant nagging;
- a bounded usage meter and stop control;
- a checkpoint containing Goal, Completed, Evidence, State changed, Next, and
  Constraints;
- a completion summary that links changes, tests, live evidence, usage, and
  unresolved risks;
- a recovery path after failure, cancellation, quit/relaunch, or provider
  change.

Conversation remains useful for direction and explanation, but the source of
truth is structured work state plus receipts. Never fabricate a plan item,
worker, tool call, or completion from prose alone.

## Phase 0 — reconcile and freeze the baseline

This phase is read-only.

1. Run the canonical identity preflight and fetch `personal` without altering
   user files.
2. Inventory the dirty worktree and preserve the existing tool-use contract.
3. Record installed app identity, signature, quarantine, executable hash, CLI
   version/help, saved Settings, current provider/model list, authenticated
   continuity, and active processes without exposing credentials.
4. Reproduce the MCP readiness race and the cross-provider tool-history failure
   in disposable sessions with the smallest authorized calls. If either no
   longer reproduces, retain the new evidence and do not code a ghost fix.
5. Map the ACP events already emitted for plan changes, tool calls, permission
   requests, scheduler activity, session history, usage, and subagents. Prove
   which desired UI state exists in the protocol before inventing new storage.
6. Produce a one-page baseline receipt and a ranked Fix / Spike / Defer table.

**Gate:** no code begins until identity, dirty state, installed/runtime state,
and the two defect reproductions are settled.

## Phase 1 — reliable MCP lifecycle and tool-required readiness

Fix the first-turn race at the thinnest truthful layer.

1. Model each configured MCP server as Connecting, Ready, Degraded, Failed,
   Disabled, or Stopped using actual CLI/ACP evidence.
2. Discover and cache capabilities only after protocol readiness. Honor tool
   list changes and invalidate stale capability state.
3. For a run that explicitly requires Browser or Computer Use, prevent the
   agent from claiming execution until the named server is Ready. Use a bounded
   same-session retry when the server reports “still connecting.”
4. Do not block ordinary text-only work merely because an optional MCP is slow.
5. Surface actionable failure: exact server name, non-secret reason, retry,
   disable, or open the relevant Settings pane.
6. Preserve cancellation and process-generation guards so late readiness cannot
   mutate a replaced session.

Automated tests must cover fast-model startup, delayed readiness, partial tool
discovery, server failure, retry success, list changes, cancellation, restart,
wrong generation, and text-only sends with an optional server unavailable.

Installed acceptance must show a fresh fast-model session waiting/retrying and
then completing the exact Browser and Computer Use tools without a false
“capability missing” answer.

## Phase 2 — safe provider/model transitions after tools

Make incompatible history impossible to replay accidentally.

1. Classify each completed turn as plain, web-search, built-in tool, MCP tool,
   or mixed using authoritative transcript events.
2. When the user requests a provider-boundary switch after tool-rich history,
   fail closed before a billable send and offer **Start new session with
   checkpoint**.
3. Generate the checkpoint from durable public state only. Never copy raw tool
   JSON, hidden reasoning, provider response bodies, or credentials.
4. Preserve the original session unchanged and create a backend-confirmed new
   session with the requested model.
5. Keep same-provider/plain-history switching working. Do not ban all model
   switches to hide one interoperability bug.
6. If exact lossless translation is later proven across a provider pair, gate it
   behind explicit compatibility tests rather than optimistic string rewriting.

Acceptance: fresh plain switch passes; web/tool cross-provider switch is
intercepted; checkpoint transfer succeeds; original transcript remains intact;
wrong route makes zero provider calls.

## Phase 3 — structured run state and resumable project work

Add the smallest native work-state layer that can be derived from ACP and local
project state.

1. Introduce a per-session Run Summary with goal, acceptance criteria, plan,
   current phase, worker/tool activity, usage, checkpoint, and outcome.
2. Prefer structured ACP events or constrained JSON output over parsing prose.
   Invalid structured updates are rejected and shown as degraded, not silently
   accepted.
3. Bind every update to local tab ID, backend ID, process generation, turn ID,
   and request ID. Discard stale/out-of-order events.
4. Persist only the minimum resumable public state. Session transcripts remain
   authoritative for conversation; provider-native tool records remain in their
   compatible backend session.
5. Restore the run summary after quit/relaunch and distinguish restored local
   state from a live backend receipt.
6. Keep chat available but visually subordinate routine narration to actual
   work, evidence, and decisions.

Acceptance: create a three-step task, complete one step, quit/relaunch, resume
the exact next step, cancel, and verify no duplicate work or stale completion.

## Phase 4 — bounded multi-agent orchestration

Use Grok CLI's own subagent/runtime capabilities. Do not embed another agent
SDK in Swift merely to draw worker cards.

Implement and test these distinct patterns:

1. **Router:** manager selects one specialist from an explicit role catalog.
2. **Sequential chain:** protocol design → implementation → verification, where
   each stage consumes the prior stage's checked artifact.
3. **Parallel workers:** two or three independent read-only investigations run
   concurrently with isolated scope and no shared writes.
4. **Manager with specialists-as-tools:** specialists return bounded findings
   and control returns to the manager.
5. **Handoff:** control and a filtered checkpoint move to a specialist that owns
   the next stage.
6. **Evaluator-optimizer:** one evaluator checks an artifact against a fixed
   rubric; at most one repair loop is allowed unless the user raises the cap.

Hard rails:

- default maximum three active workers, configurable downward;
- explicit max turns, model calls, tool calls, and token/cost budget;
- one integration owner for shared files;
- worker allowlists for roots, tools, MCP servers, and write permissions;
- no worker may spawn an unbounded descendant tree;
- cancellation propagates and late results are marked orphaned, never merged;
- worker failures return typed, non-secret receipts and do not erase successful
  sibling evidence;
- deterministic tests and the integration owner—not a model vote—decide release
  acceptance.

Installed acceptance scenario: one manager coordinates three roles for an MCP
change—Protocol/Schema, Domain/Retrieval, and Validation/Security. Run the two
independent investigations in parallel, then hand their receipts to the single
integration owner. Prove worker identity, tool ownership, call/usage totals,
cancellation, one injected failure, and a bounded evaluator pass.

## Phase 5 — MCP builder workflow

Add an agentic workflow, not a giant IDE inside the app. It may begin as a
project template plus structured run recipe if that is the lightest honest
implementation.

The workflow must:

1. Inspect an existing MCP or scaffold a minimal TypeScript or Swift server.
2. Ask what capability is needed before choosing tools, resources, or prompts.
3. Define exact names, descriptions, JSON Schemas, structured results, errors,
   timeouts, progress, cancellation, and idempotency behavior.
4. Support stdio for local servers and Streamable HTTP plus OAuth for remote
   servers when required. Never invent auth merely because a server is remote.
5. Scope filesystem roots, hosts/origins, environment variables, credentials,
   and write tools. Default to read-only and local loopback during development.
6. Exercise discovery and calls with the MCP Inspector or a deterministic test
   client before model-driven acceptance.
7. Test malformed inputs, dependency failure, timeout, cancellation,
   concurrency, rate limits, oversized responses, redirects, SSRF boundaries,
   prompt/error redaction, and secret absence.
8. Generate a capability manifest and release receipt: server/version/source
   SHA, transport, tools/resources/prompts, schemas, auth mode, bounds, tests,
   and known limitations.
9. Optionally validate Registry metadata, but do not publish or install from the
   Registry without separate authorization and provenance review.

### MCP capability palette

Apply capabilities by need, in this order:

| Need | Preferred capability | Default boundary |
|---|---|---|
| Local source/build/test | Grok terminal plus workspace-scoped filesystem access | Exact project root; no home-wide write access |
| Repository/PR evidence | Local Git first; official GitHub MCP only for remote metadata/actions | Read-only toolsets until publication is authorized |
| Current public research | Built-in web search/fetch | Source inspection and citations; no account state |
| Stateful website interaction | Existing GrokBuild Browser MCP; Playwright MCP only as a measured alternative | Isolated profile, exact hosts, fresh refs |
| Native macOS acceptance | Existing GrokBuild Computer Use MCP | Accessibility refs, fresh snapshots, no guessed destructive actions |
| Errors/production telemetry | A narrow first-party observability MCP such as Sentry only when the target uses it | Project-scoped read-only queries; redact event data |
| Long project knowledge | MCP resources or project documents before a generic memory server | User-visible, deletable, source-linked state |
| Server discovery | Official MCP Registry metadata | Inspect, pin, and allowlist; never equate listing with trust |

Do not add duplicate Browser, Computer Use, GitHub, filesystem, memory, or
search servers when the existing runtime already provides the capability.
Measure schema/context cost before expanding a tool surface.

## Phase 6 — American History MCP reference build

Use an isolated fixture or new sample MCP owned by the GrokBuild test workspace.
Do not change or deploy the live American History Gateway.

Build a narrow **Chicago History Evidence Lab** MCP that demonstrates the
Gateway's strongest transferable patterns without cloning its entire product:

- one free deterministic source-discovery path;
- one explicit billable synthesis path, disabled by default;
- tools for search and bounded answer composition;
- resources for source/evidence packets and run receipts;
- a reusable prompt for an evidence-first research brief;
- source identity, type, date/place fit, inspected/metadata-only state, and
  citation eligibility;
- bounded provider requests, concurrency, response bytes, retries, and time;
- fail-closed evidence sufficiency: weak packets produce explicit gaps, not
  fluent invented history;
- deterministic bibliography/citation assembly from admitted evidence;
- exact-span or inspected-text grounding for attributed claims;
- opaque per-session capabilities rather than a process-global current result;
- host-aware compact output without leaking session IDs, prompts, secrets, or
  provider payloads;
- model failure disclosed as degradation, never silently treated as a pass.

Use reputable first-party or scholarly APIs directly through narrow adapters
where available. Candidate lanes include Library of Congress, Chronicling
America/NEH, National Archives, DPLA, Smithsonian, OpenAlex, Crossref, ERIC,
and Unpaywall. Each lane must be individually justified, documented, bounded,
and tested; do not add all of them merely to inflate the connector count.

Frozen acceptance prompts should include:

1. a broad Chicago history question requiring scholarly spread;
2. a named-place/named-community question that tests scope preservation;
3. a primary-source question with OCR or newspaper evidence;
4. an intentionally evidence-starved question that must disclose gaps;
5. an adversarial prompt asking the writer to ignore sources or reveal hidden
   data;
6. a multi-turn follow-up that reuses the same bounded research session;
7. an expired/wrong capability test proving no cross-session fallback.

The evaluator checks evidence eligibility, claim support, scope, bibliography,
source disclosure, request ceilings, secret absence, latency, and settled host
output. It does not reward length or confident prose.

## Phase 7 — cross-model tool and multi-turn acceptance

Use fresh disposable sessions and backend-confirmed live model receipts. Test a
representative direct Grok route, direct OpenAI route, one other direct provider,
and at least two OpenRouter routes only within the approved billing cap.

For each route:

1. terminal read-only call;
2. MCP readiness and exact tool discovery;
3. built-in web search with inspected sources;
4. Browser open → wait → snapshot → ref action → fresh snapshot;
5. Computer Use list/snapshot → ref action → fresh verification;
6. MCP fixture discovery and one deterministic tool call;
7. four-turn checkpoint/resume test;
8. manager plus specialist test where supported;
9. cancellation and bounded retry;
10. exact no-tool recall of the public checkpoint.

Record pass, pass-after-readiness-retry, unsupported, failed, or blocked. Do not
collapse those into one green check. A discovered tool name, Settings toggle,
spinner, model claim, or catalog result is not execution proof.

Never switch provider inside tool-rich history during the matrix. Start a new
session and carry only the plain-text checkpoint. Separately test that the new
Phase 2 guard prevents the known invalid replay.

## Phase 8 — observability, budgets, accessibility, and performance

1. Add secret-safe run/worker/tool receipts with stable correlation IDs,
   elapsed time, terminal status, retries, model/provider ID, and usage totals.
2. Default logs exclude prompt bodies, tool inputs/outputs, credentials, and
   hidden reasoning. Add focused redaction tests.
3. Show aggregate and per-worker calls/tokens/cost when providers expose them;
   mark unavailable fields unknown rather than zero.
4. Enforce budgets before spawning or retrying. One stop action cancels the
   manager, workers, tools, and pending evaluator loop.
5. Perform VoiceOver/Accessibility traversal, keyboard-only operation, focus
   restoration, reduced motion, contrast, Dynamic Type equivalents available
   on macOS, Settings round trips, quit/relaunch, and error recovery.
6. Soak one realistic agentic run while sampling app/child CPU, memory, process
   count, open files, logs, and orphan cleanup. Settled idle CPU and child
   process ownership are acceptance gates.
7. Verify no stale accessibility or browser ref can trigger the wrong action;
   require a fresh snapshot after every structural state change.

## Phase 9 — release-readiness and installed truth

For every code slice:

1. make surgical edits matching existing Swift/SwiftUI conventions;
2. update tests and governing docs in the same slice;
3. run focused tests, then `make test`;
4. rebuild/package/sign/install through the repository's supported workflow;
5. run deep and strict signature verification and check quarantine;
6. drive `/Applications/GrokBuild.app` with Computer Use to the exact changed
   state;
7. verify Settings round trips, preserved user/provider state, retained
   sessions, quit/relaunch, rollback bundle, installed identity, executable
   hash parity, and settled resource use;
8. scan source, diffs, logs, receipts, test output, and packaged resources for
   secret patterns;
9. update `ARCHITECTURE.md`, README/user docs, acceptance matrix, and this
   handoff's outcome section.

No green suite substitutes for installed-app proof. No UI screenshot substitutes
for backend/tool/usage receipts. No local build substitutes for signed installed
identity.

## Phase 10 — publication, only when authorized

1. Reconcile the final dirty tree and stage only intended files.
2. Commit on a short-lived `codex/*` branch with an exact scope message.
3. Push normally to `personal` and use the maintained GitHub workflow for a
   draft PR. Preserve `origin` as upstream.
4. Verify local commit, remote branch, PR head/base/tree, checks, and displayed
   diff parity. Never overwrite an existing draft PR's exact content unless the
   executing request explicitly says to update it.
5. After merge, fetch and reconcile `main`, rebuild/install the exact merged
   commit if requested, and repeat the minimum identity/signature/smoke proof.

## Required receipts

Maintain append-only, secret-safe receipts for:

- canonical preflight and starting dirty state;
- defect reproductions and root-cause evidence;
- each slice's files/tests/installed-app proof;
- MCP capability manifest and schema fingerprints;
- worker graph, roles, handoffs, tool calls, failures, cancellation, and usage;
- cross-model capability matrix;
- American-history fixture evidence/quality matrix;
- accessibility and performance soak;
- signed bundle, installed identity, hashes, rollback bundle, and final state;
- commit/remote/PR parity when publication is authorized.

## Stop conditions

Stop and report evidence instead of improvising when:

- canonical worktree, branch, remote, installed identity, or dirty state cannot
  be reconciled;
- a required edit overlaps unexplained user work;
- a secret appears in source, output, logs, receipts, or Git history;
- a billable cap, call cap, time cap, worker cap, or retry cap is reached;
- a model/provider route cannot be proven before send;
- MCP readiness or capability cannot be proven after the bounded retry;
- tool history would cross an unverified provider boundary;
- the only proposed fix duplicates Grok CLI runtime behavior in Swift;
- deterministic or installed acceptance fails repeatedly;
- publication, deployment, destructive action, or external send lacks explicit
  authorization.

## Definition of done

Done means all of the following are simultaneously true:

- the two known session/tool defects are fixed or truthfully guarded with live
  reproduction and regression coverage;
- GrokBuild presents structured, resumable work state rather than relying on
  chat narration;
- bounded multi-agent routing, parallelism, handoffs, failure containment,
  cancellation, and budgets pass installed acceptance;
- the MCP builder workflow produces and validates the Chicago History Evidence
  Lab fixture with evidence-first behavior;
- terminal, web search, Browser, Computer Use, and fixture MCP calls pass the
  cross-model matrix with exact caveats;
- accessibility, performance, secret safety, state continuity, rollback, and
  installed identity pass;
- governing docs and append-only receipts match current code/runtime truth;
- final Git/local/remote/PR parity is proven if and only if publication was
  authorized.

Finish with a compact handoff containing: outcome, exact files/commits,
installed identity, tests, capability matrix, usage/cost, unresolved risks,
rollback, publication status, and the single next authorization—if any.
