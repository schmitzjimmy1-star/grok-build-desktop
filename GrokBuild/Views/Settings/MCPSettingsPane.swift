import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct MCPSettingsPane: View {
    let workspace: Workspace?
    @Binding var inventory: SettingsInventoryState<[GrokMCPServerInfo]>
    @Binding var draft: GrokMCPServerDraft
    @Binding var acknowledgedLiteralStorage: Bool
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    private let service = GrokCLIService()
    @State private var doctorReport: GrokMCPDoctorReport?
    @State private var isLoading = false
    @State private var activeOperationID: String?
    @State private var activeOperationIsCancellable = false
    @State private var operationTask: Task<Void, Never>?
    @State private var rowReceipts: [String: SettingsRowOperationReceipt] = [:]
    @State private var pendingRemoval: GrokMCPServerInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "MCP Servers",
                    subtitle: "Connect external tools and check their status.",
                    systemImage: SettingsTab.mcpServers.systemImage
                )
                Button("Run Doctor") {
                    startDoctor()
                }
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            if let receipt = rowReceipts["doctor-all"] {
                SettingsRowOperationReceiptView(
                    receipt: receipt,
                    onCancel: activeOperationID == "doctor-all" && activeOperationIsCancellable
                        ? { cancelOperation("doctor-all") }
                        : nil
                )
            }

            mcpEditor

            List {
                ForEach(inventory.value) { server in
                    VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.name)
                                .font(.headline)
                            Text([server.transport, server.source].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !server.target.isEmpty {
                                Text(server.target)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            let metadata = [
                                server.argumentCount > 0 ? "\(server.argumentCount) argument\(server.argumentCount == 1 ? "" : "s")" : nil,
                                server.environmentNames.isEmpty ? nil : "environment: \(server.environmentNames.joined(separator: ", ")) (values redacted)",
                                server.headerNames.isEmpty ? nil : "headers: \(server.headerNames.joined(separator: ", ")) (values redacted)",
                            ].compactMap { $0 }
                            if !metadata.isEmpty {
                                Text(metadata.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("Check") {
                            startDoctor(name: server.name, rowID: server.id)
                        }
                        Button("Remove", role: .destructive) {
                            pendingRemoval = server
                        }
                    }
                    if let receipt = rowReceipts[server.id] {
                        SettingsRowOperationReceiptView(
                            receipt: receipt,
                            onCancel: activeOperationID == server.id && activeOperationIsCancellable
                                ? { cancelOperation(server.id) }
                                : nil
                        )
                    }
                    }
                    .padding(.vertical, 3)
                }
            }
            .overlay {
                if inventory.value.isEmpty && !isLoading {
                    SettingsLoadStateView(
                        state: inventory.loadState,
                        retry: { Task { await refresh() } }
                    )
                }
            }

            if let doctorReport {
                Divider()
                Text("Check Results: \(doctorReport.healthyCount) healthy, \(doctorReport.failingCount) failing")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(doctorReport.servers) { server in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Circle()
                                        .fill(server.healthy ? .green : .red)
                                        .frame(width: 8, height: 8)
                                    Text(server.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(server.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(server.checks, id: \.self) { check in
                                    HStack(alignment: .top) {
                                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(check.passed ? .green : .red)
                                        VStack(alignment: .leading) {
                                            Text(check.label)
                                            if !check.detail.isEmpty {
                                                Text(check.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !check.hint.isEmpty {
                                                Text(check.hint)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if isLoading { ProgressView() }
            if !inventory.value.isEmpty, inventory.loadState != .content {
                SettingsLoadStateView(
                    state: inventory.loadState,
                    retry: { Task { await refresh() } }
                )
            }
        }
        .task(id: workspace?.path) { await refresh() }
        .onDisappear {
            operationTask?.cancel()
            operationTask = nil
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "MCP server")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let server = pendingRemoval {
                Button("Remove \(server.name)", role: .destructive) {
                    pendingRemoval = nil
                    startRemove(server)
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This removes the selected scope entry through the Grok CLI and restarts only the current live tab when eligible.")
        }
    }

    private var mcpEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Structured server draft").font(.headline)
                Spacer()
                Text("\(draft.scope.rawValue.capitalized) scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            SettingsFormRow("Name", subtitle: "Stable Grok MCP server identifier.") {
                TextField("server-name", text: $draft.name).frame(minWidth: 220)
            }
            SettingsFormRow("Transport", subtitle: "Stdio uses an executable and ordered arguments; HTTP/SSE use a URL and headers.") {
                Picker("Transport", selection: $draft.transport) {
                    ForEach(GrokMCPTransport.allCases) { item in
                        Text(item.rawValue.uppercased()).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: AppTheme.Layout.settingsControlWidth)
            }
            SettingsFormRow("Scope", subtitle: "User writes ~/.grok/config.toml. Project writes ./.grok/config.toml in the selected workspace.") {
                Picker("Scope", selection: $draft.scope) {
                    Text("User").tag(GrokMCPConfigScope.user)
                    Text("Project").tag(GrokMCPConfigScope.project)
                }
                .labelsHidden()
                .frame(width: AppTheme.Layout.settingsControlWidth)
            }

            if draft.transport == .stdio {
                SettingsFormRow("Executable", subtitle: "Kept separate from arguments; no shell splitting.") {
                    TextField("/path/to/executable", text: $draft.executable).frame(minWidth: 280)
                }
                structuredArguments
                secretRows(
                    title: "Environment",
                    subtitle: "Repeated --env KEY=value entries. Only names are shown after save.",
                    entries: $draft.environment,
                    addTitle: "Add environment entry"
                )
            } else {
                SettingsFormRow("URL", subtitle: "A complete HTTP or HTTPS endpoint.") {
                    TextField("https://example.com/mcp", text: $draft.url).frame(minWidth: 280)
                }
                secretRows(
                    title: "Headers",
                    subtitle: "Repeated --header NAME: VALUE entries. Only names are shown after save.",
                    entries: $draft.headers,
                    addTitle: "Add header"
                )
            }

            if draft.containsLiteralSecrets {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Literal secret storage", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                    Text("The installed Grok 0.2.118 CLI accepts literal --env/--header values and exposes no interoperable secret-reference syntax. Grok stores them in the selected config. User config remains owner-only (0600); project config may be shared. GrokBuild never mirrors or reveals these values.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("I understand where these literal values will be stored", isOn: $acknowledgedLiteralStorage)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }

            if let validation = draft.validation.message {
                Text(validation).font(.caption).foregroundStyle(.red)
            } else if draft.scope == .project, workspace == nil {
                Text("Choose a project before saving a project-scoped MCP server.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Direct CLI write · exact argument boundaries · current-tab restart only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Revert Draft") {
                    draft = GrokMCPServerDraft()
                    acknowledgedLiteralStorage = false
                }
                .disabled(draft == GrokMCPServerDraft())
                Button("Add / Update") { startAddServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveDraft || activeOperationID != nil)
            }
            if let receipt = rowReceipts["mcp-editor"] {
                SettingsRowOperationReceiptView(receipt: receipt)
            }
        }
        .padding(14)
        .grokGlassSurface()
        .onChange(of: draft.transport) { _, _ in acknowledgedLiteralStorage = false }
        .onChange(of: draft.scope) { _, _ in acknowledgedLiteralStorage = false }
    }

    private var canSaveDraft: Bool {
        draft.validation.isValid
            && (draft.scope != .project || workspace != nil)
            && (!draft.containsLiteralSecrets || acknowledgedLiteralStorage)
    }

    private var structuredArguments: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arguments").font(.callout.weight(.medium))
                    Text("One row per exact argument. Empty and space-containing values are preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Argument") { draft.arguments.append(GrokMCPArgumentDraft()) }
                    .controlSize(.small)
            }
            ForEach(Array(draft.arguments.enumerated()), id: \.element.id) { index, argument in
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 22)
                    TextField("Argument", text: argumentBinding(id: argument.id))
                    Button { moveArgument(from: index, offset: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0).help("Move argument up")
                    Button { moveArgument(from: index, offset: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == draft.arguments.count - 1).help("Move argument down")
                    Button(role: .destructive) { draft.arguments.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .help("Remove argument")
                }
                .controlSize(.small)
            }
        }
    }

    private func secretRows(
        title: String,
        subtitle: String,
        entries: Binding<[GrokMCPSecretDraft]>,
        addTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(addTitle) {
                    entries.wrappedValue.append(GrokMCPSecretDraft())
                    acknowledgedLiteralStorage = false
                }
                .controlSize(.small)
            }
            ForEach(entries.wrappedValue) { entry in
                HStack(spacing: 8) {
                    TextField("Name", text: secretNameBinding(id: entry.id, entries: entries))
                    SecureField("Value", text: secretValueBinding(id: entry.id, entries: entries)).privacySensitive()
                    Button(role: .destructive) {
                        entries.wrappedValue.removeAll { $0.id == entry.id }
                        acknowledgedLiteralStorage = false
                    } label: { Image(systemName: "minus.circle") }
                        .help("Remove \(title.lowercased()) entry")
                }
                .controlSize(.small)
            }
        }
    }

    private func argumentBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { draft.arguments.first(where: { $0.id == id })?.value ?? "" },
            set: { value in
                guard let index = draft.arguments.firstIndex(where: { $0.id == id }) else { return }
                draft.arguments[index].value = value
            }
        )
    }

    private func secretNameBinding(id: UUID, entries: Binding<[GrokMCPSecretDraft]>) -> Binding<String> {
        Binding(
            get: { entries.wrappedValue.first(where: { $0.id == id })?.name ?? "" },
            set: { value in
                guard let index = entries.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                entries.wrappedValue[index].name = value
                acknowledgedLiteralStorage = false
            }
        )
    }

    private func secretValueBinding(id: UUID, entries: Binding<[GrokMCPSecretDraft]>) -> Binding<String> {
        Binding(
            get: { entries.wrappedValue.first(where: { $0.id == id })?.value ?? "" },
            set: { value in
                guard let index = entries.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                entries.wrappedValue[index].value = value
                acknowledgedLiteralStorage = false
            }
        )
    }

    private func moveArgument(from index: Int, offset: Int) {
        let destination = index + offset
        guard draft.arguments.indices.contains(index), draft.arguments.indices.contains(destination) else { return }
        draft.arguments.swapAt(index, destination)
    }

    private func header(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }

    private func refresh() async {
        isLoading = true
        inventory.beginRefresh(staleMessage: "Refreshing MCP servers for the selected scope and project…")
        do {
            let servers = try await service.listMCPServers(cwd: workspace?.path)
            guard !Task.isCancelled else { return }
            inventory.finish(
                servers,
                isEmpty: servers.isEmpty,
                emptyMessage: "No MCP servers are configured. Grok completed the inventory successfully."
            )
        } catch {
            guard !Task.isCancelled else { return }
            inventory.fail(error.localizedDescription)
        }
        isLoading = false
    }

    private func startDoctor(name: String? = nil, rowID: String = "doctor-all") {
        startOperation(
            rowID: rowID,
            action: "Run MCP Doctor",
            scope: .externalConfigOnly,
            cancellable: true,
            mutatesConfiguration: false,
            requiresTrust: false
        ) {
            doctorReport = try await service.mcpDoctor(name: name, cwd: workspace?.path)
        }
    }

    private func startAddServer() {
        let submitted = draft
        startOperation(
            rowID: "mcp-editor",
            action: "Save MCP server",
            scope: .activeTabRestart,
            cancellable: false,
            mutatesConfiguration: true,
            requiresTrust: submitted.containsLiteralSecrets
        ) {
            try await service.addMCPServer(submitted, cwd: workspace?.path)
            draft = GrokMCPServerDraft()
            acknowledgedLiteralStorage = false
        }
    }

    private func startRemove(_ server: GrokMCPServerInfo) {
        let scope = GrokMCPConfigScope(rawValue: server.source)
        startOperation(
            rowID: server.id,
            action: "Remove MCP server",
            scope: .activeTabRestart,
            cancellable: false,
            mutatesConfiguration: true,
            requiresTrust: false
        ) {
            try await service.removeMCPServer(
                name: server.name,
                scope: scope,
                cwd: workspace?.path
            )
        }
    }

    private func startOperation(
        rowID: String,
        action: String,
        scope: SettingsApplyScope,
        cancellable: Bool,
        mutatesConfiguration: Bool,
        requiresTrust: Bool,
        operation: @escaping () async throws -> Void
    ) {
        guard activeOperationID == nil else { return }
        activeOperationID = rowID
        activeOperationIsCancellable = cancellable
        rowReceipts[rowID] = .running(rowID: rowID, summary: "\(action) is running.", scope: scope)
        operationTask = Task {
            do {
                try await operation()
                try Task.checkCancellation()
                var applyReceipt: SettingsApplyReceipt?
                if mutatesConfiguration {
                    let request = SettingsApplyRequest(
                        configurationGeneration: inventory.nextConfigurationGeneration(),
                        capability: .mcpServers,
                        persistenceOwner: .grokConfig,
                        applyScope: .activeTabRestart,
                        requiresProcessRestart: true,
                        requiresPermissionOrTrust: requiresTrust,
                        redactedSummary: "MCP configuration saved through the verified CLI schema; restarting only the current live tab when eligible."
                    )
                    applyReceipt = await onApply(request)
                    try Task.checkCancellation()
                    await refresh()
                }
                rowReceipts[rowID] = .completed(
                    rowID: rowID,
                    status: applyReceipt?.status == .failure ? .failure : .success,
                    summary: applyReceipt?.summary ?? "\(action) completed with a redacted receipt.",
                    scope: scope,
                    applyReceipt: applyReceipt
                )
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                rowReceipts[rowID] = .completed(
                    rowID: rowID,
                    status: cancelled ? .cancelled : .failure,
                    summary: cancelled
                        ? "Operation cancelled. Refresh before trusting the current MCP state."
                        : GrokMCPRedactor.redact(error.localizedDescription),
                    scope: scope
                )
            }
            activeOperationID = nil
            activeOperationIsCancellable = false
            operationTask = nil
        }
    }

    private func cancelOperation(_ rowID: String) {
        guard activeOperationID == rowID, activeOperationIsCancellable else { return }
        operationTask?.cancel()
    }
}

