import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ComposerControlMetrics {
    static let minimumHitTarget: CGFloat = 36
}

enum ComposerDensityPolicy {
    static let minimumLineCount = 1
    static let maximumLineCount = 8
    static let editorMinimumHeight = ComposerControlMetrics.minimumHitTarget
    static let surfaceHorizontalPadding: CGFloat = 11
    static let surfaceVerticalPadding: CGFloat = 7
    static let outerHorizontalPadding: CGFloat = 20
    static let outerVerticalPadding: CGFloat = 5
    static let surfaceHasShadow = false
}

/// Owns one stable AppKit cursor rectangle for the text-entry portion of the
/// composer. SwiftUI's transparent, vertically-growing TextField otherwise
/// exposes alternating editor and container hit regions, which can make the
/// pointer flicker between an I-beam and arrow while it is still visibly over
/// the editor. The view never intercepts clicks and does not use cursor stacks,
/// hover callbacks, or timers.
final class ComposerCursorRectView: NSView {
    private var composerTrackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = frame.size != newSize
        super.setFrameSize(newSize)
        if sizeChanged {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func updateTrackingAreas() {
        if let composerTrackingArea {
            removeTrackingArea(composerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate,
            ],
            owner: self
        )
        addTrackingArea(trackingArea)
        composerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        applyComposerCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        applyComposerCursor()
    }

    override func cursorUpdate(with event: NSEvent) {
        applyComposerCursor()
    }

    override func mouseExited(with event: NSEvent) {
        applyWorkbenchCursor()
    }

    func applyComposerCursor() {
        NSCursor.iBeam.set()
    }

    func applyWorkbenchCursor() {
        NSCursor.arrow.set()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct ComposerCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> ComposerCursorRectView {
        ComposerCursorRectView()
    }

    func updateNSView(_ nsView: ComposerCursorRectView, context: Context) {
        // SwiftUI calls this for every draft mutation. Invalidating cursor
        // rectangles here turns long prompt entry into an AppKit layout loop;
        // window attachment and actual size changes already own invalidation.
    }
}

enum ProjectOpenTarget {
    case finder
    case cursor
    case vsCode
    case terminal
    case iTerm
    case zed
}

enum ChatTranscriptLayout {
    enum MessageBlock: Hashable {
        case agentHeader
        case thinking
        case toolActivity
        case planSpine
        case liveProgress
        case answer
    }

    struct IdentifiedMessageBlock: Identifiable, Hashable {
        let messageID: UUID
        let block: MessageBlock

        var id: Self { self }
    }

    static func identifiedMessageBlocks(
        messageID: UUID,
        blocks: [MessageBlock]
    ) -> [IdentifiedMessageBlock] {
        blocks.map { IdentifiedMessageBlock(messageID: messageID, block: $0) }
    }

    /// One turn has one stable semantic order. Thinking and tool receipts may
    /// appear or settle at any point in the event stream, but neither is allowed
    /// to migrate below the answer it explains. The live run row (Workbench W-5)
    /// is independent of the trace disclosure. After the answer settles, tool
    /// receipts stay on the message; the GitHub-style settled Run checklist is
    /// not mounted in the transcript (Activity remains the opt-in ledger).
    /// Turns with tool receipts default expanded, including restored threads,
    /// until the user collapses that turn.
    static func messageBlockOrder(
        containsAgentHeader: Bool,
        traceExpanded: Bool,
        containsThinking: Bool,
        containsToolActivity: Bool,
        containsLiveProgress: Bool = false,
        containsPlanSpine: Bool = false
    ) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        if containsAgentHeader { blocks.append(.agentHeader) }
        if traceExpanded && containsThinking { blocks.append(.thinking) }
        if traceExpanded && containsToolActivity { blocks.append(.toolActivity) }
        if containsPlanSpine { blocks.append(.planSpine) }
        if containsLiveProgress { blocks.append(.liveProgress) }
        blocks.append(.answer)
        return blocks
    }

    static func activeAssistantMessageID(
        messages: [Message],
        streamingMessageID: UUID?
    ) -> UUID? {
        if let streamingMessageID { return streamingMessageID }
        guard let lastTurnMessage = messages.last(where: { $0.role == .assistant || $0.role == .user }) else {
            return nil
        }
        return lastTurnMessage.role == .assistant ? lastTurnMessage.id : nil
    }

    /// Tool receipts default visible. An explicit collapse wins; an explicit
    /// expand (including a live streaming turn) also wins. Thinking-only turns
    /// stay collapsed until the user opens them or a live stream inserts them.
    static func isTraceExpanded(
        messageID: UUID,
        hasTools: Bool,
        explicitlyExpanded: Set<UUID>,
        explicitlyCollapsed: Set<UUID>
    ) -> Bool {
        if explicitlyCollapsed.contains(messageID) { return false }
        if explicitlyExpanded.contains(messageID) { return true }
        return hasTools
    }

    /// Thinking belongs to the assistant response for the active turn. During
    /// streaming that response has an explicit id; after completion it is the
    /// most recent assistant message — but only when that message is the
    /// latest turn's answer. When a failed turn removed its empty assistant
    /// reply (the transcript then ends with the user prompt), this returns
    /// nil and ChatView renders the block at the transcript tail instead, so
    /// the trace is neither lost nor attached to an older answer.
    static func thinkingMessageID(
        messages: [Message],
        streamingMessageID: UUID?
    ) -> UUID? {
        activeAssistantMessageID(
            messages: messages,
            streamingMessageID: streamingMessageID
        )
    }
}

enum ChatAutoScrollPolicy {
    /// Follow-up passes after the first scroll. GPT/DeepSeek and rich Markdown can
    /// deliver one large final chunk whose SwiftUI/WebKit height settles after the
    /// stream event; a single pre-layout scroll then leaves the answer below the fold.
    /// These gaps yield immediately, then cover the next ~3.1 seconds of bounded
    /// layout settling. Later turns commonly reuse warm WebKit views whose final
    /// intrinsic height lands well after the ACP completion event; keeping the
    /// true bottom attached through that window prevents turns two and three from
    /// ending behind the composer without introducing an unbounded timer.
    static let layoutSettleGapsMilliseconds = [0, 100, 200, 400, 800, 1_600]
}

enum ChatTranscriptScrollPolicy {
    /// A small bottom margin keeps a reader attached when they are just above
    /// the final line, while a deliberate upward scroll immediately detaches.
    static let attachmentThreshold: CGFloat = 52

    static func isAttached(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom <= attachmentThreshold
    }

    static func unreadCount(
        current: Int,
        messageCountDelta: Int,
        contentChanged: Bool,
        isAttached: Bool
    ) -> Int {
        guard contentChanged, !isAttached else { return isAttached ? 0 : current }
        return current + max(1, messageCountDelta)
    }

    static func jumpLabel(unreadCount: Int) -> String {
        unreadCount > 0 ? "Jump to latest (\(unreadCount) new)" : "Jump to latest"
    }

    /// An already-attached reader does not need a per-chunk `scrollTo` while the
    /// bounded settlement window keeps the true bottom in view. Immediate follow
    /// remains for the first attach, when content has grown off-screen.
    static func shouldPerformImmediateFollowScroll(isAttached: Bool) -> Bool {
        !isAttached
    }
}

/// AppKit `SelectionOverlay` on settled per-block Markdown feeds back into
/// `LazyVStack` layout on macOS 26. Freeze selection only while the transcript is
/// auto-following a live or settling turn; a reader who scrolled away keeps copy.
enum ChatTranscriptSelectionPolicy {
    static func shouldSuspendSelection(
        isFollowingBottom: Bool,
        isStreaming: Bool,
        isSettlingAutoScroll: Bool
    ) -> Bool {
        isFollowingBottom && (isStreaming || isSettlingAutoScroll)
    }
}

enum ComposerModelMenuLayout {
    static func effortDisplayName(storedValue: String) -> String {
        ReasoningEffortLevel(storedValue: storedValue).displayName
    }
}

enum ComposerSubmissionPolicy {
    /// Clear only the exact draft GrokBuild handed to the agent and only after the
    /// session accepted it. If lazy resume is still starting — or the user typed
    /// more while send awaited readiness — the editor remains authoritative.
    static func draftAfterSubmission(
        currentDraft: String,
        submittedDraft: String,
        accepted: Bool
    ) -> String {
        accepted && currentDraft == submittedDraft ? "" : currentDraft
    }
}

enum ConnectionStatusPresentation {
    static func subtitle(
        state: GrokProcessState,
        isResumedSession: Bool,
        hasWorkspace: Bool
    ) -> String {
        switch state {
        case .starting:
            return isResumedSession ? "Resuming session…" : "Starting agent…"
        case .ready:
            return "Connected"
        case .busy:
            return "Working…"
        case .failed:
            return "Connection error"
        case .idle:
            return hasWorkspace ? "Ready" : "Idle"
        }
    }
}

struct ChatView: View {
    @Bindable var store: ChatStore
    var sessionTitle: String = "New chat"
    var isSidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var reviewFileCount: Int = 0
    /// The already-fetched project diffs, used only to derive per-file +/− counts
    /// for the inline changed-files card (Codex parity Slice 3). Git remains the
    /// authority; ChatView never fetches or refreshes.
    var reviewDiffs: [ChatStore.DetectedDiff] = []
    var isReviewVisible: Bool = false
    var onToggleReview: () -> Void = {}
    /// Straggler fix (2026-08-08): the inline card's Review selects the Last
    /// turn scope before the pane opens.
    var onOpenTurnReview: () -> Void = {}
    var onBrowseSessions: () -> Void = {}
    var onNewSession: () -> Void = {}
    var onAddProject: () -> Void = {}
    var onOpenProjectIn: (ProjectOpenTarget) -> Void = { _ in }
    var onToggleBrowserTools: () -> Void = {}
    var onSelectBrowserRuntime: (BrowserRuntimeMode) -> Void = { _ in }
    var onToggleComputerUse: () -> Void = {}
    var onOpenBrowserSettings: () -> Void = {}
    var onOpenComputerUseSettings: () -> Void = {}
    var onOpenAgentSettings: () -> Void = {}
    var onOpenModelSettings: () -> Void = {}
    var onOpenConnectionSettings: () -> Void = {}
    var onOpenMemorySettings: () -> Void = {}
    var onForkSession: () -> Void = {}
    var onOpenDashboard: () -> Void = {}
    var onSwitchBranch: () -> Void = {}
    var onRevealArtifact: (ChatStore.RunArtifact) -> Void = { _ in }
    /// True while launch restore rebuilds saved tabs. The composer stays typeable so a
    /// draft is never swallowed, but sends and header/empty-state actions stay inert
    /// until restore completes.
    var isSessionRestoreInProgress: Bool = false

    @State private var input: String = ""
    @State private var isFileDropTargeted = false
    @State private var slashActiveIndex = 0
    @State private var slashSkillsExpanded = false
    @State private var slashCommandsExpanded = false
    @State private var toolActivityExpanded = false
    @State private var expandedAssistantTraceIDs: Set<UUID> = []
    @State private var collapsedAssistantTraceIDs: Set<UUID> = []
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var autoScrollTrailingPassRequested = false
    @State private var autoScrollTrailingPerformanceInterval: GrokBuildPerformanceInterval?
    @State private var programmaticScrollReleaseTask: Task<Void, Never>?
    @State private var isProgrammaticTranscriptScroll = false
    @State private var transcriptSessionTransitionInProgress = false
    @State private var lastAutoScroll: Date = .distantPast
    @State private var transcriptIsAttachedToBottom = true
    @State private var transcriptHasUserScrolled = false
    @State private var transcriptUnreadCount = 0
    @State private var transcriptJumpAnnouncementPosted = false
    @State private var lastObservedTranscriptMessageCount = 0
    @State private var wasStreaming = false
    @State private var voiceInput = VoiceInputService()
    @State private var pendingReasoningEffortChange: String?
    // Keep the composer calm. Backend receipts and worker/file evidence live in
    // the optional right-side activity drawer instead of permanent chrome.
    @State private var showActivitySidebar = false
    /// A transcript Activity link may target an older settled turn. The ID is
    /// local UI selection only; its evidence still comes from that turn's
    /// durable checkpoint and trace.
    @State private var selectedActivityMessageID: UUID?
    /// Measured chat-area width driving the Slice 7 responsive policy.
    @State private var chatAreaWidth: Double = .infinity
    /// Hysteresis-backed mount so overlay/dock/strip cannot chase geometry jitter.
    @State private var inspectorPlacement: ResponsiveLayoutPolicy.InspectorPlacement = .dockedColumn
    @State private var toolPillStatus = ToolPillStatus()
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(GrokSettingsKeys.memoryEnabled) private var memoryEnabled = GrokPermissionSettings.defaults.memoryEnabled

