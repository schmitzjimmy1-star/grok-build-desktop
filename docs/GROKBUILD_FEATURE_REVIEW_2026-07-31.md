# GrokBuild feature and product review — 2026-07-31

## Product definition

GrokBuild is an agentic macOS project workbench. It is not a chatbot with developer decorations. The central transcript is a durable, inspectable record of an agent working inside a selected project: reading files, planning changes, running terminal and MCP tools, using specialized agents and skills, managing longer workflows, and presenting results or diffs for review.

That distinction changes the review standard. Conversational fluency matters only insofar as it supports project work. The primary product questions are whether project identity is obvious, work runs in the intended directory and durable session, the active model and agent remain truthful, tools and permissions behave predictably, background work remains legible, source changes are reviewable, and interrupted work recovers without destroying user input.

From the perspective of a veteran Apple software engineer, the current build has the right bones. It uses native window, menu, sheet, list, picker, open-panel, and accessibility behavior; it delegates agent execution to the CLI instead of rebuilding the runtime in Swift; and it now puts project state back in the foreground. The earlier transcript-heavy presentation obscured that strength.

## Evidence

This review combined source inspection, **388 passing automated tests**, and live Computer Use against the rebuilt macOS app. Live checks covered the Build Workspace empty state, project/session navigator, session metadata and context menu, branch/worktree sheet, session-agent menu, Browser Tools, Computer Use, Workflows, Tasks, Memory, session dashboard and browser, Settings navigation, permissions, MCP servers, skills, plugins, and native rich-result links.

Grok CLI receipt: `/Users/jimmyschmitz/.grok/bin/grok`, `grok 0.2.118 (1e1687c1cf6a) [stable]`.

Final installed receipt for this historical feature-review slice: executable SHA-256 `e9cf164cad8cdb1b00718e5612c2d1f67c0b1b16bf1e360190d1110ebba8eff3`; deep/strict signing and byte-for-byte dist/install parity passed, and quarantine was cleared. Its then-prior bundle at `/Users/jimmyschmitz/.Trash/GrokBuild-pre-workbench-feature-review-20260731-210606.app` was superseded and permanently retired after the later hostile-stress repair; current rollback truth is recorded in `docs/UI_STRESS_ERROR_REPAIR_HANDOFF_2026-07-31.md`.

## The workbench model

The app has four product layers:

| Layer | User-visible responsibility | Current assessment |
|---|---|---|
| Workspace | Project selection, durable session list, branch/worktree context, open-in actions | Strong foundation; project identity is now persistent and visible |
| Agent run | Model, reasoning effort, agent, permissions, tools, streaming, Stop, recovery | Strong after session/model, draft, interruption, and CPU repairs |
| Orchestration | Skills, workflows, goals, background tasks, subagents, browser/computer automation, memory | Broad and credible; discoverability is improving but still distributed |
| Review and governance | Tool receipts, permission cards, diff preview, commit/PR actions, hooks, compatibility, update receipts | Technically substantial; diff/review deserves more first-class emphasis |

The most important UI repair in this pass is simple: session controls are visible by default. Project, branch, agent, Browser Tools, Computer Use, Workflows, Tasks, and Memory are not secondary chat preferences. They are the state of the workbench. Hiding them made GrokBuild look generic and made it harder to answer the most important question in an agentic IDE: “What exactly is about to act on what?”

## Feature assessment

### Projects, sessions, and identity

The sidebar expresses the correct hierarchy: projects own sessions. Sessions retain local tab identity, backend Grok session identity, model, selected agent, transcript, and last-accessed order. The session dashboard provides a useful cross-session operational view, while Browse Sessions handles the CLI's historical store.

Live acceptance confirmed full sidebar accessibility labels with title, model, running state, and last-used time. Hover/right-click exposes Rename and Close Session. A fresh empty tab initially exposed an impossible year-one date because the view treated an absent persistence record as `Date.distantPast`; this was fixed to announce **New session** and covered by a source-level behavior test.

Session identity remains the critical invariant. A visible transcript, local UUID, backend session ID, model, and agent must agree. The previous teardown repair preserves that invariant through Settings, tab changes, and quit/relaunch. The app should continue treating backend receipts—not selector labels—as the authority for routing acceptance.

