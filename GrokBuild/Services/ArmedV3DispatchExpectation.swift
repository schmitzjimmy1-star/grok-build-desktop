import Foundation

/// Credential-free dispatch bind for schema-3 armed launches.
///
/// Packet `credentialAuthorizationV3` selectors are necessary but not
/// sufficient. Swift independently observes the selected custom model and
/// linked provider, then binds Keychain account + scheme + expected digest
/// only when those observations match the frozen route. It does not invent
/// `configIdentity`, live endpoint SHA, or a provenance document.
struct ArmedV3DispatchExpectation: Equatable, Sendable {
    let campaignID: String
    let allocationID: String
    let selectedModelID: String
    let managedProviderID: String
    let providerFacingModel: String
    let authScheme: String
    let apiBackend: String
    let authBoundary: ModelRouteContract.AuthBoundary
    let candidate: GrokCandidateRuntimeIdentity
    let frozenRoute: AcceptanceHardBudgetRoute
    let credentialAuthorizationV3: GrokArmedCredentialAuthorizationV3

    static func tryMake(
        authorization: AcceptanceBudgetAuthorization,
        selectedModelID: String,
        customModel: CustomModel,
        provider: Provider,
        candidate: GrokCandidateRuntimeIdentity
    ) -> ArmedV3DispatchExpectation? {
        let route = authorization.budget.route
        let selected = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveModelID = customModel.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveProviderFacing = customModel.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveProviderID = customModel.providerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let packetProviderID = route.managedProviderID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let packetScheme = route.authScheme?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let packetModel = route.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty,
              selected == liveModelID,
              liveProviderID == provider.id,
              liveProviderID == packetProviderID,
              packetModel == liveProviderFacing,
              route.apiBackend == customModel.apiBackend.rawValue,
              let liveScheme = provider.authScheme.armedV3CanonicalScheme,
              liveScheme == packetScheme,
              candidate.cliBuild == authorization.expectedCLIBuild,
              let packetAuthorization = route.credentialAuthorizationV3,
              packetAuthorization.managedProviderID == liveProviderID,
              packetAuthorization.authScheme == liveScheme,
              packetAuthorization.expectedProvenanceSHA256 == route.boundProvenanceSHA256
        else {
            return nil
        }
        if let attached = authorization.credentialAuthorizationV3,
           attached != packetAuthorization {
            return nil
        }
        let routeContract = ModelRouteContract.resolve(
            selectedModelID: selected,
            customModel: customModel,
            isKnownNativeModel: false
        )
        guard routeContract.authBoundary == .officialHelper else { return nil }
        return ArmedV3DispatchExpectation(
            campaignID: authorization.runID,
            allocationID: authorization.budget.allocationID,
            selectedModelID: selected,
            managedProviderID: liveProviderID,
            providerFacingModel: liveProviderFacing,
            authScheme: liveScheme,
            apiBackend: route.apiBackend,
            authBoundary: routeContract.authBoundary,
            candidate: candidate,
            frozenRoute: route,
            credentialAuthorizationV3: packetAuthorization
        )
    }

    /// Resolves the live custom-model snapshot and linked provider, then binds.
    static func bind(
        authorization: AcceptanceBudgetAuthorization,
        selectedModelID: String,
        customModelSnapshot: CustomModelStore.Snapshot,
        providers: [Provider],
        candidate: GrokCandidateRuntimeIdentity
    ) -> ArmedV3DispatchExpectation? {
        let customModel = CustomModelStore.runtimeEligibleModels(from: customModelSnapshot)
            .first { $0.id == selectedModelID }
        guard let customModel,
              let providerID = customModel.providerID,
              let provider = providers.first(where: { $0.id == providerID }) else {
            return nil
        }
        return tryMake(
            authorization: authorization,
            selectedModelID: selectedModelID,
            customModel: customModel,
            provider: provider,
            candidate: candidate
        )
    }

    static func bindAuthorization(
        authorization: AcceptanceBudgetAuthorization,
        selectedModelID: String,
        customModelSnapshot: CustomModelStore.Snapshot,
        providers: [Provider],
        candidate: GrokCandidateRuntimeIdentity
    ) -> GrokArmedCredentialAuthorizationV3? {
        bind(
            authorization: authorization,
            selectedModelID: selectedModelID,
            customModelSnapshot: customModelSnapshot,
            providers: providers,
            candidate: candidate
        )?.credentialAuthorizationV3
    }

    /// CLI-produced nested `v3Authority` must match Swift-observable identity.
    /// This does not invent `configIdentity` or live serializer bounds.
    func admitsInitializeMetadata(_ value: Any?) -> Bool {
        guard let provenance = HardBudgetProvenanceV3.ExecutionCapability.parseInitializeProvenance(value) else {
            return false
        }
        return provenance.campaignID == campaignID
            && provenance.allocationID == allocationID
            && provenance.candidate.cliBuild == candidate.cliBuild
            && provenance.candidate.binarySHA256 == candidate.binarySHA256
            && provenance.candidate.sourceCommitSHA == candidate.sourceSHA
            && provenance.route.providerID == managedProviderID
            && provenance.route.authScheme == authScheme
            && provenance.route.providerFacingModel == providerFacingModel
            && provenance.route.endpointSHA256 == frozenRoute.endpointSHA256
            && provenance.route.apiBackend == apiBackend
            && provenance.configIdentity.managedProviderID == managedProviderID
    }

    func spawnAdmissionRefusal(options: GrokLaunchOptions) -> String? {
        let mcpNames = Set(options.mcpServers.map(\.name)).union(options.allowedMCPServerNames)
        guard options.model == selectedModelID,
              authBoundary == .officialHelper,
              !options.mcpGatewayEnabled,
              mcpNames.isEmpty else {
            return "Acceptance route changed after authorization. No Grok process was launched."
        }
        return nil
    }
}