    private var browserToolsEnabled: Bool { store.isBuiltInToolEnabled(.browser) }
    private var computerUseEnabled: Bool { store.isBuiltInToolEnabled(.computerUse) }

    private var isFollowingTranscriptBottom: Bool {
        transcriptIsAttachedToBottom || !transcriptHasUserScrolled
    }

    private var allowsTranscriptTextSelection: Bool {
        !ChatTranscriptSelectionPolicy.shouldSuspendSelection(
            isFollowingBottom: isFollowingTranscriptBottom,
            isStreaming: store.isStreaming,
            isSettlingAutoScroll: autoScrollTask != nil
        )
    }

    @State private var cachedCustomSubagentNames: [String] = []
    @State private var showSavedWorkflows = false
    @State private var showDeepResearch = false
    @State private var showSetGoal = false
    @State private var showCreateSkill = false
    @State private var showImagine = false
    @State private var showRecoveryReview = false
    @State private var createSkillName = ""
    @State private var imaginePrompt = ""

    private var slashMatch: (query: String, range: Range<String.Index>)? {
        SlashAutocomplete.match(in: input)
    }

    private var filteredSlashCommands: [SlashCommand] {
        guard let match = slashMatch else { return [] }
        let q = match.query.lowercased()
        return store.availableSlashCommands.filter { $0.name.lowercased().hasPrefix(q) }
    }

    private var slashGroups: (skills: [SlashCommand], commands: [SlashCommand]) {
        SlashAutocompleteGroups.split(filteredSlashCommands)
    }

    private var slashFiltering: Bool {
        !(slashMatch?.query.isEmpty ?? true)
    }

    private var slashMenuEntries: [SlashMenuEntry] {
        SlashAutocompleteGroups.navigableEntries(
            skills: slashGroups.skills,
            commands: slashGroups.commands,
            skillsExpanded: slashSkillsExpanded,
            commandsExpanded: slashCommandsExpanded,
            filtering: slashFiltering
        )
    }

    private var showSlashPopover: Bool {
        !slashMenuEntries.isEmpty && inputFocused
    }

    private var hasThinkingContent: Bool {
        !store.thinkingText.isEmpty || store.thinkingDuration != nil
    }

    private var thinkingMessageID: UUID? {
        guard hasThinkingContent else { return nil }
        return ChatTranscriptLayout.thinkingMessageID(
            messages: store.messages,
            streamingMessageID: store.streamingMessageID
        )
    }

    /// A failed turn removes its empty assistant reply, leaving thinking with
    /// no anchor. Render it at the tail so the diagnostic is not lost.
    private var showThinkingAtTail: Bool {
        hasThinkingContent && thinkingMessageID == nil
    }

    private var toolActivityMessageID: UUID? {
        guard !store.liveToolCalls.isEmpty else { return nil }
        return ChatTranscriptLayout.activeAssistantMessageID(
            messages: store.messages,
            streamingMessageID: store.streamingMessageID
        )
    }

    private var showToolActivityAtTail: Bool {
        !store.liveToolCalls.isEmpty && toolActivityMessageID == nil
    }

    private var thinkingBlock: some View {
        ThinkingBlock(
            summaryChunks: store.reasoningSummaryChunks,
            duration: store.thinkingDuration,
            isExpanded: store.isThinkingExpanded,
            isLive: store.isStreaming && store.thinkingDuration == nil
        ) {
            store.toggleThinkingExpanded()
        }
    }

    private func assistantTurnHeader(
        message: Message,
        isExpanded: Bool,
        trace: AssistantTurnTrace?,
        hasLiveTrace: Bool,
        status: ConversationTurnStatusPresentation?
    ) -> some View {
        Button {
            if isExpanded {
                expandedAssistantTraceIDs.remove(message.id)
                collapsedAssistantTraceIDs.insert(message.id)
            } else {
                collapsedAssistantTraceIDs.remove(message.id)
                expandedAssistantTraceIDs.insert(message.id)
            }
        } label: {
            HStack(spacing: 7) {
                Text(assistantTurnTitle(trace: trace))
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textMuted)
                if let label = assistantTraceSummary(trace: trace, hasLiveTrace: hasLiveTrace) {
                    Text(label)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Palette.textMuted)
                }
                Spacer(minLength: 8)
                if let status {
                    ConversationTurnStatusBadge(presentation: status)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.Palette.textMuted)
        .help(isExpanded ? "Hide thinking and tool use" : "Show thinking and tool use")
        .accessibilityLabel(assistantTurnTitle(trace: trace))
        .accessibilityValue(isExpanded ? "Thinking and tool use expanded" : "Thinking and tool use collapsed")
        .accessibilityHint(isExpanded ? "Hides this turn's thinking and tool receipts." : "Shows this turn's thinking and tool receipts.")
        .accessibilityIdentifier("grok-assistant-trace-\(message.id.uuidString)")
    }

    /// The turn header names the model that actually produced the turn (from the
    /// confirmed execution receipt stamped into the trace), plus the subagent role
    /// when one ran it. Turns without a stamped receipt — old transcripts, or a
    /// model that was never exactly confirmed — keep the neutral "Build agent"
    /// label instead of a guessed name.
    private func assistantTurnTitle(trace: AssistantTurnTrace?) -> String {
        guard let modelName = trace?.modelDisplayName, !modelName.isEmpty else {
            return "Build agent"
        }
        if let agent = trace?.agentName, !agent.isEmpty {
            return "\(modelName) · \(agent)"
        }
        return modelName
    }