### Build entry and composer

The empty state now says **Build Workspace** and offers four appropriate starting jobs: map architecture, implement a scoped change, review the working tree, and diagnose build/test failures. This is a much better contract than an open-ended “What should we talk about?” prompt.

The composer remains compact and native. Its 36-point targets are appropriate for pointer reliability without inflating the macOS density. Model, mode, skills/workflows, context, voice, attachment, Send, and Stop remain one action away. The project status row below it makes the execution environment explicit.

Draft handling is now transactional. The UI clears a submitted draft only after the store accepts it, and only if the user has not edited the text during asynchronous startup. A failed lazy resume or a send/typing race cannot silently erase intent. Starting copy distinguishes **Starting agent…** from **Resuming session…**, making restored-session latency causal instead of mysterious.

### Git, worktrees, and change review

The branch/worktree sheet is a real workbench feature, not a decorative branch badge. Live testing opened the sheet, confirmed the current branch and workspace path, exposed searchable worktrees plus New branch/New worktree disclosures, and closed without mutation.

Diff review exists through `PreviewPane`, including apply/commit/PR affordances. Its conditional appearance is sensible, but review is still less prominent than generation. For a build product, the trustworthy loop is inspect → plan → change → test → review. GrokBuild should eventually surface a stable working-tree summary even when no diff preview is active: clean/dirty state, file count, current branch, test receipt, and the last agent action.

### Agents, models, and orchestration

The session-agent menu correctly separates the default `grok build` behavior from discovered agents such as `general-purpose`, `explore`, and `plan`. Per-tab model selection and per-project effort remain compact. The repaired persistence policy prevents a restored GPT or DeepSeek tab from silently restarting on Grok.

Workflows are broader than a slash-command picker. Live acceptance exposed background run status, Refresh Runs, Saved Workflows, Deep Research, and workflow settings. Tasks mirror scheduled work, shells, monitors, and subagents. Goals, forking, sharing, create-skill, and the status-grouped session dashboard round out the orchestration layer.

This breadth creates one open design problem: capability topology. Skills, workflows, plugins, agents, MCP servers, Browser Tools, Computer Use, hooks, and compatibility are individually understandable but collectively scattered. The answer is not another giant settings screen. Add task-oriented routes from the workbench: “Choose an agent,” “Automate this flow,” “Connect a tool,” and “Review what can act.”

### Tools, MCP, skills, and plugins

Settings → MCP Servers provides add/update, transport and scope, refresh, doctor, status, and removal. Settings → Skills exposes searchable user and bundled skills with source-opening actions. Settings → Plugins exposes installed state, version/source provenance, enablement, and trusted installation. Live Computer Use observed real entries in all three panes.

These are core GrokBuild features. They determine what the agent can do. Their UI should consistently communicate four facts: provenance, scope, enabled state, and effective availability in the active session. “Installed” is not necessarily “loaded,” and “configured” is not necessarily “healthy.” The MCP pane is closest to this truth model because it has Doctor and status concepts.

### Browser and Computer Use

Browser Tools and Computer Use are first-class session capabilities with dedicated Settings panes and one-click session controls. Their enablement can restart the active connection because MCP configuration is part of session construction. That restart is correct but should always be explicit in help and status copy.

The product wisely separates browser automation profiles from native macOS automation and uses applied settings for the live process. Continue to resist merging them into one vague “tools” toggle; their privacy, trust, and failure models differ.

### Permissions and interruption design

The previous **Don't ask** label was misleading. Official xAI documentation defines `dontAsk` as a headless/CI policy that silently denies anything without an explicit allow rule; it is not the interactive “keep capabilities and skip prompts” behavior users reasonably infer from the phrase. The repaired UI calls it **Deny unapproved (CI)** and groups it under Advanced. Interactive choices are Ask, Auto, and Always approve. Always approve launches with `--always-approve`; explicit deny rules, hooks, and sandbox constraints still win. See [xAI permissions](https://docs.x.ai/build/features/permissions) and [xAI enterprise/headless behavior](https://docs.x.ai/build/enterprise).

