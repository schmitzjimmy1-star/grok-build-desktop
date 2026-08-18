import Darwin
import Foundation
import GrokBuildProviderAuthCore

do {
    let providerID = try ProviderAuthHelperContract.providerID(arguments: CommandLine.arguments)
    let reader = KeychainProviderCredentialReader()
    let credential = try ProviderAuthHelperContract.loadCredential(providerID: providerID) {
        try reader.credential(for: $0)
    }
    FileHandle.standardOutput.write(Data((credential + "\n").utf8))
    exit(EXIT_SUCCESS)
} catch {
    FileHandle.standardError.write(Data("Provider credential unavailable.\n".utf8))
    exit(EXIT_FAILURE)
}
