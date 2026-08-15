import SwiftUI
import UniformTypeIdentifiers

/// Composer envelope. ChatView still owns draft state, slash matching, the add
/// menu, and send; this view only lays out chips, the editor, and the control row.
enum ChatComposerAccessibility {
    static let identifier = "grok-message-composer"
    static let label = "Message composer"

    /// Empty-field VoiceOver value must include the visible placeholder.
    static func value(forDraft input: String) -> String {
        input.isEmpty ? "Describe a task" : "\(input.count) characters"
    }
}

struct ChatComposer<QueueBar: View, PrimaryControls: View, ActionControls: View>: View {
    @Bindable var store: ChatStore
    @Binding var input: String
    @Binding var isFileDropTargeted: Bool
    @FocusState.Binding var inputFocused: Bool
    let showSlashPopover: Bool
    let slashMenuEntries: [SlashMenuEntry]
    let slashActiveIndex: Int
    var onSelectSlash: (SlashCommand) -> Void
    var onShowMoreSkills: () -> Void
    var onShowMoreCommands: () -> Void
    var onSubmit: () -> Void
    var onActivateSlash: (Int) -> Void
    var onMoveSlashSelection: (Int) -> Void
    var onInputChanged: () -> Void
    var onPreviousHistory: () -> Bool
    var onNextHistory: () -> Bool
    var onFileDrop: ([NSItemProvider]) -> Bool
    let queueBar: QueueBar
    let primaryControls: PrimaryControls
    let actionControls: ActionControls