The app does not silently migrate a user's stored `dontAsk` selection to Always approve because that would expand authority. It does normalize the old explicit `bypassPermissions` spelling to the equivalent Always approve choice. Permission cards now say **Tool approval required**, name the active launch policy, and explain that the tool cannot run until the user chooses.

### Rich results and accessibility

Code, Markdown, tables, math, diagrams, and source links are work artifacts. They are not chat ornament. Native Markdown links now use accent and underline treatment and expose separate accessibility link elements; live acceptance showed an ESPN source as a distinct link with its destination. Display equations expose one spoken equation label rather than fragmented WebKit/KaTeX descendants. Tables expose summaries plus header and cell labels. Mermaid output exposes one diagram description.

This is the right direction for macOS. Accessibility should follow the semantic artifact, not mirror the implementation hierarchy. The next step is hands-on VoiceOver rotor acceptance for long tables and multiple links, plus keyboard activation of every virtual link child.

### Performance and recovery

The prior periodic working indicator repeatedly invalidated a large lazy transcript and could pin a core during silent provider reasoning. Static event-driven status returned silent and idle sampling to 0%. Buffered large ACP chunks and bounded post-layout scroll retries keep progressive and one-shot output usable without continuous animation work.

Recovery is now coherent: restored views bottom-follow on appearance, session identity survives teardown, updater receipts refresh, Stop is static and recoverable, and draft clearing waits for accepted submission. Remaining operational risk is background-task durability: schedules only run while the app and owning session process remain alive, and LRU eviction can stop inactive processes. The UI says this, but a persistent scheduler would be a separate product architecture—not a small polish fix.

## Prioritized findings

| ID | Severity | Status | Evidence | User impact | Recommendation |
|---|---|---|---|---|---|
| GBF-01 | P0 | Fixed | Backend session ID could be erased during teardown | Transcript and model could silently diverge from the next turn | Preserve durable receipts and verify backend history in routing tests |
| GBF-02 | P1 | Fixed | Workbench controls were hidden by default | Product read as a chatbot and hid execution context | Keep project/branch/agent/tools/workflow/task/memory state visible |
| GBF-03 | P1 | Fixed | `dontAsk` was labeled as an interruption preference | Users expected tools to run, but unallowed tools were denied or prompted by a different path | Use truthful Ask/Auto/Always approve grouping and CI label |
| GBF-04 | P1 | Fixed | Lazy-resume failure or a typing race could clear the draft | User intent could disappear | Clear only an unchanged draft after accepted submission |
| GBF-05 | P2 | Fixed | Links, math, and tables flattened semantically | Source discovery and VoiceOver navigation were weak | Native link children and spoken artifact labels |
| GBF-06 | P2 | Fixed | Session rows truncated identity and showed no operational metadata | Long session histories were hard to disambiguate | Model/state/last-used AX and help metadata plus row actions |
| GBF-07 | P2 | Open recommendation | Review state appears mainly when a diff is detected | Generation feels more prominent than verification | Add a persistent working-tree/test summary to the workbench |
| GBF-08 | P2 | Open recommendation | Capabilities are distributed across many panes and menus | Users must understand internal taxonomy before acting | Add task-oriented capability routes, not another flat settings group |
| GBF-09 | P3 | Open recommendation | Background schedules depend on live session processes | “Scheduled” can imply stronger durability than exists | Keep lifecycle copy prominent; only promise durable scheduling with a persistent service |
| GBF-10 | P3 | Model behavior | DeepSeek ignored “No tools” and wrote a file | Unexpected project mutation | Keep tool receipts visible; do not misclassify model instruction failure as renderer failure |

## Ship judgment

The current build is fit for continued personal daily use as a GrokBuild workbench. Its strongest qualities are thin CLI delegation, durable session/model identity, broad capability management, native macOS structure, honest tool receipts, and low idle cost. The next product increment should not add more chat polish. It should strengthen review authority: persistent working-tree state, clearer capability topology, and end-to-end VoiceOver/keyboard acceptance of work artifacts.
