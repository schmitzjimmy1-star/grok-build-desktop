import Foundation
import Observation

enum SettingsBackgroundLoader {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
        await Task.detached(priority: .userInitiated, operation: operation).value
    }

    static func runThrowing<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await Task.detached(priority: .userInitiated, operation: operation).value
    }
}

/// Persistent Models-pane state. The SwiftUI view owns editor presentation only; provider,
/// catalog, migration, and save state live here so tab navigation cannot silently reset them.
@Observable
@MainActor
final class CustomModelsSettingsViewModel {
    var providers: [Provider] = []
    var models: [CustomModel] = []
    var defaultModelID = ""
    var persistedDefaultModelID = ""
    var errorMessage: String?
    var statusMessage: String?
    var migrationIssues: [ProviderCredentialMigrationIssue] = []
    var validationResults: [String: ProviderValidationResult] = [:]
    var fetchedModels: [String: [FetchedModel]] = [:]
    var fetchingProviderID: String?
    var fetchErrorProviderID: String?
    var fetchErrorMessage: String?
}
