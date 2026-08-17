import Foundation
import Observation

/// Runs pure file/config parsing away from the main actor. The operation must return a
/// Sendable value so the UI receives a complete snapshot rather than sharing mutable parser
/// state across actors.
enum GrokBuildBackgroundWork {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value,
        priority: TaskPriority = .userInitiated
    ) async -> Value {
        await Task.detached(priority: priority, operation: operation).value
    }

    static func runThrowing<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value,
        priority: TaskPriority = .userInitiated
    ) async throws -> Value {
        try await Task.detached(priority: priority, operation: operation).value
    }
}

enum SettingsBackgroundLoader {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
        await GrokBuildBackgroundWork.run(operation)
    }

    static func runThrowing<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await GrokBuildBackgroundWork.runThrowing(operation)
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
    var modelConfigWriteSafety: CustomModelStore.WriteSafety = .writable
    var hasLoadedModelConfiguration = false
    var migrationIssues: [ProviderCredentialMigrationIssue] = []
    var validationResults: [String: ProviderValidationResult] = [:]
    var fetchedModels: [String: [FetchedModel]] = [:]
    var fetchingProviderID: String?
    var fetchErrorProviderID: String?
    var fetchErrorMessage: String?
    var grokAuthenticationState: GrokAuthenticationState = .checking
}