    init(
        store: ChatStore,
        input: Binding<String>,
        isFileDropTargeted: Binding<Bool>,
        inputFocused: FocusState<Bool>.Binding,
        showSlashPopover: Bool,
        slashMenuEntries: [SlashMenuEntry],
        slashActiveIndex: Int,
        onSelectSlash: @escaping (SlashCommand) -> Void,
        onShowMoreSkills: @escaping () -> Void,
        onShowMoreCommands: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        onActivateSlash: @escaping (Int) -> Void,
        onMoveSlashSelection: @escaping (Int) -> Void,
        onInputChanged: @escaping () -> Void,
        onPreviousHistory: @escaping () -> Bool,
        onNextHistory: @escaping () -> Bool,
        onFileDrop: @escaping ([NSItemProvider]) -> Bool,
        @ViewBuilder queueBar: () -> QueueBar,
        @ViewBuilder primaryControls: () -> PrimaryControls,
        @ViewBuilder actionControls: () -> ActionControls
    ) {
        self.store = store
        self._input = input
        self._isFileDropTargeted = isFileDropTargeted
        self._inputFocused = inputFocused
        self.showSlashPopover = showSlashPopover
        self.slashMenuEntries = slashMenuEntries
        self.slashActiveIndex = slashActiveIndex
        self.onSelectSlash = onSelectSlash
        self.onShowMoreSkills = onShowMoreSkills
        self.onShowMoreCommands = onShowMoreCommands
        self.onSubmit = onSubmit
        self.onActivateSlash = onActivateSlash
        self.onMoveSlashSelection = onMoveSlashSelection
        self.onInputChanged = onInputChanged
        self.onPreviousHistory = onPreviousHistory
        self.onNextHistory = onNextHistory
        self.onFileDrop = onFileDrop
        self.queueBar = queueBar()
        self.primaryControls = primaryControls()
        self.actionControls = actionControls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.fileAttachments.isEmpty {
                FileChipBar(
                    attachments: store.fileAttachments,
                    onToggleHidden: { store.toggleFileAttachmentHidden(id: $0) },
                    onRemove: { store.removeFileAttachment(id: $0) }
                )
            }

            if !store.selectedPromptMCPOptions.isEmpty {
                PromptMCPChipBar(
                    names: store.selectedPromptMCPOptions.map(\.name),
                    onRemove: { store.removePromptMCPAttachment(named: $0) }
                )
            }

            if !store.promptQueue.isEmpty {
                queueBar
            }

            VStack(alignment: .leading, spacing: 10) {
                if let stage = store.pendingSubmitStageText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing task…")
                            .font(.callout.weight(.medium))
                        Text(stage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("Esc to cancel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("grok-pending-submit-status")
                } else if let stage = store.sendOwnedStartupStageText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(stage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("grok-send-startup-status")
                }

                VStack(alignment: .leading, spacing: 6) {
                    if showSlashPopover {
                        SlashAutocompleteView(
                            entries: slashMenuEntries,
                            activeIndex: slashActiveIndex,
                            onSelect: onSelectSlash,
                            onShowMoreSkills: onShowMoreSkills,
                            onShowMoreCommands: onShowMoreCommands
                        )
                    }

                    TextField("Describe a task", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.composer)
                    .lineSpacing(4)
                    .focused($inputFocused)
                    .lineLimit(ComposerDensityPolicy.minimumLineCount...ComposerDensityPolicy.maximumLineCount)
                    .frame(minHeight: ComposerDensityPolicy.editorMinimumHeight, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .overlay(ComposerCursorRegion())
                    .submitLabel(.send)
                    .accessibilityLabel(ChatComposerAccessibility.label)
                    .accessibilityValue(ChatComposerAccessibility.value(forDraft: input))
                    .accessibilityHint("Enter a question, build request, or review request. Return sends; Shift-Return adds a line.")
                    .accessibilityIdentifier(ChatComposerAccessibility.identifier)
                    .disabled(store.isPreparingSubmit)
                    .onSubmit {
                        if showSlashPopover {
                            onActivateSlash(slashActiveIndex)
                        } else {
                            onSubmit()
                        }
                    }
                    .onChange(of: input) { _, _ in
                        onInputChanged()
                    }
                    .onKeyPress { press in
                        if press.key == .tab, showSlashPopover, !slashMenuEntries.isEmpty {
                            onActivateSlash(slashActiveIndex)
                            return .handled
                        }
                        if press.key == .return && !press.modifiers.contains(.shift) {
                            if showSlashPopover {
                                onActivateSlash(slashActiveIndex)
                            } else {
                                onSubmit()
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(keys: [.upArrow]) { press in
                        guard press.modifiers.isEmpty else { return .ignored }
                        if showSlashPopover, !slashMenuEntries.isEmpty {
                            onMoveSlashSelection(-1)
                            return .handled
                        }
                        // History only when the caret has no line above it —
                        // multi-line drafts keep native caret movement
                        // (returning .handled unconditionally made arrows
                        // dead inside long drafts).
                        guard !input.contains("\n") else { return .ignored }
                        return onPreviousHistory() ? .handled : .ignored
                    }
                    .onKeyPress(keys: [.downArrow]) { press in
                        guard press.modifiers.isEmpty else { return .ignored }
                        if showSlashPopover, !slashMenuEntries.isEmpty {
                            onMoveSlashSelection(1)
                            return .handled
                        }
                        guard !input.contains("\n") else { return .ignored }
                        return onNextHistory() ? .handled : .ignored
                    }
                }

                // Codex parity Slice 4: the bottom row carries only immediate
                // authoring/run controls — add/context, run mode, then model,
                // voice, and send. No keyboard-hint prose, no Details shelf.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) {
                        primaryControls
                        Spacer(minLength: 12)
                        actionControls
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        primaryControls
                        actionControls
                    }
                }
            }
            .padding(.horizontal, ComposerDensityPolicy.surfaceHorizontalPadding)
            .padding(.vertical, ComposerDensityPolicy.surfaceVerticalPadding)
            .frame(maxWidth: AppTheme.Layout.composerMaxWidth, alignment: .leading)
            .grokGlassSurface(
                cornerRadius: AppTheme.Radius.composer,
                emphasized: isFileDropTargeted,
                shadowed: ComposerDensityPolicy.surfaceHasShadow
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDropTargeted) { providers in
                onFileDrop(providers)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, ComposerDensityPolicy.outerHorizontalPadding)
        .padding(.vertical, ComposerDensityPolicy.outerVerticalPadding)
    }
}