    private func assistantTraceSummary(trace: AssistantTurnTrace?, hasLiveTrace: Bool) -> String? {
        if hasLiveTrace && store.isStreaming { return "Live details" }
        guard let trace else { return "Details" }
        var parts: [String] = []
        if let duration = trace.thinkingDuration {
            parts.append("\(max(1, Int(duration.rounded())))s thought")
        } else if !trace.reasoningSummaryChunks.isEmpty {
            parts.append("Thinking")
        }
        if !trace.tools.isEmpty {
            parts.append(ToolActivitySummaryPresentation.summary(for: trace.tools.map {
                .init(
                    title: $0.title,
                    kind: $0.kind ?? "tool",
                    status: $0.status,
                    isFailed: ToolCallTerminalStatus.from(rawStatus: $0.status) == .failed,
                    isRecovered: false
                )
            }))
        }
        return parts.isEmpty ? "Details" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func assistantThinkingDetails(
        message: Message,
        useLiveTrace: Bool,
        hasAnyTrace: Bool
    ) -> some View {
        if useLiveTrace {
            AssistantReasoningTraceView(
                summaryChunks: store.reasoningSummaryChunks,
                duration: store.thinkingDuration,
                emptyMessage: store.isStreaming ? "Waiting for a public reasoning summary." : nil
            )
        } else if let trace = message.assistantTrace,
                  !trace.reasoningSummaryChunks.isEmpty || trace.thinkingDuration != nil {
            AssistantReasoningTraceView(
                summaryChunks: trace.reasoningSummaryChunks,
                duration: trace.thinkingDuration
            )
        } else if !hasAnyTrace {
            AssistantReasoningTraceView(
                summaryChunks: [],
                duration: nil,
                emptyMessage: "No thinking or tool receipts were retained for this earlier turn."
            )
        }
    }

    @ViewBuilder
    private func assistantToolDetails(message: Message, useLiveTrace: Bool) -> some View {
        // Live in-flight rows stay compact. After the turn is no longer streaming,
        // prefer the message trace so settled `resultDetail` is visible. If live
        // receipts outlive the stream, still map their detail through the same
        // bounded extractor.
        if useLiveTrace, store.isStreaming || store.isGrokking {
            AssistantToolTraceView(tools: store.liveToolCalls.map(Self.assistantTraceTool))
        } else if let tools = message.assistantTrace?.tools, !tools.isEmpty {
            AssistantToolTraceView(tools: tools)
        } else if useLiveTrace {
            AssistantToolTraceView(tools: store.liveToolCalls.map(Self.assistantTraceTool))
        }
    }

    private static func assistantTraceTool(_ tool: ChatStore.LiveToolCall) -> AssistantTurnTrace.Tool {
        AssistantTurnTrace.Tool(
            id: tool.id,
            title: tool.title,
            kind: tool.kind,
            status: tool.terminalStatus.map { String(describing: $0).capitalized }
                ?? tool.status.map(ActivitySidebarPresentation.activityStatus)
                ?? "Running",
            mcpServerName: tool.mcpServerName,
            mcpReceiptRole: tool.mcpReceiptRole,
            qualifiedToolName: tool.qualifiedToolName,
            discoveredQualifiedToolNames: tool.discoveredQualifiedToolNames,
            resultDetail: ToolResultPresentation.transcriptOutput(
                detail: tool.detail,
                kind: tool.kind,
                title: tool.title
            ),
            durationMilliseconds: tool.durationMilliseconds
        )
    }

    private var currentAssistantHasText: Bool {
        guard let id = store.streamingMessageID else { return false }
        return store.messages.first(where: { $0.id == id })?.content.isEmpty == false
    }

    private var inlineChangedFilesSummary: ChangedFilesSummaryProjection.Summary? {
        guard let summary = ChangedFilesSummaryProjection.summary(
            snapshot: store.runEvidenceSnapshot,
            diffs: reviewDiffs,
            workspace: store.currentWorkspace?.path
        ), summary.turnAttributedCount > 0 else {
            return nil
        }
        return summary
    }

    /// Git review evidence belongs to the latest settled assistant turn. A
    /// repository-wide change without turn attribution remains header-only.
    private var inlineChangedFilesMessageID: UUID? {
        guard inlineChangedFilesSummary != nil else { return nil }
        return store.messages.last(where: { $0.role == .assistant })?.id
    }

    @ViewBuilder
    private var liveProgressControl: some View {
        if let projection = store.liveRunEvidenceProjection {
            let presentation = LiveProgressPresentation.make(
                projection: projection,
                startedAt: store.turnStartedAt,
                now: Date(),
                hasAssistantText: currentAssistantHasText
            )
            Button {
                setActivitySidebarVisible(true)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.link)
                    Text(presentation.compactText)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: ComposerControlMetrics.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the Run inspector evidence for this live run")
            .accessibilityLabel("Live progress")
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityHint("Opens the generation-bound workers, tools, and receipts in the Run inspector.")
            .accessibilityIdentifier("grok-live-progress")
        } else if store.isGrokking {
            GrokkingIndicator(startedAt: store.turnStartedAt)
                .padding(.leading, 2)
        }
    }

    /// One on-demand evidence dock. The docked form is a true peer surface;
    /// ordinary windows get the same surface as a bounded material overlay.
    @ViewBuilder
    private func activityInspector(docked: Bool) -> some View {
        if docked {
            activityInspectorContent
                .frame(width: ResponsiveLayoutPolicy.activityCanvasWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            activityInspectorContent
                .frame(width: ResponsiveLayoutPolicy.activityCanvasWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .grokGlassSurface(cornerRadius: AppTheme.Radius.composer, shadowed: true)
                .padding(10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var activityInspectorContent: some View {
        ActivitySidebar(
                snapshot: activitySnapshot,
                liveProjection: store.liveRunEvidenceProjection,
                workspace: store.currentWorkspace?.path,
                onClose: {
                    setActivitySidebarVisible(false)
                },
                onContinueAsNew: {
                    Task {
                        _ = await performTranscriptSessionTransition {
                            await store.continueAsNew()
                        }
                    }
                },
                onReviewRecovery: {
                    showRecoveryReview = true
                    Task { await store.reviewRecoveryCandidates() }
                },
                onRevealArtifact: onRevealArtifact,
                inspector: contextInspectorModel
            )
    }

    /// Below the inspector fit threshold the open panel stays mounted as a narrow
    /// trailing strip so run evidence is not fully hidden and widening restores
    /// the full inspector without resetting `showActivitySidebar`.
    private func activityInspectorCollapsedStrip() -> some View {
        VStack(spacing: 10) {
            Button {
                setActivitySidebarVisible(false)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GrokChromeButtonStyle())
            .help("Hide run inspector")
            .accessibilityLabel("Hide run inspector")

            if store.liveRunEvidenceProjection != nil {
                Circle()
                    .fill(AppTheme.Palette.accent)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            } else if activitySnapshot != nil {
                Circle()
                    .fill(activitySnapshot?.outcome == .completionReceiptMissing ? AppTheme.Palette.warning : Color.secondary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            Text(collapsedActivityLabel)
                .font(AppTheme.Typography.captionStrong)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .frame(width: 52)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
        .background(AppTheme.Palette.sidebar)
        .overlay(alignment: .leading) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Worker activity collapsed")
        .accessibilityValue(activityEvidenceAccessibilityValue)
        .accessibilityHint("Widen the window to restore the full run inspector.")
        .accessibilityIdentifier("grok-worker-activity-collapsed")
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var collapsedActivityLabel: String {
        let count = store.liveRunEvidenceProjection?.workers.count
            ?? activitySnapshot?.workers.count
            ?? 0
        return count > 0 ? "Workers \(count)" : "Run"
    }

    var body: some View {
        // P3D: the worker activity canvas overlays in the mid band
        // (900..<1,180 pt chat area), docks at ≥1,180, and collapses below 900.
        HStack(alignment: .top, spacing: 0) {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
            topBar
                .disabled(isSessionRestoreInProgress)

            if let authMsg = store.authRequiredMessage {
                AuthBanner(
                    message: authMsg,
                    onDismiss: { store.authRequiredMessage = nil },
                    onRetry: { Task { await store.retryConnection() } }
                )
            }

            if let error = store.lastError {
                ErrorBanner(message: error)
            }

            if let stalledSince = store.turnStalledSince {
                TurnStalledBanner(since: stalledSince) {
                    store.requestStop()
                }
            }

            if let switchError = store.modelSwitchError {
                ModelSwitchBanner(
                    message: switchError,
                    canStartNewSession: store.modelSwitchNeedsNewSession,
                    onStartNewSession: {
                        Task { await store.resolveModelSwitchByStartingNewSession() }
                    },
                    onDismiss: {
                        store.dismissModelSwitchIssue()
                    }
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if store.showsEmptyTranscriptWelcome {
                            if store.currentWorkspace == nil {
                                noProjectState
                                    .disabled(isSessionRestoreInProgress)
                            } else if case .failed = store.connectionState {
                                EmptyView()
                            } else {
                                WelcomeStateView(
                                    workspaceName: store.currentWorkspace?.displayName ?? "Choose a project to begin"
                                ) { item in
                                    input = item.prompt
                                    inputFocused = true
                                }
                                    .disabled(isSessionRestoreInProgress)
                            }
                        } else if store.messages.isEmpty && store.isResumedSessionTab {
                            restoredEmptyState
                                .disabled(isSessionRestoreInProgress)
                        }

                        ForEach(store.messages) { msg in
                            let persistedTrace = msg.assistantTrace
                            let hasLiveThinking = thinkingMessageID == msg.id
                            let hasLiveTools = toolActivityMessageID == msg.id
                            let hasPersistedThinking = persistedTrace?.reasoningSummaryChunks.isEmpty == false
                                || persistedTrace?.thinkingDuration != nil
                            let hasPersistedTools = persistedTrace?.tools.isEmpty == false
                            let hasAnyTrace = hasLiveThinking || hasLiveTools
                                || hasPersistedThinking || hasPersistedTools
                            let traceExpanded = ChatTranscriptLayout.isTraceExpanded(
                                messageID: msg.id,
                                hasTools: hasLiveTools || hasPersistedTools,
                                explicitlyExpanded: expandedAssistantTraceIDs,
                                explicitlyCollapsed: collapsedAssistantTraceIDs
                            )
                            if msg.role == .assistant {
                                let isLiveTurn = store.isStreaming && msg.id == store.streamingMessageID
                                let turnStatus = ConversationTurnStatusPresentation.make(
                                    isLive: isLiveTurn,
                                    checkpoint: persistedTrace?.checkpoint
                                )
                                ConversationTurnSurface(messageID: msg.id, status: turnStatus) {
                                    ForEach(
                                        ChatTranscriptLayout.identifiedMessageBlocks(
                                            messageID: msg.id,
                                            blocks: ChatTranscriptLayout.messageBlockOrder(
                                                containsAgentHeader: true,
                                                traceExpanded: traceExpanded,
                                                containsThinking: hasLiveThinking || hasPersistedThinking || !hasAnyTrace,
                                                containsToolActivity: hasLiveTools || hasPersistedTools,
                                                containsLiveProgress: msg.id == store.streamingMessageID
                                                    && store.liveRunEvidenceProjection == nil
                                                    && store.isGrokking,
                                                containsPlanSpine: false
                                            )
                                        )
                                    ) { identifiedBlock in
                                        switch identifiedBlock.block {
                                        case .agentHeader:
                                            assistantTurnHeader(
                                                message: msg,
                                                isExpanded: traceExpanded,
                                                trace: persistedTrace,
                                                hasLiveTrace: hasLiveThinking || hasLiveTools,
                                                status: turnStatus
                                            )
                                        case .thinking:
                                            assistantThinkingDetails(
                                                message: msg,
                                                useLiveTrace: hasLiveThinking,
                                                hasAnyTrace: hasAnyTrace
                                            )
                                        case .toolActivity:
                                            assistantToolDetails(message: msg, useLiveTrace: hasLiveTools)
                                        case .planSpine:
                                            EmptyView()
                                        case .liveProgress:
                                            liveProgressControl
                                        case .answer:
                                            MessageBubble(
                                                message: msg,
                                                isStreaming: isLiveTurn,
                                                streamingPresentation: msg.id == store.streamingMessageID
                                                    ? store.streamingPresentation
                                                    : nil,
                                                isLayoutFrozen: transcriptSessionTransitionInProgress,
                                                allowsTextSelection: allowsTranscriptTextSelection
                                            )
                                            .id(msg.id)
                                        }
                                    }

                                    if msg.id == inlineChangedFilesMessageID,
                                       let changedFilesSummary = inlineChangedFilesSummary {
                                        ChangedFilesSummaryCard(
                                            summary: changedFilesSummary,
                                            onOpenReview: {
                                                onOpenTurnReview()
                                                if !isReviewVisible { onToggleReview() }
                                            }
                                        )
                                    }
                                }
                            } else {
                                MessageBubble(
                                    message: msg,
                                    isLayoutFrozen: transcriptSessionTransitionInProgress,
                                    allowsTextSelection: allowsTranscriptTextSelection
                                )
                                .id(msg.id)
                            }
                        }

                        if showThinkingAtTail {
                            thinkingBlock
                        }

                        if showToolActivityAtTail {
                            toolActivityBlock
                        }

                        if let plan = store.pendingExitPlan {
                            PlanReviewCard(plan: plan) { verdict in
                                store.respondToExitPlan(plan, verdict: verdict)
                            }
                        }

                        ForEach(store.pendingQuestions) { question in
                            QuestionCard(
                                request: question,
                                onSubmit: { answers in store.respondToQuestion(question, answers: answers) },
                                onSkip: { store.cancelQuestion(question) }
                            )
                        }

                        ForEach(store.pendingPermissions) { perm in
                            PermissionCard(
                                permission: perm,
                                effectivePermissionMode: store.effectivePermissionMode
                            ) { optionId in
                                store.respondToPermission(perm, with: optionId)
                            }
                        }

                        // A fixed 1pt element at the true bottom. Scrolling to a
                        // dedicated anchor is reliable in a LazyVStack; scrolling to the
                        // last message's id is not when that message is tall and was
                        // just streamed in — which is why long answers stranded below
                        // the fold.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .frame(maxWidth: AppTheme.Layout.conversationMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)
                }
                .coordinateSpace(name: Self.transcriptCoordinateSpace)
                .background(AppTheme.Palette.canvas)
                .onAppear {
                    // Settings navigation and tab restoration recreate ChatView, so
                    // populated transcripts must reopen at the latest answer.
                    scheduleSettledAutoScroll(proxy: proxy)
                }
                .onAppear {
                    transcriptIsAttachedToBottom = true
                    transcriptHasUserScrolled = false
                    transcriptUnreadCount = 0
                    transcriptJumpAnnouncementPosted = false
                    lastObservedTranscriptMessageCount = store.messages.count
                    wasStreaming = store.isStreaming
                }
                .onScrollPhaseChange { _, phase in
                    // Programmatic proxy scrolling can emit a tracking phase as
                    // the layout settles. Only an actual interacting phase can
                    // detach the reader; proxy movement is guarded separately.
                    if phase == .interacting && !isProgrammaticTranscriptScroll {
                        transcriptHasUserScrolled = true
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    ChatTranscriptScrollPolicy.isAttached(
                        distanceFromBottom: max(
                            0,
                            geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
                        )
                    )
                } action: { _, isAttached in
                    guard transcriptHasUserScrolled else { return }
                    transcriptIsAttachedToBottom = isAttached
                    if isAttached {
                        transcriptUnreadCount = 0
                        transcriptJumpAnnouncementPosted = false
                    }
                }
                .onChange(of: store.messages.count) { _, newCount in
                    let delta = max(0, newCount - lastObservedTranscriptMessageCount)
                    lastObservedTranscriptMessageCount = newCount
                    recordTranscriptContentChange(messageCountDelta: delta)
                    if transcriptIsAttachedToBottom || !transcriptHasUserScrolled {
                        scheduleSettledAutoScroll(proxy: proxy)
                    }
                }
                .onChange(of: store.isGrokking) { _, isGrokking in
                    if !transcriptIsAttachedToBottom && isGrokking {
                        recordTranscriptContentChange()
                    } else if transcriptIsAttachedToBottom || !transcriptHasUserScrolled {
                        scheduleSettledAutoScroll(proxy: proxy)
                    }
                }
                .onChange(of: store.isStreaming) { _, isStreaming in
                    if wasStreaming && !isStreaming {
                        if store.latestTurnOutcome != .completionReceiptMissing {
                            let outcome = store.latestTurnOutcome?.displayName ?? "Turn ended"
                            VoiceOverAnnouncer.announce("Turn finished. \(outcome).")
                        }
                    }
                    wasStreaming = isStreaming
                    if !isStreaming, (transcriptIsAttachedToBottom || !transcriptHasUserScrolled) {
                        // The final provider event can precede the last rich-text layout.
                        scheduleSettledAutoScroll(
                            proxy: proxy,
                            performanceInterval: GrokBuildPerformance.begin(.finalChunkToSettledRender)
                        )
                    }
                }
                // Follows streamed thinking and answer. A streaming answer grows
                // the existing message (no count/isGrokking change), so settlement
                // still keeps the true bottom attached. An already-attached viewport
                // skips the per-chunk scrollTo; unattached first-follow stays throttled.
                .onChange(of: store.streamRevision) { _, _ in
                    guard transcriptIsAttachedToBottom || !transcriptHasUserScrolled else {
                        recordTranscriptContentChange()
                        return
                    }
                    let now = Date()
                    if ChatTranscriptScrollPolicy.shouldPerformImmediateFollowScroll(
                        isAttached: transcriptIsAttachedToBottom
                    ), now.timeIntervalSince(lastAutoScroll) > 0.08 {
                        lastAutoScroll = now
                        scrollToBottom(proxy: proxy, instant: true)
                    }
                    scheduleSettledAutoScroll(proxy: proxy)
                }
                .onChange(of: toolActivityExpanded) { _, _ in
                    // Expanding tool receipts changes the LazyVStack's height
                    // without changing the message or stream revision. Keep a
                    // reader already attached to the tail attached after that
                    // layout mutation, while respecting an intentional manual
                    // scroll away from the latest content.
                    guard transcriptIsAttachedToBottom || !transcriptHasUserScrolled else {
                        return
                    }
                    scheduleSettledAutoScroll(proxy: proxy)
                }
                .onChange(of: transcriptSessionTransitionInProgress) { _, isInProgress in
                    guard !isInProgress, !store.messages.isEmpty else { return }
                    scheduleSettledAutoScroll(proxy: proxy)
                }

                if !transcriptIsAttachedToBottom {
                    Button {
                        transcriptIsAttachedToBottom = true
                        transcriptHasUserScrolled = true
                        transcriptUnreadCount = 0
                        transcriptJumpAnnouncementPosted = false
                        scrollToBottom(proxy: proxy)
                        VoiceOverAnnouncer.announce("Jumped to latest content.")
                    } label: {
                        Label(
                            ChatTranscriptScrollPolicy.jumpLabel(unreadCount: transcriptUnreadCount),
                            systemImage: "arrow.down.to.line"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Return to the latest transcript content")
                    .accessibilityLabel("Jump to latest")
                    .accessibilityValue(
                        transcriptUnreadCount > 0
                            ? "\(transcriptUnreadCount) new content"
                            : "Latest content is below"
                    )
                    .accessibilityHint("Resumes following the latest response.")
                    .accessibilityIdentifier("grok-jump-to-latest")
                    .accessibilitySortPriority(3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Conversation transcript")
            .accessibilityHint(
                transcriptIsAttachedToBottom
                    ? "Reading the latest content. Scroll up to pause following new content."
                    : "Detached from the latest content. Use Jump to latest to resume following."
            )
            .accessibilitySortPriority(2)
            .focusSection()

            if let goal = store.goalState {
                GoalBanner(state: goal, store: store)
                    .padding(.horizontal, 12)
            }

            if let aside = store.btwAsideText {
                BtwAsideBanner(text: aside) {
                    store.clearBtwAside()
                }
                .padding(.horizontal, 12)
            }

            if store.continuityRequiresRecovery {
                ContinuityStatusBanner(
                    kind: .needsRecovery,
                    message: "This saved conversation can’t be resumed — Send starts a fresh thread.",
                    onReview: {
                        showRecoveryReview = true
                        Task { await store.reviewRecoveryCandidates() }
                    }
                )
                .padding(.horizontal, 12)
            }

            composerContextBar
            composer
                .accessibilitySortPriority(1)
                .focusSection()
            }

            // F5C responsive order: below 960 the evidence drawer collapses to a
            // named strip; 960..<1,320 overlays; ≥1,320 docks. The user's
            // open state is preserved so widening restores the full panel.
            if showActivitySidebar, inspectorPlacement == .overlay {
                activityInspector(docked: false)
            }
        }

        // F5C: at ≥1,320 pt the open activity drawer is a
        // real third column — same panel and state, no overlap with the transcript.
        if showActivitySidebar, inspectorPlacement == .dockedColumn {
            activityInspector(docked: true)
        }

        // Below 960 pt keep a compact collapsed strip instead of hiding evidence.
        if showActivitySidebar, inspectorPlacement == .collapsedStrip {
            activityInspectorCollapsedStrip()
        }
        }
        // W-6: the measurement wraps the whole chat area including the docked
        // column — measuring only the transcript stack would shrink the width
        // at the moment of docking and oscillate across the 1,180-pt threshold.
        // 2026-08-14: also ignore sub-point jitter and apply hysteresis so a
        // committed width cannot flip overlay/dock/strip every frame.
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.width
        } action: { width in
            guard ResponsiveLayoutPolicy.shouldCommitMeasuredWidth(
                current: chatAreaWidth,
                next: width
            ) else { return }
            chatAreaWidth = width
            inspectorPlacement = ResponsiveLayoutPolicy.inspectorPlacement(
                chatAreaWidth: width,
                current: inspectorPlacement
            )
        }
        .onAppear {
            inputFocused = true
        }
        .onDisappear {
            cancelSettledAutoScroll()
            programmaticScrollReleaseTask?.cancel()
            programmaticScrollReleaseTask = nil
        }
        .onChange(of: store.liveToolCalls.isEmpty) { _, isEmpty in
            if isEmpty { toolActivityExpanded = false }
        }
        .onChange(of: store.streamingMessageID) { _, id in
            // Tool visibility (owner ask, 2026-08-08): a live turn opens its
            // trace so running tool calls are visible as they happen, not
            // hidden behind a disclosure. Collapsing manually still sticks
            // for the rest of the turn.
            if let id, store.isStreaming {
                collapsedAssistantTraceIDs.remove(id)
                expandedAssistantTraceIDs.insert(id)
            }
        }
        .onChange(of: store.connectionState) { _, state in
            if case .failed = state {
                VoiceOverAnnouncer.announce("Agent connection failed. Review the connection error.")
            }
        }
        .onChange(of: store.continuityRequiresRecovery) { _, needsRecovery in
            if needsRecovery {
                VoiceOverAnnouncer.announce("Conversation continuity needs attention. Send is blocked until recovery.")
            }
        }
        .onChange(of: store.modelSwitchError) { _, error in
            if error != nil {
                VoiceOverAnnouncer.announce("Model change was not confirmed. Review the model status.")
            }
        }
        .onChange(of: store.runEvidenceSnapshot?.outcome) { _, outcome in
            guard let outcome,
                  [.failed, .cancelled, .completionReceiptMissing, .userStopped].contains(outcome),
                  !showActivitySidebar else { return }
            setActivitySidebarVisible(true)
            let announcement = switch outcome {
            case .failed:
                "Turn failed. Run inspector opened with the provider or CLI error."
            case .cancelled:
                "Turn cancelled. Run inspector opened with the preserved cancellation and tool receipts."
            case .userStopped:
                "Stopped by you. Run inspector opened with the local stop outcome and next action."
            case .completionReceiptMissing:
                "Completion receipt missing. Run inspector opened with the preserved run evidence."
            case .completed:
                "Turn completed."
            }
            VoiceOverAnnouncer.announce(announcement)
        }
        .confirmationDialog(
            "Change reasoning effort?",
            isPresented: Binding(
                get: { pendingReasoningEffortChange != nil },
                set: { if !$0 { pendingReasoningEffortChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Summarize & Restart") {
                if let effort = pendingReasoningEffortChange {
                    Task {
                        await store.applyReasoningEffort(effort, strategy: .summarizeAndRestart)
                    }
                }
                pendingReasoningEffortChange = nil
            }
            Button("Restart", role: .destructive) {
                if let effort = pendingReasoningEffortChange {
                    Task {
                        await store.applyReasoningEffort(effort, strategy: .restart)
                    }
                }
                pendingReasoningEffortChange = nil
            }
            Button("Cancel", role: .cancel) {
                pendingReasoningEffortChange = nil
            }
        } message: {
            if let effort = pendingReasoningEffortChange {
                Text("Apply \(store.reasoningEffortDisplayName(effort)) when Grok restarts. Summarize & restart runs /compact first to preserve context.")
            }
        }
        .sheet(isPresented: $showSavedWorkflows) {
            SavedWorkflowsPanel(projectRoot: store.currentWorkspace?.path) { workflow, argsJSON in
                Task {
                    let args = Self.parseWorkflowArgsJSON(argsJSON)
                    _ = await sendWithTranscriptSessionTransition {
                        await store.launchSavedWorkflow(name: workflow.name, args: args)
                    }
                }
            }
        }
        .sheet(isPresented: $showDeepResearch) {
            DeepResearchSheet { query in
                Task {
                    _ = await sendWithTranscriptSessionTransition {
                        await store.startDeepResearch(query)
                    }
                }
            }
        }
        .sheet(isPresented: $showSetGoal) {
            SetGoalSheet { objective, budget in
                Task {
                    _ = await sendWithTranscriptSessionTransition {
                        await store.setGoal(objective, budget: budget)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSkill) {
            createSkillSheet
        }
        .sheet(isPresented: $showImagine) {
            imagineSheet
        }
        .sheet(isPresented: $showRecoveryReview) {
            SessionRecoveryReviewSheet(store: store) {
                showRecoveryReview = false
            }
        }
        .onAppear {
            input = store.composerDraft
        }
        .task(id: promptMCPRefreshIdentity) {
            await store.refreshPromptMCPOptions()
        }
        .onChange(of: input) { _, newValue in
            store.composerDraft = newValue
        }
        .onChange(of: store.connectionState) { _, newState in
            if case .ready = newState {
                // Clear stale auth message if the CLI became ready again
                if store.authRequiredMessage != nil {
                    store.authRequiredMessage = nil
                }
                Task { await store.refreshPromptMCPOptions() }
            } else if case .failed(let msg) = newState,
                      (msg.lowercased().contains("login") || msg.lowercased().contains("auth")),
                      store.authRequiredMessage == nil {
                store.authRequiredMessage = msg
            }
        }
    }

    private var topBar: some View {
        ChatTopBar(
            store: store,
            sessionTitle: sessionTitle,
            isSidebarVisible: isSidebarVisible,
            onToggleSidebar: onToggleSidebar,
            onBrowseSessions: onBrowseSessions,
            onOpenDashboard: onOpenDashboard,
            onForkSession: onForkSession,
            onSwitchBranch: onSwitchBranch,
            onOpenProjectIn: onOpenProjectIn,
            showSetGoal: $showSetGoal,
            createSkillName: $createSkillName,
            showCreateSkill: $showCreateSkill
        ) {
            tasksStatusPill
        } reviewToggle: {
            headerReviewToggle
        } inspectorToggle: {
            activitySidebarToggle
        }
    }

    private var restoredEmptyState: some View {
        Text("Loading saved conversation…")
            .font(.system(size: 20, weight: .semibold))
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
            .padding(.horizontal, 32)
            .accessibilityLabel("Loading saved conversation")
            .accessibilityIdentifier("grok-restored-conversation-loading")
    }

    private var noProjectState: some View {
        VStack(spacing: 18) {
            GrokBrandMarkView()
            VStack(spacing: 6) {
                Text("Welcome to GrokBuild")
                    .font(.title2.weight(.semibold))
                Text("Add a project folder to start a Grok session — then plan, build, and explore your code together.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAddProject) {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(GrokProminentButtonStyle())
            .controlSize(.large)
            .help("Choose a folder to work in")
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    static let bottomAnchorID = "transcript-bottom-anchor"
    static let transcriptCoordinateSpace = "grokbuild-transcript"

    /// Resume and Continue-as-New both remove recovery controls while process and
    /// continuity state changes. Give selectable rich transcript content its own
    /// preceding transaction, then restore it only after the operation settles.
    /// This prevents macOS 26 SelectionOverlay updates from sharing a transaction
    /// with LazyVStack identity and control removal.
    @MainActor
    private func performTranscriptSessionTransition(
        _ operation: @MainActor () async -> Bool
    ) async -> Bool {
        guard !transcriptSessionTransitionInProgress else { return false }
        cancelSettledAutoScroll()
        transcriptSessionTransitionInProgress = true
        await Task.yield()
        let result = await operation()
        await Task.yield()
        transcriptSessionTransitionInProgress = false
        return result
    }

    @MainActor
    private func sendWithTranscriptSessionTransition(
        _ operation: @MainActor () async -> Bool
    ) async -> Bool {
        if store.continuityRequiresRecovery {
            return await performTranscriptSessionTransition(operation)
        }
        return await operation()
    }

    private func cancelSettledAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTrailingPassRequested = false
    }

    private func recordTranscriptContentChange(messageCountDelta: Int = 0) {
        // Stream revisions can arrive once per chunk. One detached response is
        // one unread item; message-count changes may add their exact delta.
        let increment = messageCountDelta > 0
            ? messageCountDelta
            : (transcriptUnreadCount == 0 ? 1 : 0)
        transcriptUnreadCount = ChatTranscriptScrollPolicy.unreadCount(
            current: transcriptUnreadCount,
            messageCountDelta: increment,
            contentChanged: increment > 0,
            isAttached: transcriptIsAttachedToBottom
        )
        guard !transcriptIsAttachedToBottom, !transcriptJumpAnnouncementPosted else { return }
        transcriptJumpAnnouncementPosted = true
        VoiceOverAnnouncer.announce("New transcript content is available. Jump to latest.")
    }

    private func scrollToBottom(proxy: ScrollViewProxy, instant: Bool = false) {
        guard !store.messages.isEmpty else { return }
        isProgrammaticTranscriptScroll = true
        programmaticScrollReleaseTask?.cancel()
        programmaticScrollReleaseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            isProgrammaticTranscriptScroll = false
        }
        // Instant while streaming (animating every ~80ms would stutter); a gentle ease
        // for one-off jumps like a finished turn or a newly-added message.
        if instant || reduceMotion || store.isStreaming {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func scheduleSettledAutoScroll(
        proxy: ScrollViewProxy,
        performanceInterval: GrokBuildPerformanceInterval? = nil
    ) {
        guard !transcriptSessionTransitionInProgress else {
            performanceInterval?.end()
            return
        }
        // Restore, resume, and final rich-text settlement can all publish several
        // state milestones in one window. Keep one bounded settlement task instead
        // of cancel/restarting six ScrollViewProxy passes for every milestone.
        guard autoScrollTask == nil else {
            autoScrollTrailingPassRequested = true
            if let performanceInterval {
                autoScrollTrailingPerformanceInterval?.end()
                autoScrollTrailingPerformanceInterval = performanceInterval
            }
            return
        }
        autoScrollTrailingPassRequested = false
        autoScrollTask = Task { @MainActor in
            defer {
                performanceInterval?.end()
                autoScrollTrailingPerformanceInterval?.end()
                autoScrollTrailingPerformanceInterval = nil
                autoScrollTrailingPassRequested = false
                autoScrollTask = nil
            }
            for gap in ChatAutoScrollPolicy.layoutSettleGapsMilliseconds {
                if gap > 0 {
                    try? await Task.sleep(for: .milliseconds(gap))
                } else {
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                guard transcriptIsAttachedToBottom || !transcriptHasUserScrolled else {
                    return
                }
                lastAutoScroll = Date()
                scrollToBottom(proxy: proxy, instant: true)
            }
            let shouldRunTrailingPass = autoScrollTrailingPassRequested
            if shouldRunTrailingPass,
               transcriptIsAttachedToBottom || !transcriptHasUserScrolled {
                lastAutoScroll = Date()
                scrollToBottom(proxy: proxy, instant: true)
            }
        }
    }

    /// Skill + research + imagine chips in curated order, shown as one horizontal bar.
    private var composerChips: [SlashCommand] {
        SkillSlashCommands.filter(store.availableSlashCommands)
            + ResearchSlashCommands.filter(store.availableSlashCommands)
            + ImagineSlashCommands.filter(store.availableSlashCommands)
    }

    private var promptMCPRefreshIdentity: String {
        let workspace = store.currentWorkspace?.id.uuidString ?? "no-workspace"
        let tab = store.tabSessionID?.uuidString ?? "no-tab"
        return "\(workspace):\(tab)"
    }

    private var toolActivityBlock: some View {
        ToolActivityGroup(
            tools: store.liveToolCalls,
            turnOutcome: store.latestTurnOutcome,
            isExpanded: toolActivityExpanded
        ) {
            toolActivityExpanded.toggle()
        }
    }

    @ViewBuilder
    private var composerContextBar: some View {
        if let workspace = store.currentWorkspace {
            HStack(spacing: 7) {
                Label(workspace.displayName, systemImage: "folder")
                    .lineLimit(1)
                    .accessibilityIdentifier("grok-composer-workspace-chip")

                Text("·")
                    .foregroundStyle(.tertiary)

                Button(action: onSwitchBranch) {
                    Label(
                        GitService.currentBranch(in: workspace.path) ?? "Choose branch",
                        systemImage: "arrow.triangle.branch"
                    )
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Switch branch or worktree")
                .accessibilityIdentifier("grok-composer-branch-chip")

                Spacer(minLength: 0)

                if !store.continuityRequiresRecovery,
                   store.continuityIsResuming,
                   store.isResumedSessionTab {
                    LaunchSessionChoices(
                        onResumeCurrent: {
                            Task {
                                _ = await performTranscriptSessionTransition {
                                    await store.resumeTaskSession()
                                }
                            }
                        },
                        onStartNew: onNewSession,
                        onBrowseOld: onBrowseSessions
                    )
                }
            }
            .font(AppTheme.Typography.label)
            .foregroundStyle(.secondary)
            .padding(.horizontal, ComposerDensityPolicy.outerHorizontalPadding + 2)
            .frame(maxWidth: AppTheme.Layout.composerMaxWidth, minHeight: 24, alignment: .leading)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Composer project context")
        }
    }

    private var composer: some View {
        ChatComposer(
            store: store,
            input: $input,
            isFileDropTargeted: $isFileDropTargeted,
            inputFocused: $inputFocused,
            showSlashPopover: showSlashPopover,
            slashMenuEntries: slashMenuEntries,
            slashActiveIndex: slashActiveIndex,
            onSelectSlash: pickSlashCommand,
            onShowMoreSkills: {
                slashSkillsExpanded = true
                clampSlashActiveIndex()
            },
            onShowMoreCommands: {
                slashCommandsExpanded = true
                clampSlashActiveIndex()
            },
            onSubmit: submit,
            onActivateSlash: { activateSlashEntry(at: $0) },
            onMoveSlashSelection: { moveSlashSelection(by: $0) },
            onInputChanged: {
                slashActiveIndex = 0
                slashSkillsExpanded = false
                slashCommandsExpanded = false
            },
            onPreviousHistory: {
                guard let prev = store.previousHistory(from: input) else { return false }
                input = prev
                return true
            },
            onNextHistory: {
                guard let next = store.nextHistory(from: input) else { return false }
                input = next
                return true
            },
            onFileDrop: handleFileDrop
        ) {
            promptQueueBar
        } primaryControls: {
            composerPrimaryControls
        } actionControls: {
            composerActionControls
        }
    }

    private var composerPrimaryControls: some View {
        HStack(spacing: 9) {
            composerAddMenu
            if !store.availableModes.isEmpty {
                modeSelector
            }
        }
    }

    /// Codex parity Slice 4: the single add/context menu. Files, MCP
    /// connections, skills/workflows, and the Browser/Computer Use project
    /// tools all attach or launch from here; selected files and MCPs render as
    /// chips inside the composer envelope above the text area.
    private var composerAddMenu: some View {
        Menu {
            Button {
                chooseFiles()
            } label: {
                Label("Attach Files…", systemImage: "paperclip")
            }

            Section("MCP connections") {
                if store.promptMCPInventoryIsLoading && store.attachablePromptMCPOptions.isEmpty {
                    Text("Checking connections…")
                } else if store.attachablePromptMCPOptions.isEmpty {
                    Text(store.promptMCPInventoryUnavailable ? "MCP connections unavailable" : "No connected MCPs")
                } else {
                    ForEach(store.attachablePromptMCPOptions) { option in
                        Button {
                            store.togglePromptMCPAttachment(named: option.name)
                        } label: {
                            Label(
                                option.name,
                                systemImage: store.selectedPromptMCPNames.contains(option.name)
                                    ? "checkmark.circle.fill"
                                    : (option.isReady ? "circle" : "circle.dashed")
                            )
                        }
                        .disabled(store.isStreaming || store.isPreparingSubmit)
                        .help(option.detail)
                    }
                }
                Button {
                    Task { await store.refreshPromptMCPOptions(force: true) }
                } label: {
                    Label("Refresh Connections", systemImage: "arrow.clockwise")
                }
            }

            Section("Skills and workflows") {
                Button {
                    showSavedWorkflows = true
                } label: {
                    Label("Saved Workflows…", systemImage: "doc.text")
                }
                .disabled(store.isStreaming || store.currentWorkspace == nil)

                if composerChips.isEmpty {
                    Button {
                        input = "/"
                        inputFocused = true
                    } label: {
                        Label("Browse commands with /", systemImage: "text.cursor")
                    }
                } else {
                    ForEach(composerChips) { command in
                        Button {
                            Task { await handleComposerChip(command) }
                        } label: {
                            Label(
                                command.name.replacingOccurrences(of: "-", with: " ").capitalized,
                                systemImage: "hammer"
                            )
                        }
                        .disabled(store.isStreaming || store.currentWorkspace == nil)
                    }
                }
            }

            Section("Project tools") {
                browserStatusIndicator
                computerUseStatusIndicator
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(store.selectedPromptMCPNames.isEmpty ? Color.secondary : AppTheme.Palette.accent)
        .help("Add files, MCP connections, skills, and project tools")
        .accessibilityLabel("Add context")
        .accessibilityValue(
            "\(store.fileAttachments.count) files, \(store.selectedPromptMCPNames.count) MCPs attached"
        )
        .accessibilityHint("Attach files or MCP connections, insert skills and workflows, or manage Browser Tools and Computer Use.")
        .accessibilityIdentifier("grok-composer-add-menu")
        .disabled(store.isPreparingSubmit)
        // The Browser/Computer Use pill inputs previously refreshed from the
        // project status row; the add menu is their surviving surface.
        .task(id: store.currentWorkspace?.id) {
            await refreshToolPillStatus()
        }
        .task(id: store.connectionState) {
            await refreshToolPillStatus()
        }
    }

    private var composerActionControls: some View {
        HStack(spacing: 9) {
            modelSelector
            MicButton(voice: voiceInput, input: $input)
            sessionActionButton
        }
    }

    /// Contextual header Review control (Codex parity Slice 2). ChatView still
    /// owns the count and visibility; `ChatHeaderReviewToggle` renders the control.
    @ViewBuilder
    private var headerReviewToggle: some View {
        ChatHeaderReviewToggle(
            // When the latest turn owns an inline changed-files handoff, that is
            // the one closed-state Review entry. The header reappears to close an
            // open pane, or for repository-wide changes that have no turn owner.
            reviewFileCount: inlineChangedFilesSummary != nil && !isReviewVisible
                ? 0
                : reviewFileCount,
            isReviewVisible: isReviewVisible,
            onToggleReview: onToggleReview
        )
    }

    private func setActivitySidebarVisible(_ visible: Bool) {
        if visible && !showActivitySidebar {
            selectedActivityMessageID = nil
        }
        guard showActivitySidebar != visible else { return }
        if reduceMotion {
            showActivitySidebar = visible
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showActivitySidebar = visible
            }
        }
    }

    private var runInspectorQuickLook: RunInspectorQuickLook.Fact {
        RunInspectorQuickLook.make(
            inspector: contextInspectorModel,
            modelLabel: store.sessionReceiptCompactLabel,
            tokenCount: activitySnapshot?.usage.totalTokens
        )
    }

    @ViewBuilder
    private var activitySidebarToggle: some View {
        if activitySnapshot != nil || store.liveRunEvidenceProjection != nil || showActivitySidebar {
            let look = runInspectorQuickLook
            Menu {
                Section(look.phase) {
                    ForEach(Array(look.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                if contextInspectorModel.subagents != nil || showActivitySidebar {
                    Divider()
                    Button(showActivitySidebar ? "Hide run activity" : "Show run activity") {
                        setActivitySidebarVisible(!showActivitySidebar)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    TitlebarGlyph(systemName: "sidebar.right")
                    if let snapshot = activitySnapshot {
                        Circle()
                            .fill(snapshot.outcome == .completionReceiptMissing ? AppTheme.Palette.warning : Color.secondary)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                    } else if store.liveRunEvidenceProjection != nil {
                        Circle()
                            .fill(AppTheme.Palette.accent)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 28, height: TitlebarMetrics.height)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(.regular)
            .foregroundStyle(AppTheme.Palette.titlebarControl)
            .help("Run inspector")
            .accessibilityLabel("Run inspector")
            .accessibilityValue(activityEvidenceAccessibilityValue)
            .accessibilityHint("Quick look at the current run. Opens the on-demand evidence drawer.")
            .accessibilityIdentifier("grok-run-inspector-toggle")
        }
    }

    /// MCP servers actually evidenced by tool receipts: the live projection's
    /// tool receipts mid-turn, else the latest assistant trace after settlement.
    /// Requested attachments never enter this list (Slice 11 evidence rule).
    private var evidencedMCPServers: [String] {
        if let live = store.liveRunEvidenceProjection {
            return live.tools.compactMap {
                $0.mcpReceiptRole == .discovery ? nil : $0.mcpServerName
            }
        }
        if let trace = activityTrace {
            return trace.tools.compactMap {
                $0.mcpReceiptRole == .discovery ? nil : $0.mcpServerName
            }
        }
        return []
    }

    private var currentMCPToolReceipts: [ContextInspectorProjection.MCPToolReceipt] {
        if let live = store.liveRunEvidenceProjection {
            return live.tools.map {
                .init(
                    id: $0.id,
                    role: $0.mcpReceiptRole,
                    qualifiedToolName: $0.qualifiedToolName,
                    serverName: $0.mcpServerName,
                    discoveredQualifiedToolNames: $0.discoveredQualifiedToolNames,
                    statusLabel: $0.status,
                    isSettled: !$0.isActive
                )
            }
        }
        guard let trace = activityTrace else {
            return []
        }
        return trace.tools.map {
            .init(
                id: $0.id,
                role: $0.mcpReceiptRole,
                qualifiedToolName: $0.qualifiedToolName,
                serverName: $0.mcpServerName,
                discoveredQualifiedToolNames: $0.discoveredQualifiedToolNames,
                statusLabel: $0.status,
                isSettled: true
            )
        }
    }

    private var activityRequestedMCPNames: [String] {
        if store.liveRunEvidenceProjection != nil || store.runEvidenceSnapshot != nil {
            return store.currentTurnRequestedMCPNames
        }
        if let requested = activityTrace?.checkpoint?.requestedToolFamilies {
            return requested
        }
        return Array(
            Set(store.selectedPromptMCPOptions.map(\.name))
                .union(store.enabledBuiltInToolNames)
        ).sorted()
    }

    /// Codex parity Slice 5: the compact inspector's presentation model, built
    /// from existing authorities only.
    private var contextInspectorModel: ContextInspectorProjection.Model {
        let computerUseState: String? = store.mcpServerStatus(named: "grokbuild-computer-use")
            .map(\.state.displayName)
        return ContextInspectorProjection.model(
            live: store.liveRunEvidenceProjection,
            snapshot: activitySnapshot,
            attachmentNames: activityAttachmentNames,
            requestedMCPNames: activityRequestedMCPNames,
            evidencedMCPServers: evidencedMCPServers,
            computerUseConfigured: toolPillStatus.computerUseAvailable,
            computerUseStateLabel: computerUseState,
            configuredMCPNames: store.promptMCPOptions.map(\.name),
            mcpProcessStatuses: store.mcpServerStatuses,
            requestedQualifiedToolNames: MCPQualifiedToolIdentity.names(
                in: store.messages.last(where: { $0.role == .user })?.content
            ),
            mcpToolReceipts: currentMCPToolReceipts
        )
    }

    private var activityEvidenceAccessibilityValue: String {
        if let snapshot = activitySnapshot {
            return "Settled: \(snapshot.outcome.displayName)"
        }
        if store.liveRunEvidenceProjection != nil {
            return "Live run evidence, not settled"
        }
        return "No run evidence"
    }

    /// The current in-memory settlement wins. During a live run, no prior
    /// checkpoint is allowed to masquerade as current evidence. Once idle,
    /// Activity falls back to the selected (or latest) durable assistant trace.
    private var activitySnapshot: RunEvidenceSnapshot? {
        if selectedActivityMessageID != nil,
           store.liveRunEvidenceProjection == nil,
           let trace = activityTrace,
           let checkpoint = trace.checkpoint {
            return checkpoint.restoredRunEvidenceSnapshot(settledTools: trace.tools)
        }
        if let snapshot = store.runEvidenceSnapshot { return snapshot }
        guard store.liveRunEvidenceProjection == nil,
              let trace = activityTrace,
              let checkpoint = trace.checkpoint else { return nil }
        return checkpoint.restoredRunEvidenceSnapshot(settledTools: trace.tools)
    }

    private var activityTrace: AssistantTurnTrace? {
        if let selectedActivityMessageID,
           let selected = store.messages.first(where: {
               $0.id == selectedActivityMessageID && $0.role == .assistant
           })?.assistantTrace,
           selected.checkpoint != nil {
            return selected
        }
        return store.messages.last(where: {
            $0.role == .assistant && $0.assistantTrace?.checkpoint != nil
        })?.assistantTrace
    }

    private var activityAttachmentNames: [String] {
        if store.liveRunEvidenceProjection != nil || store.runEvidenceSnapshot != nil {
            return store.currentTurnAttachmentNames
        }
        if let retained = activityTrace?.checkpoint?.attachmentNames {
            return retained
        }
        return []
    }

    private static func parseWorkflowArgsJSON(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    @ViewBuilder
    private var tasksStatusPill: some View {
        let activities = store.backgroundActivities
        let unboundSpawns = store.unboundSubagentSpawnedEvents
        let scheduled = activities.filter { $0.kind == .scheduled }
        let background = activities.filter { $0.kind == .backgroundCommand }
        let monitors = activities.filter { $0.kind == .monitor }
        let subagents = activities.filter { $0.kind == .subagent }
        let count = activities.count + unboundSpawns.count
        let available = store.hasLoopCommand
        let hasActiveSchedule = store.runtimeLease != nil
        let title = count > 0 ? "Tasks (\(count))" : "Tasks"

        if count > 0 || hasActiveSchedule {
        Menu {
            Section("Runtime") {
                if let lease = store.runtimeLease {
                    Text("Runtime pinned — \(lease.activeScheduleCount) active schedule\(lease.activeScheduleCount == 1 ? "" : "s") keep this session connected")
                    Text("Backend \(lease.backendSessionID) • generation \(lease.processGeneration)")
                    Text("Last scheduler receipt: \(lease.lastSchedulerReceiptAt.formatted(date: .abbreviated, time: .shortened))")
                    if let next = lease.nextScheduledCheckpointAt {
                        Text("Next checkpoint: \(next.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text(lease.isTurnActive
                        ? "Stop releases this lease; closing or quitting stops scheduled work."
                        : "Cancel schedules before closing; schedules require this app process.")
                } else {
                    Text("Not runtime pinned — no live schedule inventory is retaining this process.")
                    Text("Restored or cached task metadata cannot create a lease; refresh against the live backend.")
                }
            }

            if activities.isEmpty && unboundSpawns.isEmpty {
                Button("No background tasks") {}
                    .disabled(true)
            } else {
                if !scheduled.isEmpty {
                    Section("Scheduled") {
                        ForEach(scheduled) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !background.isEmpty {
                    Section("Background commands") {
                        ForEach(background) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !monitors.isEmpty {
                    Section("Monitors") {
                        ForEach(monitors) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !subagents.isEmpty || !unboundSpawns.isEmpty {
                    Section("Subagents") {
                        ForEach(subagents) { activity in
                            backgroundActivityMenu(activity)
                        }
                        ForEach(unboundSpawns, id: \.childID) { event in
                            unboundSpawnMenu(event)
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await store.refreshScheduledTasks() }
            } label: {
                Label("Refresh Tasks", systemImage: "arrow.clockwise")
            }
            .disabled(store.isStreaming)

            Button("Type /loop <interval> <prompt> to schedule") {}
                .disabled(true)
        } label: {
            HStack(spacing: 3) {
                TitlebarGlyph(
                    systemName: hasActiveSchedule ? "clock.badge.checkmark" : "clock.badge",
                    pointSize: 12,
                    color: hasActiveSchedule
                        ? AppTheme.Palette.warningNSColor
                        : AppTheme.Palette.titlebarControlNSColor
                )
                if count > 0 {
                    Text("\(count)")
                        .font(AppTheme.Typography.caption)
                }
            }
            .frame(minWidth: 22, minHeight: 22)
            .contentShape(Rectangle())
            .foregroundStyle(hasActiveSchedule ? AppTheme.Palette.warning : AppTheme.Palette.titlebarControl)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help(available
            ? "Background tasks observed in this session; active schedules visibly pin their exact live runtime."
            : "Background tasks mirror — refresh to query grok; cached metadata never pins runtime.")
        .accessibilityLabel(hasActiveSchedule
            ? "Background tasks, runtime pinned by active schedule"
            : "Background tasks, runtime not pinned")
        .accessibilityValue(title)
        .accessibilityIdentifier("grok-tasks-status")
        }
    }

    @ViewBuilder
    private func backgroundActivityMenu(_ activity: BackgroundActivity) -> some View {
        if activity.kind == .scheduled, let task = activity.scheduledTask {
            Menu(taskMenuTitle(task)) {
                Text(task.prompt.isEmpty ? "(no prompt)" : task.prompt)
                if let next = task.nextFireAt {
                    Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await store.cancelScheduledTask(task.id) }
                } label: {
                    Label("Cancel Task", systemImage: "trash")
                }
            }
        } else {
            Menu(backgroundActivityTitle(activity)) {
                let detail = ActivitySidebarPresentation.activityDetail(activity)
                if !detail.isEmpty {
                    Text(detail)
                }
                Text("Status: \(ActivitySidebarPresentation.activityStatus(activity.status))")
            }
        }
    }

    private func backgroundActivityTitle(_ activity: BackgroundActivity) -> String {
        let title = ActivitySidebarPresentation.activityTitle(activity)
        return "\(title) · \(ActivitySidebarPresentation.activityStatus(activity.status))"
    }

    @ViewBuilder
    private func unboundSpawnMenu(_ event: SubagentSpawnedEvent) -> some View {
        let worker = RunEvidenceSnapshot.unboundWorker(
            from: event,
            rolesByName: store.subagentRoleModelsByName
        )
        Menu("\(worker.title) · No final report") {
            if let model = event.modelID, !model.isEmpty {
                Text("Model: \(model)")
            }
            if let description = event.description, !description.isEmpty {
                Text(description)
            }
            Text("Child: \(event.childID)")
            Text("Status: Unbound — no spawn row matched")
        }
    }

    private var promptQueueBar: some View {
        HStack(spacing: 8) {
            Label("Queue (\(store.promptQueue.count))", systemImage: "tray.full")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(Array(store.promptQueue.enumerated()), id: \.offset) { index, prompt in
                    Menu(prompt.count > 40 ? String(prompt.prefix(40)) + "…" : prompt) {
                        Button("Send now") {
                            Task { _ = await store.sendQueuedPromptNow(at: index) }
                        }
                        Button("Remove", role: .destructive) {
                            store.removeQueuedPrompt(at: index)
                        }
                    }
                }
            } label: {
                Text("Queued prompts")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var createSkillSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Skill")
                .font(.headline)
            TextField("Skill name", text: $createSkillName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCreateSkill = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = createSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    showCreateSkill = false
                    Task {
                        _ = await sendWithTranscriptSessionTransition {
                            await store.send("/create-skill \(name)")
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GrokProminentButtonStyle())
                .disabled(createSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var imagineSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Imagine")
                .font(.headline)
            TextField("Describe the image or video…", text: $imaginePrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            HStack {
                Spacer()
                Button("Cancel") { showImagine = false }
                    .keyboardShortcut(.cancelAction)
                Button("Send /imagine") {
                    let prompt = imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    showImagine = false
                    Task {
                        _ = await sendWithTranscriptSessionTransition {
                            await store.send("/imagine \(prompt)")
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GrokProminentButtonStyle())
                .disabled(imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func taskMenuTitle(_ task: ScheduledTask) -> String {
        let interval = task.intervalHuman.isEmpty ? "task" : task.intervalHuman
        let prompt = task.prompt.isEmpty ? task.id : task.prompt
        let shortPrompt = prompt.count > 32 ? String(prompt.prefix(32)) + "…" : prompt
        return "\(interval): \(shortPrompt)"
    }

    /// Filesystem-derived pill inputs, cached so the status row's render loop stops
    /// stat-ing helper paths on every body evaluation (they only change after an
    /// Apply, which restarts the connection and re-triggers the refresh task).
    struct ToolPillStatus {
        var browserIssue: String?
        var browserAvailable = false
        var browserRuntimeMode: BrowserRuntimeMode = .managed
        var canChooseRuntime = false
        var computerUseIssue: String?
        var computerUseAvailable = false
    }

    nonisolated static func computeToolPillStatus() -> ToolPillStatus {
        let browserSettings = BrowserSettingsStore.loadApplied()
        let computerUseSettings = ComputerUseSettingsStore.loadApplied()
        let browserBaseReady = AgentBrowserService.bridgeScriptURL() != nil
            && AgentBrowserService.executableURL() != nil
        let managedReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: browserSettings, mode: .managed) == nil
        let externalReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: browserSettings, mode: .external) == nil
        return ToolPillStatus(
            browserIssue: AgentBrowserService.browserToolsConfigurationIssue(settings: browserSettings),
            browserAvailable: browserSettings.enabled,
            browserRuntimeMode: browserSettings.runtimeMode,
            canChooseRuntime: browserBaseReady && (managedReady || externalReady),
            computerUseIssue: ComputerUseService.configurationIssue(settings: computerUseSettings),
            computerUseAvailable: computerUseSettings.enabled
        )
    }

    private func refreshToolPillStatus() async {
        let status = await Task.detached(priority: .utility) {
            ChatView.computeToolPillStatus()
        }.value
        toolPillStatus = status
    }

    private var browserStatusIndicator: some View {
        let configurationIssue = toolPillStatus.browserIssue
        let canChooseRuntime = toolPillStatus.canChooseRuntime
        let runtimeMode = toolPillStatus.browserRuntimeMode
        let lifecycle = store.mcpServerStatus(named: "grokbuild-browser")
        let isConfigured = toolPillStatus.browserAvailable && configurationIssue == nil
        let needsSetup = browserToolsEnabled && !isConfigured
        let title = needsSetup ? "Browser Setup Needed" : "Browser Tools"
        let icon = browserToolsEnabled && isConfigured ? "globe.badge.chevron.backward" : "globe"
        return Menu {
            if browserToolsEnabled || isConfigured {
                Button(browserToolsEnabled ? "Turn Browser Off for This Thread" : "Turn Browser On for This Thread") {
                    onToggleBrowserTools()
                }
                .disabled(store.isStreaming || store.isPreparingSubmit)
            }

            if let lifecycle {
                Divider()
                Button(lifecycle.accessibilitySummary) {}
                    .disabled(true)
            }

            if canChooseRuntime {
                Divider()

                Button {
                    onSelectBrowserRuntime(.managed)
                } label: {
                    Label("Managed Browser Runtime", systemImage: runtimeMode == .managed ? "checkmark" : "shippingbox")
                }

                Button {
                    onSelectBrowserRuntime(.external)
                } label: {
                    Label("Existing Chromium Browser", systemImage: runtimeMode == .external ? "checkmark" : "globe")
                }
            }

            if let configurationIssue {
                Button(configurationIssue) {}
                    .disabled(true)
            }

            Divider()

            Button {
                onOpenBrowserSettings()
            } label: {
                Label("Open Browser Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: icon)
                .accessibilityLabel(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .foregroundStyle(needsSetup ? AppTheme.Palette.warning : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(browserStatusHelp(isConfigured: isConfigured, issue: configurationIssue, lifecycle: lifecycle))
    }

    private func browserStatusHelp(
        isConfigured: Bool,
        issue: String?,
        lifecycle: MCPServerStatus?
    ) -> String {
        if !isConfigured {
            return issue ?? "Finish browser setup in Settings before using the quick toggle."
        }
        if let lifecycle {
            return "\(lifecycle.accessibilitySummary). " + (
                browserToolsEnabled
                    ? "Turn Browser off for this thread; GrokBuild will reconnect this tab."
                    : "Turn Browser on for this thread; GrokBuild will reconnect this tab."
            )
        }
        return browserToolsEnabled
            ? "Turn Browser off for this thread."
            : "Turn Browser on for this thread. It starts off in every new thread."
    }

    private var computerUseStatusIndicator: some View {
        let configurationIssue = toolPillStatus.computerUseIssue
        let lifecycle = store.mcpServerStatus(named: "grokbuild-computer-use")
        let isConfigured = toolPillStatus.computerUseAvailable && configurationIssue == nil
        let needsSetup = computerUseEnabled && !isConfigured
        let title = needsSetup ? "Computer Use Setup Needed" : "Computer Use"
        let icon = computerUseEnabled && isConfigured ? "desktopcomputer.badge.checkmark" : "desktopcomputer"
        return Menu {
            if computerUseEnabled || isConfigured {
                Button(computerUseEnabled ? "Turn Computer Use Off for This Thread" : "Turn Computer Use On for This Thread") {
                    onToggleComputerUse()
                }
                .disabled(store.isStreaming || store.isPreparingSubmit)
            }

            if let lifecycle {
                Divider()
                Button(lifecycle.accessibilitySummary) {}
                    .disabled(true)
            }

            if let configurationIssue {
                Button(configurationIssue) {}
                    .disabled(true)
            } else if !computerUseEnabled {
                Button("Starts only when turned on for this thread") {}
                    .disabled(true)
            }

            Divider()

            Button {
                onOpenComputerUseSettings()
            } label: {
                Label("Open Computer Use Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: icon)
                .accessibilityLabel(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .foregroundStyle(needsSetup ? AppTheme.Palette.warning : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(computerUseStatusHelp(isConfigured: isConfigured, issue: configurationIssue, lifecycle: lifecycle))
    }

    private func computerUseStatusHelp(
        isConfigured: Bool,
        issue: String?,
        lifecycle: MCPServerStatus?
    ) -> String {
        if !isConfigured {
            return issue ?? "Finish Computer Use setup in Settings before using the quick toggle."
        }
        if let lifecycle {
            return "\(lifecycle.accessibilitySummary). " + (
                computerUseEnabled
                    ? "Turn Computer Use off for this thread; GrokBuild will reconnect this tab."
                    : "Turn Computer Use on for this thread; GrokBuild will reconnect this tab."
            )
        }
        return computerUseEnabled
            ? "Turn Computer Use off for this thread."
            : "Turn Computer Use on for this thread. It starts off in every new thread."
    }

    // Send-button copy has three states: a genuine continuity block that needs
    // recovery, a transient resume (Send stays enabled and completes the resume),
    // and the ordinary send.
    private var sendButtonHelp: String {
        if store.continuityRequiresRecovery {
            return "Send — the saved conversation can’t be resumed, so this starts a fresh thread."
        }
        if store.continuityIsResuming {
            return "Send to resume this saved session."
        }
        return "Send message"
    }

    private var sendButtonAccessibilityLabel: String {
        if store.continuityRequiresRecovery {
            return "Send, starting a fresh thread"
        }
        if store.continuityIsResuming {
            return "Send and resume session"
        }
        return "Send message"
    }

    private var sendButtonAccessibilityHint: String {
        if store.continuityRequiresRecovery {
            return "The saved conversation could not be matched; sending keeps your local messages and starts a fresh thread."
        }
        if store.continuityIsResuming {
            return "Sends your message and resumes the saved backend session."
        }
        return "Sends the current composer draft to the active session."
    }

    @ViewBuilder
    private var sessionActionButton: some View {
        if store.isPreparingSubmit {
            Button {
                store.cancelPendingSubmit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel before dispatch")
            .accessibilityLabel("Cancel pending task")
            .accessibilityHint("Returns the exact draft to editing without sending it.")
            .accessibilityIdentifier("grok-cancel-pending-submit")
            .keyboardShortcut(.cancelAction)
        } else if store.isStreaming {
            Button {
                store.requestStop()
            } label: {
                // An indeterminate ProgressView here invalidated the entire transcript's
                // LazyVStack every animation frame. A long web/tool wait could therefore
                // peg one CPU core and make every nearby control miss clicks.
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop turn (⌘.)")
            .accessibilityLabel("Stop turn")
            .accessibilityHint("Stops the active build response without sending another request.")
            .accessibilityIdentifier("grok-stop")
            .keyboardShortcut(".", modifiers: .command)
        } else {
            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sendButtonHelp)
            .accessibilityLabel(sendButtonAccessibilityLabel)
            .accessibilityHint(sendButtonAccessibilityHint)
            .accessibilityIdentifier("grok-send")
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.hasVisibleFileAttachments ||
                      store.currentWorkspace == nil ||
                      store.authRequiredMessage != nil ||
                      isSessionRestoreInProgress)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var modeSelector: some View {
        Menu {
            ForEach(store.availableModes, id: \.rawValue) { mode in
                Button {
                    store.setMode(mode)
                } label: {
                    modeMenuRow(
                        icon: iconName(for: mode),
                        title: mode.displayName,
                        isSelected: store.currentMode == mode
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName(for: store.currentMode))
                    .font(.caption.weight(.semibold))
                    .frame(width: 14)
                Text(store.currentMode.displayName)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: ComposerControlMetrics.minimumHitTarget)
            .contentShape(Rectangle())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change agent mode")
        .accessibilityLabel("Agent mode")
        .accessibilityValue(store.currentMode.displayName)
        .accessibilityIdentifier("grok-mode-selector")
        .accessibilityHint("Choose the agent operating mode.")
        .disabled(store.isStreaming || store.isPreparingSubmit)
    }

    private func modeMenuRow(icon: String, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16, alignment: .center)
            Text(title)
            Spacer(minLength: 16)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
            }
        }
    }

    private func iconName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "chat": return "bubble.left"
        case "plan": return "list.bullet.indent"
        case "yolo": return "bolt.fill"
        case "agent": return "infinity"
        default: return "circle"
        }
    }

    private var modelSelector: some View {
        Menu {
            modelChoiceItems

            if store.currentModelSupportsReasoningEffort {
                Divider()
                Menu {
                    ForEach(ReasoningEffortLevel.menuCases) { level in
                        Toggle(
                            level.displayName,
                            isOn: Binding(
                                get: { store.currentReasoningEffort == level.rawValue },
                                set: { selected in
                                    if selected {
                                        requestReasoningEffortChange(to: level.rawValue)
                                    }
                                }
                            )
                        )
                        .disabled(store.isStreaming || store.currentWorkspace == nil)
                        .accessibilityIdentifier("grok-effort-option-\(level.rawValue)")
                    }
                } label: {
                    Text("Effort · \(currentReasoningEffortLabel)")
                }
            } else if store.isCurrentModelCustom {
                Text("Reasoning effort unavailable")
            }

            // Codex parity Slice 4: session telemetry relocated from the deleted
            // Details shelf into the model popover — context budget, settled
            // usage, and the generation-bound route/process/model receipt.
            Divider()
            Section("Session telemetry") {
                Text("Context: \(store.currentModelContextLabel)")
                if let usage = store.sessionUsageSummary {
                    Text("Usage: \(usage)")
                        .accessibilityIdentifier("grok-session-usage")
                }
            }
            Menu {
                Section("Route, process, and model receipt") {
                    ForEach(store.sessionReceiptDetailLines.indices, id: \.self) { index in
                        Text(store.sessionReceiptDetailLines[index])
                    }
                }
            } label: {
                Label(store.currentRouteCompactLabel, systemImage: store.currentRouteSystemImage)
            }
            .accessibilityIdentifier("grok-model-route-contract")
        } label: {
            HStack(spacing: 4) {
                Text(modelSelectorLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: ComposerControlMetrics.minimumHitTarget)
            .contentShape(Rectangle())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Model and reasoning effort")
        .accessibilityValue(store.modelAccessibilityValue)
        .accessibilityIdentifier("grok-model-effort-selector")
        .accessibilityHint("Choose the model and, when supported, reasoning effort.")
        .help(modelSelectorHelp)
    }

    @ViewBuilder
    private var modelChoiceItems: some View {
        // Provider-grouped so custom/OpenRouter routes read as first-class main-agent
        // choices, not an afterthought under the Grok natives.
        ForEach(store.groupedAvailableModels, id: \.label) { group in
            Section(group.label) {
                ForEach(group.ids, id: \.self) { modelId in
                    Button {
                        store.setModel(modelId)
                    } label: {
                        HStack {
                            Text(store.modelDisplayName(modelId))
                            if store.currentModel == modelId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("grok-model-option-\(modelId)")
                    .disabled(store.isModelRequestPending || store.isStreaming || store.isPreparingSubmit)
                }
            }
        }
        Section {
            Button("Use Current Model for New Sessions in This Project") {
                store.setCurrentModelAsProjectDefault()
            }
            .accessibilityIdentifier("grok-model-set-project-default")
            .disabled(store.currentWorkspace == nil || store.isPreparingSubmit)
        }
    }

    private var modelSelectorLabel: String {
        store.modelSelectorDisplayLabel
    }

    private var currentReasoningEffortLabel: String {
        ComposerModelMenuLayout.effortDisplayName(storedValue: store.currentReasoningEffort)
    }

    private var modelSelectorHelp: String {
        if store.isModelRequestPending {
            return "A model request is pending; other model choices are temporarily unavailable"
        }
        if store.isStreaming {
            return "Wait for the current response to finish before changing model or reasoning effort"
        }
        if !store.currentModelSupportsReasoningEffort {
            return "Model selector; reasoning effort is off for this custom model"
        }
        return "Model and reasoning effort"
    }

    private func requestReasoningEffortChange(to effort: String) {
        guard store.currentModelSupportsReasoningEffort else { return }
        guard effort != store.currentReasoningEffort else { return }
        guard store.currentWorkspace != nil, !store.isStreaming else { return }
        if store.needsReasoningEffortConfirmation(for: effort) {
            pendingReasoningEffortChange = effort
        } else {
            Task { await store.applyReasoningEffort(effort, strategy: .restart) }
        }
    }

    private func handleComposerChip(_ command: SlashCommand) async {
        switch command.name {
        case "imagine", "imagine-video":
            showImagine = true
        case "deep-research":
            showDeepResearch = true
        default:
            _ = await sendWithTranscriptSessionTransition {
                await store.send("/\(command.name)")
            }
            inputFocused = true
        }
    }

    private func submit() {
        // Launch restore keeps the composer typeable for draft capture, but a send
        // must wait until the restored session is actually selected and bound.
        guard !isSessionRestoreInProgress else { return }
        let submittedDraft = input
        let text = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let preparation = store.prepareSubmit(text)
        guard preparation != .rejected else { return }
        Task {
            let accepted = await sendWithTranscriptSessionTransition {
                await store.send(text, preparedIntentID: preparation.intentID)
            }
            input = ComposerSubmissionPolicy.draftAfterSubmission(
                currentDraft: input,
                submittedDraft: submittedDraft,
                accepted: accepted
            )
            inputFocused = true
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = fileURL(from: item)
                guard let url else { return }
                Task { @MainActor in
                    appendDroppedFile(url)
                }
            }
        }
        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                appendDroppedFile(url)
            }
        }
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    @MainActor
    private func appendDroppedFile(_ url: URL) {
        store.addFileAttachment(path: url.path)
        inputFocused = true
    }

    private func pickSlashCommand(_ command: SlashCommand) {
        guard let match = slashMatch else { return }
        input = SlashAutocomplete.apply(command: command, to: input, matchRange: match.range)
        inputFocused = true
    }

    private func moveSlashSelection(by delta: Int) {
        let count = slashMenuEntries.count
        guard count > 0 else { return }
        slashActiveIndex = (slashActiveIndex + delta + count) % count
    }

    private func activateSlashEntry(at index: Int) {
        guard slashMenuEntries.indices.contains(index) else { return }
        switch slashMenuEntries[index] {
        case .command(let command):
            pickSlashCommand(command)
        case .showMoreSkills:
            slashSkillsExpanded = true
            clampSlashActiveIndex()
        case .showMoreCommands:
            slashCommandsExpanded = true
            clampSlashActiveIndex()
        }
    }

    private func clampSlashActiveIndex() {
        let count = slashMenuEntries.count
        guard count > 0 else {
            slashActiveIndex = 0
            return
        }
        slashActiveIndex = min(slashActiveIndex, count - 1)
    }

}

private struct LaunchSessionChoices: View {
    let onResumeCurrent: () -> Void
    let onStartNew: () -> Void
    let onBrowseOld: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            launchButton(
                "Resume current task",
                help: "Resume the exact saved Grok backend without sending a prompt.",
                identifier: "grok-launch-resume-current",
                action: onResumeCurrent
            )
            Menu {
                Button("Start new task", action: onStartNew)
                    .accessibilityIdentifier("grok-launch-new-task")
                Button("Browse old tasks", action: onBrowseOld)
                    .accessibilityIdentifier("grok-launch-browse-old")
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More saved task actions")
            .accessibilityLabel("More saved task actions")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved task launch choices")
        .accessibilityIdentifier("grok-launch-session-choices")
    }

    private func launchButton(
        _ title: String,
        help: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(.secondary)
            .help(help)
            .accessibilityLabel(title)
            .accessibilityHint(help)
            .accessibilityIdentifier(identifier)
    }
}

// MARK: - Context Usage

// MARK: - Auth Banner

/// Shown when a streaming turn has produced no ACP events for two minutes. Nothing is
/// cancelled automatically — a long tool run and a wedged process look identical from
/// outside, so the user decides.
private struct TurnStalledBanner: View {
    let since: Date
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass.badge.exclamationmark")
                .foregroundStyle(AppTheme.Palette.warning)
            Text("Grok hasn't sent anything since \(since.formatted(date: .omitted, time: .shortened)). It may be mid-tool-run, or stuck.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop turn", action: onStop)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.small).fill(AppTheme.Palette.glassTint))
        .padding(.horizontal, 20)
        .accessibilityLabel("Turn may be stalled")
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.Palette.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("grok-acp-error-banner")
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct SessionRecoveryReviewSheet: View {
    @Bindable var store: ChatStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review candidate histories")
                        .font(.title3.weight(.semibold))
                    Text("Candidates are read-only until you explicitly Relink a verified match.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            if store.isLoadingRecoveryCandidates {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking recent histories in this project…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.recoveryCandidateError {
                ContentUnavailableView(
                    "Candidate review unavailable",
                    systemImage: "exclamationmark.shield",
                    description: Text(error)
                )
                Button("Retry") {
                    Task { await store.reviewRecoveryCandidates() }
                }
            } else if store.recoveryCandidates.isEmpty {
                ContentUnavailableView(
                    "No provenance-safe candidates",
                    systemImage: "link.badge.plus",
                    description: Text(
                        "No recent history has enough evidence to verify this transcript. Continue as New remains the safe recovery."
                    )
                )
            } else {
                List(store.recoveryCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.redactedBackendID)
                                .font(.body.monospaced())
                            Text(candidate.isRelinkable ? "Verified candidate" : "Review only")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(candidate.isRelinkable ? .green : AppTheme.Palette.warning)
                            Spacer()
                            Button("Relink") {
                                Task {
                                    if await store.relink(to: candidate) {
                                        onClose()
                                    }
                                }
                            }
                            .disabled(!candidate.isRelinkable)
                        }
                        Text(
                            "\(candidate.workspaceName) · \(candidate.modelID ?? "model unknown") · last active \(candidate.lastActivity.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(
                            "\(candidate.matchingTurnCount) matching turns · \(candidate.mismatchCount) mismatched rows · \(candidate.localMessageCount) local / \(candidate.backendMessageCount) backend rows"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if candidate.quarantinedRowCount > 0 {
                            Text("Mixed or unknown provenance is quarantined and cannot verify a binding.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Palette.warning)
                        } else if !candidate.isRelinkable {
                            Text("Shared prompts are evidence for review, not identity proof.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(
                        "Backend \(candidate.redactedBackendID), \(candidate.isRelinkable ? "verified candidate" : "review only")"
                    )
                    .accessibilityValue(
                        "\(candidate.matchingTurnCount) matching turns, \(candidate.mismatchCount) mismatched rows"
                    )
                }
            }
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 430)
        .accessibilityElement(children: .contain)
    }
}

private struct ModelSwitchBanner: View {
    let message: String
    var canStartNewSession: Bool = false
    var onStartNewSession: () -> Void = {}
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(AppTheme.Palette.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            if canStartNewSession {
                Button("Start New Session", action: onStartNewSession)
                    .buttonStyle(GrokProminentButtonStyle())
                    .controlSize(.small)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

struct AuthBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AppTheme.Palette.warning)
                Text("Authentication Required")
                    .font(.headline)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    openTerminalForLogin()
                } label: {
                    Label("Sign in with Grok…", systemImage: "terminal")
                }
                .buttonStyle(GrokProminentButtonStyle())

                Button {
                    copyLoginCommand()
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .contentShape(Rectangle().inset(by: -8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(AppTheme.Palette.warning.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func openTerminalForLogin() {
        guard let command = GrokAuthentication.loginCommand() else {
            openTerminalApp()
            return
        }
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: just open Terminal
                openTerminalApp()
            }
        } else {
            openTerminalApp()
        }
    }

    private func openTerminalApp() {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(terminalURL)
    }

    private func copyLoginCommand() {
        guard let command = GrokAuthentication.loginCommand() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }
}

// MARK: - Permission Card with Diff Preview

struct PermissionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let permission: PermissionRequest
    let effectivePermissionMode: GrokPermissionMode
    let onRespond: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: permission.toolCall.isEdit ? "doc.text" : "terminal")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool approval required")
                        .font(.subheadline.weight(.semibold))
                    Text(permission.toolCall.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(permissionPolicyExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if permission.toolCall.isEdit, let path = permission.toolCall.filePath {
                HStack {
                    Text("\(path) — proposed edit")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("open diff preview →") {
                        openNativeDiffPreview(permission.toolCall)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else if permission.toolCall.isExecute, let cmd = permission.toolCall.command {
                Text("Command: \(cmd)")
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.Palette.warning)
            }

            HStack(spacing: 8) {
                ForEach(permission.options) { option in
                    Button(option.name) {
                        onRespond(option.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(AppTheme.Palette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(AppTheme.Palette.warning.opacity(0.35), lineWidth: 1)
        )
        .transition(.opacity)
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: permission.id)
    }

    private var permissionPolicyExplanation: String {
        "Effective live process policy: \(effectivePermissionMode.displayName). This tool will not run until you choose an option; explicit deny rules still win."
    }

    private func openNativeDiffPreview(_ toolCall: ToolCall) {
        guard let path = toolCall.filePath,
              let proposed = toolCall.proposedContent else { return }
        // File writes + process spawn have no business on the main actor.
        Task.detached(priority: .userInitiated) {
            Self.launchNativeDiffPreview(path: path, proposed: proposed)
        }
    }

    private nonisolated static func launchNativeDiffPreview(path: String, proposed: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let oldURL = tempDir.appendingPathComponent("grok-old-\(UUID().uuidString).txt")
        let newURL = tempDir.appendingPathComponent("grok-new-\(UUID().uuidString).txt")

        do {
            // Try to get current content as "old"
            let oldContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try oldContent.write(to: oldURL, atomically: true, encoding: .utf8)
            try proposed.write(to: newURL, atomically: true, encoding: .utf8)

            // Deeper: use opendiff (FileMerge) or Xcode for native diff
            let process = Process()
            if FileManager.default.fileExists(atPath: "/usr/bin/opendiff") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
                process.arguments = [oldURL.path, newURL.path]
            } else {
                // Fallback to opening both or use VS Code if available
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Xcode", oldURL.path, newURL.path]
            }
            try GrokChildProcessSpawnGate.run(process)
        } catch {
            // Silent fallback: the native diff is a convenience, not a required path.
        }
    }
}
