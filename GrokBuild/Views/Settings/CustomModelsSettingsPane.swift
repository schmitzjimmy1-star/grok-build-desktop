import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct CustomModelsSettingsPane: View {
    @Binding var valueState: SettingsValueState<String>
    @Bindable var viewModel: CustomModelsSettingsViewModel
    let liveReceipt: EffectiveSessionReceipt?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt
    let onConfigurationChanged: (ConfigurationChange) -> Void

    @State private var editingID: String?
    @State private var draft = CustomModel(id: "", model: "", baseURL: "")
    @State private var revealKey = false
    @State private var allowUnverifiedCustomModel = false
    @State private var editingProviderID: String?
    @State private var providerDraft = Provider(id: "", name: "", baseURL: "")
    @State private var revealProviderKey = false
    @State private var modelFilterText = ""
    @State private var openRouterOAuthTask: Task<Void, Never>?
    @State private var openRouterOAuthError: String?

    private enum ProviderEditorField: Hashable { case id, name, url, key }
    @FocusState private var providerEditorFocus: ProviderEditorField?

    /// See the comment at the provider-editor fields: present only while the field is
    /// unfocused, so the first click lands here and forcibly moves focus.
    @ViewBuilder
    private func focusClickCatcher(for field: ProviderEditorField) -> some View {
        if providerEditorFocus != field {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { providerEditorFocus = field }
        }
    }
    // Drives programmatic scrolling to an editor when a card opens it.
    @State private var scrollTarget: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // True while the provider editor holds a not-yet-saved template (so we lock the id and
    // prompt for the key). Cleared once the provider is saved or the draft is reset.
    @State private var providerDraftFromPreset = false
    // The editor cards are hidden until the user explicitly opens them via Install / Add /
    // Edit, keeping the default view a clean list.
    @State private var showingProviderEditor = false
    @State private var showingModelEditor = false
    // The provider-template catalog is collapsed by default so "Add Provider" stays compact.
    @State private var showingProviderTemplates = false
    @State private var showModelRemovalConfirmation = false
    @State private var modelPendingRemoval: CustomModel?
    @State private var showProviderRemovalConfirmation = false
    @State private var providerPendingRemoval: Provider?
    @State private var showObservationClearConfirmation = false
    @State private var observationRevision = 0

    private var providers: [Provider] {
        get { viewModel.providers }
        nonmutating set { viewModel.providers = newValue }
    }
    private var models: [CustomModel] {
        get { viewModel.models }
        nonmutating set { viewModel.models = newValue }
    }
    private var defaultModelID: String {
        get { valueState.draft }
        nonmutating set { valueState.updateDraft(newValue) }
    }
    private var persistedDefaultModelID: String {
        get { valueState.persisted }
        nonmutating set { _ = newValue }
    }
    private var errorMessage: String? {
        get { viewModel.errorMessage }
        nonmutating set { viewModel.errorMessage = newValue }
    }
    private var statusMessage: String? {
        get { viewModel.statusMessage }
        nonmutating set { viewModel.statusMessage = newValue }
    }
    private var modelConfigWriteSafety: CustomModelStore.WriteSafety {
        get { viewModel.modelConfigWriteSafety }
        nonmutating set { viewModel.modelConfigWriteSafety = newValue }
    }
    private var hasLoadedModelConfiguration: Bool {
        get { viewModel.hasLoadedModelConfiguration }
        nonmutating set { viewModel.hasLoadedModelConfiguration = newValue }
    }
    private var modelConfigWriteBlockReason: String? {
        guard hasLoadedModelConfiguration else {
            return "Wait for GrokBuild to finish loading config.toml before changing models."
        }
        return modelConfigWriteSafety.blockingMessage
    }
    private var canWriteModelConfiguration: Bool { modelConfigWriteBlockReason == nil }
    private var migrationIssues: [ProviderCredentialMigrationIssue] {
        get { viewModel.migrationIssues }
        nonmutating set { viewModel.migrationIssues = newValue }
    }
    private var validationResults: [String: ProviderValidationResult] {
        get { viewModel.validationResults }
        nonmutating set { viewModel.validationResults = newValue }
    }
    private var fetchedModels: [String: [FetchedModel]] {
        get { viewModel.fetchedModels }
        nonmutating set { viewModel.fetchedModels = newValue }
    }
    private var fetchingProviderID: String? {
        get { viewModel.fetchingProviderID }
        nonmutating set { viewModel.fetchingProviderID = newValue }
    }
    private var fetchErrorProviderID: String? {
        get { viewModel.fetchErrorProviderID }
        nonmutating set { viewModel.fetchErrorProviderID = newValue }
    }
    private var fetchErrorMessage: String? {
        get { viewModel.fetchErrorMessage }
        nonmutating set { viewModel.fetchErrorMessage = newValue }
    }
    private var grokAuthenticationState: GrokAuthenticationState {
        get { viewModel.grokAuthenticationState }
        nonmutating set { viewModel.grokAuthenticationState = newValue }
    }

    private struct DefaultModelOption: Identifiable {
        var id: String
        var label: String
    }

    private struct ContextTokenPreset: Identifiable {
        var label: String
        var value: Int
        var id: Int { value }
    }

    @State private var builtInModels = GrokModelCatalog.cachedOrFallback()

    private var builtInDefaultModels: [DefaultModelOption] {
        [DefaultModelOption(id: "", label: "No default override")]
            + builtInModels.map { DefaultModelOption(id: $0.id, label: $0.name) }
    }

    private let contextTokenPresets: [ContextTokenPreset] = [
        ContextTokenPreset(label: "128K", value: 128_000),
        ContextTokenPreset(label: "200K", value: 200_000),
        ContextTokenPreset(label: "512K", value: 512_000),
        ContextTokenPreset(label: "1M", value: 1_000_000)
    ]

    private var isEditing: Bool { editingID != nil }
    private var isEditingProvider: Bool { editingProviderID != nil }
    /// While any editor (provider or model) is open we lock the list cards so the user
    /// finishes or cancels the current edit before starting another action.
    private var isAnyEditorOpen: Bool { showingProviderEditor || showingModelEditor }
    private var isAtModelLimit: Bool { models.count >= CustomModelStore.maxModels }
    private var isDefaultModelDirty: Bool { valueState.isDirty }

    private var defaultModelOptions: [DefaultModelOption] {
        var options = builtInDefaultModels
        for model in models {
            let label = model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? model.id
                : "\(model.name) (\(model.id))"
            if !options.contains(where: { $0.id == model.id }) {
                options.append(DefaultModelOption(id: model.id, label: label))
            }
        }
        if !defaultModelID.isEmpty, !options.contains(where: { $0.id == defaultModelID }) {
            options.append(DefaultModelOption(id: defaultModelID, label: "\(defaultModelID) (current)"))
        }
        return options
    }

    private var contextTokensBinding: Binding<String> {
        Binding(
            get: {
                draft.contextTokens.map(String.init) ?? ""
            },
            set: { value in
                let digits = value.filter(\.isNumber)
                draft.contextTokens = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    private func selectableModels(for provider: Provider) -> [FetchedModel] {
        fetchedModels[provider.id] ?? []
    }

    /// True when a provider has a non-empty fetched-model list ready for "Add model".
    private func hasFetchedModels(for provider: Provider) -> Bool {
        !(fetchedModels[provider.id]?.isEmpty ?? true)
    }

    private func addModelDisabledReason(for provider: Provider) -> String? {
        if isAtModelLimit {
            return "Maximum of \(CustomModelStore.maxModels) custom models reached. Remove a model first."
        }
        if !hasFetchedModels(for: provider) {
            return "Fetch models from this provider first."
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    grokAccountCard
                    if !migrationIssues.isEmpty {
                        migrationIssueCard
                    }
                    if hasLoadedModelConfiguration, !modelConfigWriteSafety.canWrite {
                        advancedModelConfigurationCard
                    }
                    defaultModelCard
                    observedPerformanceCard
                    providerTemplatesCard
                    if showingProviderEditor {
                        providerEditorCard
                            .id(providerEditorAnchor)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    yourProvidersCard
                    if showingModelEditor {
                        editorCard
                            .id(modelEditorAnchor)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    modelListCard
                }
                .animation(.easeInOut(duration: 0.2), value: showingProviderEditor)
                .animation(.easeInOut(duration: 0.2), value: showingModelEditor)
                .animation(.easeInOut(duration: 0.2), value: showingProviderTemplates)
                .centeredSettingsColumn()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.Palette.canvas)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                // The editor/provider card this targets is only inserted into the
                // hierarchy by the `showingModelEditor`/`showingProviderEditor` toggle
                // that triggers this same change, so scrolling in this tick would race
                // its layout and silently no-op. Defer one runloop turn so the card
                // exists before `scrollTo` looks it up.
                DispatchQueue.main.async {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
                scrollTarget = nil
            }
        }
        .task {
            await reload()
            guard !Task.isCancelled else { return }
            let catalog = await GrokModelCatalog.shared.models()
            guard !Task.isCancelled else { return }
            builtInModels = catalog
        }
        .task {
            await refreshGrokAuthentication()
        }
        .onDisappear {
            openRouterOAuthTask?.cancel()
            openRouterOAuthTask = nil
        }
        .onChange(of: liveReceipt) { _, receipt in
            valueState.refreshLive(
                receipt?.freshness == .live ? receipt?.requestedModelID : nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelPerformanceObservationsChanged)) { _ in
            observationRevision &+= 1
        }
        .alert("Remove Model?", isPresented: $showModelRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                modelPendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let model = modelPendingRemoval {
                    remove(model)
                }
                modelPendingRemoval = nil
            }
        } message: {
            if let model = modelPendingRemoval {
                let label = model.name.isEmpty ? model.id : model.name
                Text("Remove \(label) from ~/.grok/config.toml? You won't be able to use /model \(model.id) until you add it again.")
            }
        }
        .alert("Remove Provider?", isPresented: $showProviderRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                providerPendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let provider = providerPendingRemoval {
                    removeProvider(provider)
                }
                providerPendingRemoval = nil
            }
        } message: {
            if let provider = providerPendingRemoval {
                Text("Remove \(provider.name) from your providers? This cannot be undone.")
            }
        }
        .alert("Clear Local Model Observations?", isPresented: $showObservationClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Local Observations", role: .destructive) {
                ModelPerformanceObservationStore.clear()
                observationRevision &+= 1
            }
        } message: {
            Text("This removes only GrokBuild's bounded model-performance observations from this Mac. Provider credentials, model configuration, Grok history, and transcripts are unchanged.")
        }
    }

    private let providerEditorAnchor = "provider-editor"
    private let modelEditorAnchor = "model-editor"

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Models",
                subtitle: "Add OpenAI-compatible providers and choose the models available to Grok.",
                systemImage: SettingsTab.models.systemImage
            )
            SettingsPaneStateHeader(status: valueState.status)
        }
    }

    private var grokAccountCard: some View {
        settingsCard(title: "Grok Account", systemImage: "person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(grokAuthenticationState.label)
                            .font(.subheadline.weight(.semibold))
                        Text(grokAuthenticationState.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if grokAuthenticationState == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        badge(
                            grokAuthenticationState.label,
                            systemImage: grokAuthenticationState.isSignedIn
                                ? "checkmark.circle.fill"
                                : "person.crop.circle.badge.exclamationmark"
                        )
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        openTerminalForGrokLogin()
                    } label: {
                        Label(
                            grokAuthenticationState.isSignedIn ? "Sign in again…" : "Sign in with Grok…",
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(GrokProminentButtonStyle())
                    .controlSize(.small)
                    .disabled(GrokAuthentication.loginCommand() == nil)

                    Button("Copy command") { copyGrokLoginCommand() }
                        .controlSize(.small)
                        .disabled(GrokAuthentication.loginCommand() == nil)

                    Button("Check again") {
                        Task { await refreshGrokAuthentication() }
                    }
                    .controlSize(.small)
                    .disabled(grokAuthenticationState == .checking)
                }

                Text("Sign-in is owned by the grok CLI and xAI's browser flow. GrokBuild stores no Grok password or session token.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var migrationIssueCard: some View {
        settingsCard(title: "Credential migration needs attention", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(migrationIssues) { issue in
                    Text("\(issue.providerID): \(issue.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var advancedModelConfigurationCard: some View {
        settingsCard(title: "Advanced model configuration", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 6) {
                Text(modelConfigWriteSafety.blockingMessage ?? "Model configuration is read-only in GrokBuild.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Palette.warning)
                    .textSelection(.enabled)
                Text("You can still inspect models here. Add, edit, remove, provider, and default-model writes stay locked so the official CLI configuration remains intact.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultModelCard: some View {
        settingsCard(title: "Default Model", systemImage: "checkmark.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Used when you start a new session. Existing sessions keep their current model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Picker("Default model", selection: Binding(
                        get: { defaultModelID },
                        set: { defaultModelID = $0 }
                    )) {
                        ForEach(defaultModelOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                    .disabled(!hasLoadedModelConfiguration)

                    Spacer()

                    Button("Apply Default") { Task { await applyDefaultModel() } }
                    .buttonStyle(GrokProminentButtonStyle())
                    .controlSize(.small)
                    .disabled(!isDefaultModelDirty || !canWriteModelConfiguration)
                }
                Text("Applies to future inherited tabs only; existing tab choices and live process receipts are unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)
            }
        }
    }

    private var modelPerformanceSummaries: [ModelPerformanceObservationSummary] {
        _ = observationRevision
        return ModelPerformanceObservationStore.summaries()
    }

    private var observedPerformanceCard: some View {
        settingsCard(title: "Observed on this Mac", systemImage: "chart.xyaxis.line") {
            let summaries = modelPerformanceSummaries
            VStack(alignment: .leading, spacing: 12) {
                Text("Local completion receipts grouped by exact model, route, and comparable workload class. These observations never choose a model, claim a best model, or turn unlike work into a quality score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if summaries.isEmpty {
                    Text("No comparable completed-turn observations are stored.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summaries) { summary in
                        modelPerformanceRow(summary)
                        if summary.id != summaries.last?.id {
                            Divider()
                        }
                    }
                }

                HStack {
                    Text("Missing measurements stay missing; absent prices never become $0.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear local observations", role: .destructive) {
                        showObservationClearConfirmation = true
                    }
                    .controlSize(.small)
                    .disabled(summaries.isEmpty)
                    .accessibilityIdentifier("grok-clear-model-performance-observations")
                }
            }
        }
        .accessibilityIdentifier("grok-observed-model-performance")
    }

    private func modelPerformanceRow(_ summary: ModelPerformanceObservationSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.modelID)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
                Text(summary.routeKind.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(summary.sampleCount) \(summary.sampleCount == 1 ? "sample" : "samples")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(summary.workloadClass.displayName)
                .font(.caption.weight(.semibold))
            Text("First chunk \(metricText(summary.firstChunkLatency, format: durationText)); provider API \(metricText(summary.providerAPIDuration, format: durationText)).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Tokens total \(metricText(summary.totalTokens, format: SessionUsageLedger.compactTokens)); input \(metricText(summary.inputTokens, format: SessionUsageLedger.compactTokens)); output \(metricText(summary.outputTokens, format: SessionUsageLedger.compactTokens)); cached \(metricText(summary.cachedReadTokens, format: SessionUsageLedger.compactTokens)); reasoning \(metricText(summary.reasoningTokens, format: SessionUsageLedger.compactTokens)).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Calls \(metricText(summary.modelCalls, format: String.init)); cost \(metricText(summary.costUsdTicks, format: costText)).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            let completion = percentage(summary.completionRate)
            let recovery = summary.recoveryRate.map(percentage) ?? "not observed"
            Text("Completion \(completion); explicit-retry recovery \(recovery); unresolved workers \(percentage(summary.unresolvedWorkerRate)).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Last route: \(summary.lastObservedRoute). \(summary.servingProviderIsProven ? "Serving provider proven by this route." : "Downstream serving provider unproven.")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func metricText(
        _ metric: ModelPerformanceObservationSummary.IntegerMetric?,
        format: (Int) -> String
    ) -> String {
        guard let metric else { return "not measured" }
        let median = format(metric.median)
        let range = metric.minimum == metric.maximum
            ? format(metric.minimum)
            : "\(format(metric.minimum))–\(format(metric.maximum))"
        return "median \(median), range \(range) (\(metric.sampleCount))"
    }

    private func durationText(_ milliseconds: Int) -> String {
        if milliseconds < 1_000 { return "\(milliseconds) ms" }
        return "\((Double(milliseconds) / 1_000).formatted(.number.precision(.fractionLength(1)))) s"
    }

    private func costText(_ ticks: Int) -> String {
        SessionUsageLedger.dollars(SessionUsageLedger.dollarsFromCostTicks(ticks)) + " provider-reported"
    }

    private func percentage(_ rate: Double) -> String {
        rate.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Provider templates (catalog)

    /// `true` when a preset has already been installed as one of `providers`.
    private func isPresetInstalled(_ preset: ProviderPreset) -> Bool {
        providers.contains { $0.id == preset.provider.id }
    }

    private var providerTemplatesCard: some View {
        settingsCard(title: "Add Provider", systemImage: "plus") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        showingProviderTemplates.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showingProviderTemplates ? 90 : 0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Provider Templates")
                                .font(.subheadline.weight(.semibold))
                            Text("Popular OpenAI-compatible providers. Install one, then use its listed connection method.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Group {
                    if showingProviderTemplates {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(ProviderPreset.allCases) { preset in
                                providerTemplateTile(preset)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider()

                    Button {
                        beginNewProvider()
                    } label: {
                        Label("Create custom provider…", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .disabled(isAnyEditorOpen)
                .opacity(isAnyEditorOpen ? 0.45 : 1)
            }
        }
    }

    private func providerTemplateTile(_ preset: ProviderPreset) -> some View {
        let template = preset.provider
        let installed = isPresetInstalled(preset)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(preset.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(template.baseURL)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !template.suggestedModel.isEmpty {
                Text("e.g. \(template.suggestedModel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(preset.connectionMethodLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Button(installed ? "Configure" : "Install") { addProviderPreset(preset) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(installed ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.glassBorder)
        )
    }

    // MARK: - Your providers (installed)

    private var yourProvidersCard: some View {
        settingsCard(title: "Providers", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 12) {
                if providers.isEmpty {
                    Text("No providers installed yet. Install one from a template above, or create a custom provider.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A provider holds a base URL and a Keychain-backed connection. Multiple models can reuse the same provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(providers) { provider in
                        providerRow(provider)
                        if provider.id != providers.last?.id { Divider() }
                    }
                }
            }
            .disabled(isAnyEditorOpen)
            .opacity(isAnyEditorOpen ? 0.45 : 1)
        }
    }

    private func providerRow(_ provider: Provider) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.headline)
                    providerKeyBadge(for: provider)
                    if provider.allowInsecureHTTP {
                        badge("Insecure HTTP", systemImage: "lock.open")
                    }
                    providerValidationBadge(for: provider)
                    let count = models.filter { $0.providerID == provider.id }.count
                    if count > 0 {
                        Text("\(count) model\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let fetched = fetchedModels[provider.id] {
                        if fetched.isEmpty {
                            Text("0 available")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(fetched.count) available")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(provider.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if fetchErrorProviderID == provider.id, let message = fetchErrorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let result = validationResults[provider.id] {
                    HStack(spacing: 6) {
                        Text(result.message)
                        Text("·")
                        Text("checked \(result.checkedAtLabel)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    let addModelDisabled = addModelDisabledReason(for: provider) != nil
                    Button("Add model") { beginNewModel(forProvider: provider) }
                        .controlSize(.small)
                        .disabled(addModelDisabled || !canWriteModelConfiguration)
                        .help(addModelDisabledReason(for: provider)
                            ?? "Add a model from the fetched list.")
                    Button("Edit") { beginEditingProvider(provider) }
                        .controlSize(.small)
                        .disabled(!canWriteModelConfiguration)
                    let inUse = modelsUsing(provider).count
                    Button("Remove", role: .destructive) {
                        providerPendingRemoval = provider
                        showProviderRemovalConfirmation = true
                    }
                        .controlSize(.small)
                        .disabled(inUse > 0 || !canWriteModelConfiguration)
                        .help(!canWriteModelConfiguration
                            ? modelConfigWriteBlockReason ?? "Model configuration is read-only."
                            : inUse > 0
                            ? "Remove its \(inUse) model\(inUse == 1 ? "" : "s") first before removing this provider."
                            : "Remove this provider.")
                }
                let canFetchProvider = canFetch(
                    baseURL: provider.baseURL,
                    apiKey: provider.apiKey,
                    authScheme: provider.authScheme,
                    providerID: provider.id
                )
                let highlightFetch = !hasFetchedModels(for: provider) && canFetchProvider
                Group {
                    if highlightFetch {
                        Button {
                            fetchModels(for: provider)
                        } label: {
                            if fetchingProviderID == provider.id {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Label("Test connection", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(GrokProminentButtonStyle())
                    } else {
                        Button {
                            fetchModels(for: provider)
                        } label: {
                            if fetchingProviderID == provider.id {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Label("Test connection", systemImage: "checkmark.circle")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                    }
                }
                .disabled(
                    fetchingProviderID == provider.id
                    || !canFetchProvider
                    || !canWriteModelConfiguration
                )
                .help(fetchHelp(for: provider, highlight: highlightFetch))

                if let result = validationResults[provider.id] {
                    Button("Copy diagnostics") {
                        copyToPasteboard(providerDiagnostics(provider: provider, result: result))
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                    .help("Copy endpoint, auth mode, and redacted connection status.")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func fetchHelp(for provider: Provider, highlight: Bool) -> String {
        if provider.supportsLiveCatalogRefresh {
            return highlight
                ? "Fetch the Cline Pass model list before adding a model (no API key required)."
                : "Refresh the Cline Pass model list (no API key required)."
        }
        return highlight
            ? "Fetch the provider's model list before adding a model."
            : "Refresh the provider's model list."
    }

    private func providerDiagnostics(provider: Provider, result: ProviderValidationResult) -> String {
        let missing = result.missingModelIDs.isEmpty ? "none" : result.missingModelIDs.joined(separator: ", ")
        return """
        Provider: \(provider.name) (\(provider.id))
        Endpoint: \(ProviderEndpointPolicy.redactedDisplay(urlString: provider.baseURL))
        Authentication: \(provider.authScheme.rawValue)
        Connection method: \(provider.credentialMethodLabel)
        Credential present: \(provider.hasInlineKey ? "yes" : "no")
        Status: \(result.status.rawValue)
        Models returned: \(result.models.count)
        Missing configured models: \(missing)
        Checked: \(result.checkedAt.formatted(.iso8601))
        """
    }

    @ViewBuilder
    private func providerKeyBadge(for provider: Provider) -> some View {
        if provider.hasInlineKey {
            badge(provider.credentialMethodLabel, systemImage: "key.fill")
        } else if provider.isLocalEndpoint {
            badge("Local", systemImage: "desktopcomputer")
        } else {
            badge("No key", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private func providerValidationBadge(for provider: Provider) -> some View {
        if fetchingProviderID == provider.id {
            badge("Checking", systemImage: "arrow.triangle.2.circlepath")
        } else if let result = validationResults[provider.id] {
            switch result.status {
            case .connected:
                badge("Connected", systemImage: "checkmark.circle.fill")
            case .modelUnavailable:
                badge("Model missing", systemImage: "exclamationmark.triangle.fill")
            case .unauthorized:
                badge("Unauthorized", systemImage: "key.slash")
            case .rateLimited:
                badge("Rate limited", systemImage: "clock")
            case .endpointMissing:
                badge("Endpoint missing", systemImage: "link.badge.plus")
            case .providerUnavailable, .timeoutOrOffline:
                badge("Offline", systemImage: "wifi.slash")
            case .incompatibleResponse, .emptyCatalog:
                badge("Catalog issue", systemImage: "exclamationmark.circle")
            case .insecureEndpoint:
                badge("Insecure URL", systemImage: "lock.slash")
            case .redirectBlocked:
                badge("Redirect blocked", systemImage: "arrow.uturn.right.circle")
            }
        } else {
            badge("Not tested", systemImage: "questionmark.circle")
        }
    }

    private var providerEditorTitle: String {
        if isEditingProvider { return "Edit Provider" }
        if providerDraftFromPreset { return "Install \(providerDraft.name)" }
        return "Add New Provider"
    }

    /// True when the provider needs a key but none is set yet (drives the "enter your key" prompt).
    private var providerNeedsKey: Bool {
        !providerDraft.isLocalEndpoint
            && providerDraft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var providerEditorCard: some View {
        settingsCard(title: providerEditorTitle, systemImage: "plus.square.on.square") {
            VStack(alignment: .leading, spacing: 12) {
                if providerDraftFromPreset && providerNeedsKey {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text(providerDraft.id == ProviderPreset.openrouter.provider.id
                             ? "Connect with OpenRouter in your browser or paste an API key. Nothing is saved until the connection succeeds or you tap **Add Provider**."
                             : "Enter your \(providerDraft.name) API key, then tap **Add Provider** to install it. Nothing is saved until you do.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.small).fill(AppTheme.Palette.glassTint))
                }

                // Pointer clicks between these fields do not reliably move AppKit's
                // first responder: the draft binds through the view model's computed
                // properties and the pane re-renders per keystroke, and NSTextField
                // swallows mousedowns before SwiftUI gestures see them (stable ids and
                // tap gestures both failed in live testing). The focusClickCatcher
                // overlay exists only while its field is unfocused — it takes the
                // first click, drives FocusState, then vanishes so native editing and
                // selection work untouched.
                settingRow("Provider id") {
                    TextField("openai", text: $providerDraft.id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isEditingProvider || providerDraftFromPreset)
                        .frame(maxWidth: 280)
                        .id("provider-editor-id")
                        .focused($providerEditorFocus, equals: .id)
                        .overlay(focusClickCatcher(for: .id))
                }
                settingRow("Name") {
                    TextField("ChatGPT (OpenAI)", text: $providerDraft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .id("provider-editor-name")
                        .focused($providerEditorFocus, equals: .name)
                        .overlay(focusClickCatcher(for: .name))
                }
                settingRow("Base URL") {
                    TextField("https://api.openai.com/v1", text: $providerDraft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .id("provider-editor-url")
                        .focused($providerEditorFocus, equals: .url)
                        .overlay(focusClickCatcher(for: .url))
                }
                if ProviderEndpointPolicy.locality(ofBaseURL: providerDraft.baseURL) == .remote,
                   !ProviderEndpointPolicy.isHTTPS(providerDraft.baseURL) {
                    settingRow("Insecure HTTP") {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Allow http:// for this trusted LAN endpoint", isOn: $providerDraft.allowInsecureHTTP)
                                .toggleStyle(.checkbox)
                            Text("Requests — including any API key — travel unencrypted. Only for model servers on hardware you control.")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.Palette.warning)
                        }
                    }
                }
                settingRow("Authentication") {
                    Picker("Authentication", selection: $providerDraft.authScheme) {
                        Text("Bearer token").tag(ProviderAuthScheme.bearer)
                        Text("API key header").tag(ProviderAuthScheme.apiKeyHeader)
                        Text("Bearer + API key").tag(ProviderAuthScheme.bearerAndAPIKey)
                        Text("None / local").tag(ProviderAuthScheme.none)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .disabled(providerDraftFromPreset)
                }
                if providerDraft.id == ProviderPreset.openrouter.provider.id {
                    openRouterOAuthRow
                }
                settingRow("API key") {
                    HStack(spacing: 8) {
                        Group {
                            if revealProviderKey {
                                TextField("sk-… (leave empty for local servers)", text: $providerDraft.apiKey)
                            } else {
                                SecureField("sk-… (leave empty for local servers)", text: $providerDraft.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .focused($providerEditorFocus, equals: .key)
                        .overlay(focusClickCatcher(for: .key))
                        Button {
                            revealProviderKey.toggle()
                        } label: {
                            Image(systemName: revealProviderKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealProviderKey ? "Hide API key" : "Show API key")
                        .accessibilityLabel(revealProviderKey ? "Hide API key" : "Show API key")
                    }
                }

                Text("Credentials stay in macOS Keychain with device-only accessibility. GrokBuild writes only the CLI's official auth-helper reference to ~/.grok/config.toml; the helper returns the credential directly to Grok at runtime. Local/open servers don't need a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerFetchRow

                HStack(spacing: 10) {
                    Button(isEditingProvider ? "Save Provider" : "Add Provider") { _ = saveProviderDraft() }
                        .buttonStyle(GrokProminentButtonStyle())
                        .disabled(providerDraft.validationError != nil || !canWriteModelConfiguration)
                    Button("Cancel") { resetProviderDraft() }
                    Spacer()
                    if let error = providerDraft.validationError, !providerDraft.id.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var openRouterOAuthRow: some View {
        settingRow("OpenRouter OAuth") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    if openRouterOAuthTask != nil {
                        ProgressView().controlSize(.small)
                        Text("Waiting for browser authorization…")
                            .font(.caption)
                        Button("Cancel") { cancelOpenRouterOAuth() }
                            .controlSize(.small)
                    } else {
                        Button {
                            connectOpenRouterWithOAuth()
                        } label: {
                            Label("Connect with OpenRouter…", systemImage: "safari")
                        }
                        .buttonStyle(GrokProminentButtonStyle())
                        .controlSize(.small)
                        .disabled(!canWriteModelConfiguration)

                        if providerDraft.credentialMetadata.kind == .oauthIssuedKey {
                            badge("OAuth key saved", systemImage: "checkmark.circle.fill")
                        }
                    }
                }

                Text("Uses OpenRouter's S256 browser flow and returns an API key to this Mac. The key is stored in Keychain; no browser password reaches GrokBuild.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let openRouterOAuthError {
                    Text(openRouterOAuthError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if providerDraft.hasInlineKey && isEditingProvider {
                    HStack(spacing: 10) {
                        Button("Disconnect locally", role: .destructive) {
                            disconnectOpenRouterLocally()
                        }
                        .controlSize(.small)
                        .disabled(!canWriteModelConfiguration)
                        Link(
                            "Manage or revoke remote keys",
                            destination: URL(string: "https://openrouter.ai/settings/keys")!
                        )
                        .font(.caption)
                    }
                    Text("Disconnect locally removes the Keychain item and Grok CLI projection. Remote revocation remains an explicit OpenRouter account action.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Fetch models" control + result/error summary inside the provider editor.
    @ViewBuilder
    private var providerFetchRow: some View {
        providerModelFetchRow
    }

    @ViewBuilder
    private var providerModelFetchRow: some View {
        let draftKey = providerDraft.id.isEmpty ? "__draft__" : providerDraft.id
        let isFetching = fetchingProviderID == draftKey
        let fetched = fetchedModels[draftKey] ?? []
        let canFetchNow = canFetch(
            baseURL: providerDraft.baseURL,
            apiKey: providerDraft.apiKey,
            authScheme: providerDraft.authScheme,
            providerID: providerDraft.id
        )
        let usesLiveCatalog = providerDraft.supportsLiveCatalogRefresh
            || ProviderPreset.matching(provider: providerDraft)?.supportsLiveCatalogRefresh == true

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    fetchModelsForDraft()
                } label: {
                    if isFetching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Fetching…")
                        }
                    } else {
                        Label("Test connection", systemImage: "checkmark.circle")
                    }
                }
                .controlSize(.small)
                .disabled(!canFetchNow || isFetching || !canWriteModelConfiguration)

                if !fetched.isEmpty {
                    Text("\(fetched.count) model\(fetched.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let docsURL = ProviderPreset.matching(provider: providerDraft)?.catalogDocumentationURL {
                    Link("Documentation", destination: docsURL)
                        .font(.caption)
                }
            }

            Text(usesLiveCatalog
                 ? "Fetches the live Cline Pass catalog (no API key required)."
                 : "Queries \(ProviderModelFetcher.modelsURL(for: providerDraft.baseURL)?.absoluteString ?? "the provider")/… to list available models. Enter the API key first (local servers need none).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if fetchErrorProviderID == draftKey, let message = fetchErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !fetched.isEmpty {
                Text("Tip: Save this provider, then use “Add model” to pick from the fetched list.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Model list

    private var modelListCard: some View {
        settingsCard(title: "Models", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(models.count)/\(CustomModelStore.maxModels) custom models")
                    .font(.caption)
                    .foregroundStyle(isAtModelLimit ? AppTheme.Palette.warning : .secondary)

                Group {
                    if models.isEmpty {
                        Text("No models yet. Use “Add model” on a provider above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(models) { model in
                            modelRow(model)
                            if model.id != models.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .disabled(isAnyEditorOpen)
                .opacity(isAnyEditorOpen ? 0.45 : 1)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func modelRow(_ model: CustomModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.headline)
                Text("/model \(model.id)  ·  \(model.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(modelMetadataSummary(model))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Edit") { beginEditing(model) }
                    .controlSize(.small)
                    .disabled(!canWriteModelConfiguration)
                Button("Remove", role: .destructive) {
                    modelPendingRemoval = model
                    showModelRemovalConfirmation = true
                }
                    .controlSize(.small)
                    .disabled(!canWriteModelConfiguration)
            }
        }
        .padding(.vertical, 4)
    }

    private func modelMetadataSummary(_ model: CustomModel) -> String {
        var pieces: [String] = [model.apiBackend.displayName]
        if let tokens = model.contextTokens {
            pieces.append("\(compactTokenCount(tokens)) context")
        } else {
            pieces.append("context unknown")
        }
        pieces.append(model.supportsReasoningEffort ? "reasoning effort on" : "reasoning effort off")
        if model.supportsVision {
            pieces.append("vision")
        }
        if model.supportsThinkingDisplay {
            pieces.append("thinking")
        }
        return pieces.joined(separator: " · ")
    }

    private func compactTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M"
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K"
        }
        return "\(tokens)"
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Editor

    private var editorCard: some View {
        settingsCard(title: isEditing ? "Edit Model" : "Add Model", systemImage: "plus.rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("Provider") {
                    Picker("", selection: providerSelection) {
                        Text("None (advanced manual endpoint)").tag("")
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .disabled(providers.isEmpty)
                }

                if let provider = providers.first(where: { $0.id == draft.providerID }) {
                    settingRow("") {
                        HStack(spacing: 8) {
                            Button {
                                fetchModels(for: provider)
                            } label: {
                                if fetchingProviderID == provider.id {
                                    HStack(spacing: 5) {
                                        ProgressView().controlSize(.small)
                                        Text("Checking…")
                                    }
                                } else {
                                    Label("Fetch models from \(provider.name)", systemImage: "arrow.down.circle")
                                }
                            }
                            .controlSize(.small)
                            .disabled(
                                fetchingProviderID == provider.id
                                || !canWriteModelConfiguration
                                || !canFetch(
                                    baseURL: provider.baseURL,
                                    apiKey: provider.apiKey,
                                    authScheme: provider.authScheme,
                                    providerID: provider.id
                                )
                            )
                            if let docsURL = provider.catalogDocumentationURL {
                                Link("Documentation", destination: docsURL)
                                    .font(.caption)
                            }
                            if fetchErrorProviderID == provider.id, let message = fetchErrorMessage {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    settingRow("Choose model") {
                        VStack(alignment: .leading, spacing: 6) {
                            // Large catalogs (OpenRouter returns ~300+) are unusable as a
                            // bare dropdown; a filter field narrows it as you type.
                            if selectableModelsForDraft.count > 12 {
                                TextField(
                                    "Filter \(selectableModelsForDraft.count) models (e.g. anthropic/)…",
                                    text: $modelFilterText
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                            }
                            HStack(spacing: 8) {
                                Picker("", selection: fetchedModelSelection) {
                                    Text(modelPickerPlaceholder(for: provider)).tag("")
                                    ForEach(filteredSelectableModels) { fetched in
                                        Text(modelPickerLabel(fetched)).tag(fetched.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 280)
                                .disabled(selectableModelsForDraft.isEmpty)
                                if !selectableModelsForDraft.isEmpty {
                                    Text(filteredCountLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onChange(of: draft.providerID) { _, _ in modelFilterText = "" }
                        // The provider-change reset alone leaked filter text across
                        // editor sessions: reopening the editor mounts fresh, so
                        // onChange never fires, and a catalog small enough to hide
                        // the filter field (≤ 12 models) left a stale invisible
                        // filter showing "0/N" with no way to clear it in the UI.
                        .onAppear { modelFilterText = "" }
                    }
                }

                if let provider = draftProvider,
                   ProviderPreset.matching(provider: provider) == nil {
                    Toggle("Advanced: allow an unverified model ID", isOn: $allowUnverifiedCustomModel)
                        .font(.caption)
                    Text("Use this only when a custom or local provider does not expose a complete model catalog.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                settingRow("Model id") {
                    TextField(modelIDPlaceholder, text: $draft.id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .frame(maxWidth: 280)
                }
                settingRow("Model") {
                    TextField(modelNamePlaceholder, text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onChange(of: draft.model) { _, newValue in
                            guard !isEditing else { return }
                            syncModelID(from: newValue)
                        }
                }
                settingRow("Display name") {
                    TextField(displayNamePlaceholder, text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                settingRow("API protocol") {
                    Picker("API protocol", selection: $draft.apiBackend) {
                        ForEach(ModelAPIBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }

                if draft.providerID == nil {
                    // Manual endpoint + credential when not linked to a provider.
                    settingRow("Base URL") {
                        TextField("https://api.example.com/v1", text: $draft.baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    settingRow("API key") {
                        HStack(spacing: 8) {
                            Group {
                                if revealKey {
                                    TextField("sk-… (leave empty for local servers)", text: $draft.apiKey)
                                } else {
                                    SecureField("sk-… (leave empty for local servers)", text: $draft.apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(revealKey ? "Hide API key" : "Show API key")
                            .accessibilityLabel(revealKey ? "Hide API key" : "Show API key")
                        }
                    }
                    Text("Authenticated remote models must use a saved provider so the credential stays in Keychain behind the CLI auth helper. GrokBuild refuses new inline remote credentials. Local/open servers don't need a key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let provider = providers.first(where: { $0.id == draft.providerID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Text("Endpoint and Keychain-backed CLI auth come from \(provider.name) (\(provider.baseURL)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Divider()

                Text("Model metadata")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                settingRow("Context window") {
                    HStack(spacing: 8) {
                        TextField("Unknown", text: contextTokensBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                        Text("tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(contextTokenPresets) { preset in
                            Button(preset.label) {
                                draft.contextTokens = preset.value
                            }
                            .controlSize(.small)
                        }
                        Button("Clear") {
                            draft.contextTokens = nil
                        }
                        .controlSize(.small)
                    }
                }

                settingRow("Capabilities") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Supports reasoning effort", isOn: $draft.supportsReasoningEffort)
                        Toggle("Supports image input", isOn: $draft.supportsVision)
                        Toggle("Shows thinking blocks", isOn: $draft.supportsThinkingDisplay)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                Text("API protocol and context window are native Grok settings. The capability checkboxes are GrokBuild-only UI hints kept outside config.toml.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(isEditing ? "Save Changes" : "Add Model") { saveDraft() }
                        .buttonStyle(GrokProminentButtonStyle())
                        .disabled(draftSaveBlockedReason != nil)
                    Button("Cancel") { resetDraft() }
                    Spacer()
                    if let error = draftSaveBlockedReason, !draft.model.isEmpty || !draft.id.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The draft with provider endpoint/credentials applied, used for validation and preview.
    private var resolvedDraft: CustomModel {
        draft.resolved(using: providers)
    }

    /// Binding for the fetched-model picker. Selecting an id fills the model name and derives
    /// the config.toml model id from it.
    private var fetchedModelSelection: Binding<String> {
        Binding(
            get: {
                let current = draft.model.trimmingCharacters(in: .whitespaces)
                return selectableModelsForDraft.contains(where: { $0.id == current }) ? current : ""
            },
            set: { newValue in
                guard !isEditing else {
                    if !newValue.isEmpty { draft.model = newValue }
                    return
                }
                if newValue.isEmpty {
                    draft.model = ""
                    draft.id = ""
                    draft.name = ""
                    return
                }
                draft.model = newValue
                syncModelID(from: newValue)
                if let picked = selectableModelsForDraft.first(where: { $0.id == newValue }),
                   let displayName = picked.ownedBy,
                   !displayName.isEmpty,
                   !Self.genericCatalogOwnerLabels.contains(displayName.lowercased()) {
                    // Generic owner strings (OpenAI's /v1/models reports owned_by
                    // "system") are not display names; auto-filling them made the
                    // composer show a model called "system" unless hand-corrected.
                    if draftProvider?.supportsLiveCatalogRefresh == true {
                        draft.name = ClinePassCatalog.displayName(for: displayName)
                    } else {
                        draft.name = displayName
                    }
                }
            }
        )
    }

    private func modelPickerLabel(_ model: FetchedModel) -> String {
        if let name = model.ownedBy, !name.isEmpty {
            return "\(name) — \(model.id)"
        }
        return model.id
    }

    /// Derives `draft.id` from a provider model name, uniquifying against existing models.
    private func syncModelID(from modelName: String) {
        let base = CustomModel.suggestedID(from: modelName)
        draft.id = uniquifiedModelID(base)
    }

    /// Returns a model id that does not collide with an existing entry (unless editing that entry).
    private func uniquifiedModelID(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var candidate = trimmed
        var suffix = 2
        while models.contains(where: { $0.id == candidate && $0.id != editingID }) {
            candidate = "\(trimmed)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Validation for the save button, including duplicate-id checks when adding a new model.
    private var draftSaveBlockedReason: String? {
        if let reason = modelConfigWriteBlockReason { return reason }
        if let error = resolvedDraft.validationError { return error }
        if let provider = draftProvider {
            let appearsInCatalog = selectableModelsForDraft.contains { $0.id == draft.model }
            if ProviderPreset.matching(provider: provider) != nil, !appearsInCatalog {
                return "Test the connection and choose a model returned by this provider."
            }
            if ProviderPreset.matching(provider: provider) == nil,
               !appearsInCatalog,
               !allowUnverifiedCustomModel {
                return "Choose a fetched model, or explicitly allow an unverified custom model ID."
            }
        }
        if !isEditing, models.count >= CustomModelStore.maxModels {
            return "GrokBuild supports up to \(CustomModelStore.maxModels) custom models."
        }
        if !isEditing, models.contains(where: { $0.id == draft.id }) {
            return "A model with this id already exists."
        }
        return nil
    }

    /// Binding that maps the model's optional providerID to the picker's string tag.
    private var providerSelection: Binding<String> {
        Binding(
            get: { draft.providerID ?? "" },
            set: { newValue in
                allowUnverifiedCustomModel = false
                if newValue.isEmpty {
                    draft.providerID = nil
                } else {
                    draft.providerID = newValue
                    if let provider = providers.first(where: { $0.id == newValue }),
                       let preset = ProviderPreset.matching(provider: provider) {
                        draft.apiBackend = preset.defaultAPIBackend
                    }
                    if !isEditing {
                        draft.model = ""
                        draft.id = ""
                        draft.name = ""
                    }
                }
            }
        )
    }

    // MARK: - Actions

    private func refreshGrokAuthentication() async {
        grokAuthenticationState = .checking
        grokAuthenticationState = await GrokAuthentication.check()
    }

    private func openTerminalForGrokLogin() {
        guard let command = GrokAuthentication.loginCommand() else { return }
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }

    private func copyGrokLoginCommand() {
        guard let command = GrokAuthentication.loginCommand() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func reload() async {
        hasLoadedModelConfiguration = false
        // Keychain reads can wait on securityd. Running them synchronously in this
        // SwiftUI task freezes every click and even the accessibility server.
        let loaded = await GrokBuildPerformance.measure(.providerCredentialMetadataLoad) {
            await SettingsBackgroundLoader.run {
                let snapshot = CustomModelStore.load()
                let providers = ProviderStore.loadResult(
                    migrationModels: snapshot.models,
                    allowCredentialMigration: snapshot.writeSafety.canWrite
                )
                return (providers, snapshot)
            }
        }
        guard !Task.isCancelled else { return }
        let providerLoad = loaded.0
        let snapshot = loaded.1
        providers = providerLoad.providers
        migrationIssues = providerLoad.migrationIssues
        modelConfigWriteSafety = snapshot.writeSafety
        hasLoadedModelConfiguration = true
        let savedDefault = snapshot.defaultModelID ?? ""
        valueState.load(
            persisted: savedDefault,
            applied: savedDefault,
            live: liveReceipt?.freshness == .live ? liveReceipt?.requestedModelID : nil
        )
        // Only an explicit app-owned legacy provider id or an official managed
        // model_provider reference proves ownership. Matching a URL is not proof:
        // two users can legitimately configure the same endpoint independently.
        let resolvedModels = snapshot.models.map { $0.resolved(using: providers) }
        models = resolvedModels

        let everyLegacyModelHasExactOwnership = resolvedModels.allSatisfy { model in
            model.providerID != nil
        }
        let needsOfficialProviderProjection = !resolvedModels.isEmpty
            && everyLegacyModelHasExactOwnership
            && resolvedModels.contains { $0.providerID != nil }
        if !snapshot.usesOfficialProviderProjection,
           needsOfficialProviderProjection,
           snapshot.writeSafety.canWrite,
           !providerLoad.migrationIssues.contains(where: { $0.kind == .storage }) {
            do {
                try CustomModelStore.save(
                    models: resolvedModels,
                    defaultModelID: snapshot.defaultModelID,
                    providers: providers
                )
                statusMessage = "Provider credentials migrated to Keychain; secured CLI configuration."
            } catch {
                errorMessage = "Credential migration could not update config.toml: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Provider actions

    private func connectOpenRouterWithOAuth() {
        guard providerDraft.id == ProviderPreset.openrouter.provider.id,
              openRouterOAuthTask == nil else { return }
        let previousDraft = providerDraft
        openRouterOAuthError = nil
        openRouterOAuthTask = Task {
            do {
                let key = try await OpenRouterOAuth.connect()
                try Task.checkCancellation()
                providerDraft.apiKey = key
                providerDraft.credentialMetadata = .openRouterOAuth()
                openRouterOAuthTask = nil
                if saveProviderDraft() {
                    statusMessage = "OpenRouter connected. Credential saved in Keychain."
                } else {
                    providerDraft = previousDraft
                }
            } catch is CancellationError {
                openRouterOAuthTask = nil
                openRouterOAuthError = "OpenRouter authorization was cancelled. Nothing changed."
            } catch {
                openRouterOAuthTask = nil
                openRouterOAuthError = error.localizedDescription
            }
        }
    }

    private func cancelOpenRouterOAuth() {
        openRouterOAuthTask?.cancel()
        openRouterOAuthTask = nil
        openRouterOAuthError = "OpenRouter authorization was cancelled. Nothing changed."
    }

    private func disconnectOpenRouterLocally() {
        guard providerDraft.id == ProviderPreset.openrouter.provider.id else { return }
        let previousDraft = providerDraft
        providerDraft.apiKey = ""
        providerDraft.credentialMetadata = .none
        if saveProviderDraft() {
            statusMessage = "OpenRouter disconnected locally. No remote key was revoked."
        } else {
            providerDraft = previousDraft
        }
    }

    /// Installing a template stages it in the editor (key empty) instead of persisting it
    /// immediately — the provider is only saved once the user enters a key and taps Save.
    /// If the preset is already installed, jump to editing the existing one.
    private func addProviderPreset(_ preset: ProviderPreset) {
        if let existing = providers.first(where: { $0.id == preset.provider.id }) {
            beginEditingProvider(existing)
            return
        }
        providerDraft = preset.provider
        editingProviderID = nil
        providerDraftFromPreset = true
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func beginNewProvider() {
        providerDraft = Provider(id: "", name: "", baseURL: "")
        editingProviderID = nil
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func beginEditingProvider(_ provider: Provider) {
        providerDraft = provider
        editingProviderID = provider.id
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func resetProviderDraft() {
        openRouterOAuthTask?.cancel()
        openRouterOAuthTask = nil
        openRouterOAuthError = nil
        providerDraft = Provider(id: "", name: "", baseURL: "")
        editingProviderID = nil
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = false
    }

    @discardableResult
    private func saveProviderDraft() -> Bool {
        guard providerDraft.validationError == nil else { return false }
        guard canWriteModelConfiguration else {
            errorMessage = modelConfigWriteBlockReason
            return false
        }
        let previousProviders = providers
        let trimmedCredential = providerDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCredential.isEmpty {
            providerDraft.credentialMetadata = .none
        } else if providerDraft.credentialMetadata.kind == .none,
                  providerDraft.authScheme != .none {
            providerDraft.credentialMetadata = .apiKey()
        }
        let affectedModelIDs = Set(modelsUsingProviderID(editingProviderID ?? providerDraft.id).map(\.id))
        var updatedProviders = providers
        var updatedModels = models
        if let editingProviderID,
           let index = updatedProviders.firstIndex(where: { $0.id == editingProviderID }) {
            updatedProviders[index] = providerDraft
            // Propagate endpoint/credential changes to models linked to this provider.
            updatedModels = models.map {
                $0.providerID == editingProviderID ? $0.resolved(using: updatedProviders) : $0
            }
        } else if let index = updatedProviders.firstIndex(where: { $0.id == providerDraft.id }) {
            updatedProviders[index] = providerDraft
        } else {
            updatedProviders.append(providerDraft)
        }
        do {
            try ProviderModelConfigurationTransaction.save(
                previousProviders: previousProviders,
                updatedProviders: updatedProviders,
                models: updatedModels.map { $0.resolved(using: updatedProviders) },
                defaultModelID: persistedDefaultModelIDForConfig
            )
            providers = updatedProviders
            models = updatedModels
            resetProviderDraft()
            recordConfigurationPersistenceSuccess(change: .models(affectedModelIDs))
            return true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            return false
        }
    }

    /// Models currently attached to (in use by) the given provider.
    private func modelsUsing(_ provider: Provider) -> [CustomModel] {
        models.filter { $0.providerID == provider.id }
    }

    private func modelsUsingProviderID(_ providerID: String) -> [CustomModel] {
        models.filter { $0.providerID == providerID }
    }

    private func removeProvider(_ provider: Provider) {
        guard canWriteModelConfiguration else {
            errorMessage = modelConfigWriteBlockReason
            return
        }
        // A provider can only be removed once none of its models reference it, so the
        // user explicitly removes the models first and we never orphan config.toml tables.
        guard modelsUsing(provider).isEmpty else { return }
        let previousProviders = providers
        let updatedProviders = providers.filter { $0.id != provider.id }
        do {
            try ProviderModelConfigurationTransaction.save(
                previousProviders: previousProviders,
                updatedProviders: updatedProviders,
                models: models.map { $0.resolved(using: updatedProviders) },
                defaultModelID: persistedDefaultModelIDForConfig
            )
            providers = updatedProviders
            if editingProviderID == provider.id { resetProviderDraft() }
            fetchedModels[provider.id] = nil
            validationResults[provider.id] = nil
            recordConfigurationPersistenceSuccess(change: .models([]))
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    // MARK: - Fetch models

    /// Fetches the model catalog for the provider draft currently being edited/created.
    private func fetchModelsForDraft() {
        let draftSnapshot = providerDraft
        guard !draftSnapshot.baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        validateProvider(draftSnapshot)
    }

    /// Fetches the model catalog for an already-installed provider.
    private func fetchModels(for provider: Provider) {
        validateProvider(provider)
    }

    private func validateProvider(_ provider: Provider) {
        guard canWriteModelConfiguration else {
            errorMessage = modelConfigWriteBlockReason
            return
        }
        let key = provider.id.isEmpty ? "__draft__" : provider.id
        fetchingProviderID = key
        fetchErrorProviderID = nil
        fetchErrorMessage = nil
        let configuredModelIDs = models
            .filter { $0.providerID == provider.id || ($0.providerID == nil && $0.baseURL == provider.baseURL) }
            .map(\.model)
        Task {
            let result = await ProviderModelFetcher.validate(
                provider: provider,
                configuredModelIDs: configuredModelIDs
            )
            await MainActor.run {
                // Only clear the busy marker if it is still ours — a second provider's
                // check may have started while this one was in flight.
                if fetchingProviderID == key { fetchingProviderID = nil }
                // Never resurrect state for a provider removed mid-check.
                guard key == "__draft__" || providers.contains(where: { $0.id == key }) else { return }
                fetchedModels[key] = result.models
                // Slice 6: capture catalog-advertised per-token pricing (OpenRouter)
                // for display-side usage estimates. Non-secret; no extra requests.
                ModelPricingStore.record(result.models)
                validationResults[key] = result
                if result.status == .connected,
                   let index = providers.firstIndex(where: { $0.id == key }),
                   providers[index].credentialMetadata.kind != .none {
                    providers[index].credentialMetadata.lastValidatedAt = result.checkedAt
                    do {
                        try ProviderStore.save(providers)
                    } catch {
                        errorMessage = "Connection succeeded, but validation metadata could not be saved: \(error.localizedDescription)"
                    }
                }
                if result.status != .connected {
                    fetchErrorProviderID = key
                    fetchErrorMessage = result.message
                }
            }
        }
    }

    /// Models available for the provider linked to the current model draft (fetched or catalog).
    private var filteredSelectableModels: [FetchedModel] {
        ProviderModelFetcher.filterModels(selectableModelsForDraft, query: modelFilterText)
    }

    private var filteredCountLabel: String {
        let total = selectableModelsForDraft.count
        let shown = filteredSelectableModels.count
        return shown == total ? "\(total)" : "\(shown)/\(total)"
    }

    private var selectableModelsForDraft: [FetchedModel] {
        guard let id = draft.providerID,
              let provider = providers.first(where: { $0.id == id }) else { return [] }
        return selectableModels(for: provider)
    }

    private func modelPickerPlaceholder(for provider: Provider) -> String {
        hasFetchedModels(for: provider) ? "Pick a fetched model…" : "Fetch models first…"
    }

    private func canFetch(
        baseURL: String,
        apiKey: String,
        authScheme: ProviderAuthScheme,
        providerID: String = ""
    ) -> Bool {
        // The caller's real auth scheme must survive this reconstruction: omitting it
        // would apply the `.bearer` default and permanently disable "Test connection"
        // for keyless remote providers that explicitly chose `.none`.
        let provider = Provider(
            id: providerID,
            name: "",
            baseURL: baseURL,
            apiKey: apiKey,
            authScheme: authScheme
        )
        // Cline Pass uses the public recommended-models feed — no API key required.
        if provider.supportsLiveCatalogRefresh {
            return true
        }
        guard ProviderModelFetcher.modelsURL(for: baseURL) != nil else { return false }
        // Local servers accept no key; keyless (`.none`) providers never need one.
        if provider.isLocalEndpoint || provider.authScheme == .none { return true }
        return ProviderModelFetcher.resolveKey(apiKey: apiKey) != nil
    }

    // MARK: - Model actions

    private func beginNewModel(forProvider provider: Provider) {
        guard addModelDisabledReason(for: provider) == nil else { return }
        draft = CustomModel(
            id: "",
            model: "",
            baseURL: "",
            apiBackend: ProviderPreset.matching(provider: provider)?.defaultAPIBackend
                ?? .chatCompletions,
            providerID: provider.id
        )
        editingID = nil
        revealKey = false
        allowUnverifiedCustomModel = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    /// Opens the model editor for a brand-new manual model (no provider preselected).
    private func beginNewModel() {
        draft = freshModelDraft()
        editingID = nil
        revealKey = false
        allowUnverifiedCustomModel = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    private func beginEditing(_ model: CustomModel) {
        draft = model
        editingID = model.id
        revealKey = false
        allowUnverifiedCustomModel = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    private func resetDraft() {
        draft = freshModelDraft()
        editingID = nil
        revealKey = false
        allowUnverifiedCustomModel = false
        showingModelEditor = false
    }

    /// A blank model draft that defaults to the first provider (if any) so the endpoint is
    /// inherited and the manual base_url/key fields stay hidden. Prefills the provider's
    /// suggested starting model.
    private func freshModelDraft() -> CustomModel {
        if let provider = providers.first {
            return CustomModel(
                id: "",
                model: "",
                baseURL: "",
                apiBackend: ProviderPreset.matching(provider: provider)?.defaultAPIBackend
                    ?? .chatCompletions,
                providerID: provider.id
            )
        }
        return CustomModel(id: "", model: "", baseURL: "")
    }

    /// The provider currently linked to the model draft, if any.
    private var draftProvider: Provider? {
        guard let id = draft.providerID else { return nil }
        return providers.first { $0.id == id }
    }

    /// Catalog `owned_by` values that identify an account tier, not a model name.
    static let genericCatalogOwnerLabels: Set<String> = [
        "system", "openai", "openai-internal", "organization-owner"
    ]

    private var modelIDPlaceholder: String {
        let trimmed = draft.model.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return CustomModel.suggestedID(from: trimmed)
        }
        return "my-model-id"
    }

    private var modelNamePlaceholder: String {
        if draftProvider != nil {
            return "Pick a model above"
        }
        return "provider-model-name"
    }

    private var displayNamePlaceholder: String {
        let trimmed = draft.model.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return "\(trimmed) (optional)"
        }
        return "Display name (optional)"
    }

    private func saveDraft() {
        guard draftSaveBlockedReason == nil else { return }
        let changedModelIDs = Set([draft.id] + (editingID.map { [$0] } ?? []))
        var updated = models
        if let editingID, let index = updated.firstIndex(where: { $0.id == editingID }) {
            updated[index] = draft
        } else {
            updated.append(draft)
        }
        guard persist(
            models: updated,
            providers: providers,
            defaultModelID: persistedDefaultModelIDForConfig,
            change: .models(changedModelIDs)
        ) else {
            return
        }
        models = updated
        resetDraft()
    }

    private func remove(_ model: CustomModel) {
        guard canWriteModelConfiguration else {
            errorMessage = modelConfigWriteBlockReason
            return
        }
        let removal = CustomModelStore.removalPlan(
            removing: model.id,
            from: models,
            defaultModelID: persistedDefaultModelIDForConfig
        )
        guard persist(
            models: removal.models,
            providers: providers,
            defaultModelID: removal.defaultModelID,
            change: .models([model.id])
        ) else {
            return
        }
        models = removal.models
        if removal.defaultModelID == nil, persistedDefaultModelIDForConfig == model.id {
            valueState.reconcilePersisted(
                "",
                preservingDraft: defaultModelID == model.id ? nil : defaultModelID
            )
        }
        if editingID == model.id { resetDraft() }
    }

    @discardableResult
    private func persist(
        models candidateModels: [CustomModel],
        providers candidateProviders: [Provider],
        defaultModelID candidateDefaultModelID: String?,
        change: ConfigurationChange
    ) -> Bool {
        guard canWriteModelConfiguration else {
            errorMessage = modelConfigWriteBlockReason
            statusMessage = nil
            return false
        }
        do {
            let resolvedModels = candidateModels.map { $0.resolved(using: candidateProviders) }
            try CustomModelStore.save(
                models: resolvedModels,
                defaultModelID: candidateDefaultModelID,
                providers: candidateProviders
            )
            recordConfigurationPersistenceSuccess(change: change)
            return true
        } catch {
            errorMessage = "Failed to save config.toml: \(error.localizedDescription)"
            statusMessage = nil
            return false
        }
    }

    private var persistedDefaultModelIDForConfig: String? {
        let selected = valueState.persisted.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? nil : selected
    }

    private func recordConfigurationPersistenceSuccess(change: ConfigurationChange) {
        statusMessage = "Saved to ~/.grok/config.toml."
        errorMessage = nil
        onConfigurationChanged(change)
    }

    @MainActor
    private func applyDefaultModel() async {
        guard valueState.canApply, canWriteModelConfiguration else {
            errorMessage = modelConfigWriteBlockReason
            return
        }
        let selectedDefault = valueState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CustomModelStore.save(
                models: models.map { $0.resolved(using: providers) },
                defaultModelID: selectedDefault.isEmpty ? nil : selectedDefault,
                providers: providers
            )
            let request = SettingsApplyRequest(
                configurationGeneration: valueState.configurationGeneration + 1,
                capability: .models,
                persistenceOwner: .grokConfig,
                applyScope: .futureSessions,
                requiresProcessRestart: false,
                redactedSummary: "Saved the default model for future inherited tabs."
            )
            valueState.recordSaved(
                applied: selectedDefault,
                requiresRestart: false,
                receipt: request.receipt
            )
            let receipt = await onApply(request)
            guard !Task.isCancelled else { return }
            valueState.complete(
                receipt: receipt,
                live: liveReceipt?.freshness == .live ? liveReceipt?.requestedModelID : nil
            )
            statusMessage = "Saved default model for future inherited tabs."
            errorMessage = nil
            onConfigurationChanged(.defaultModel)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Card / row helpers

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .settingsSectionSurface()
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
