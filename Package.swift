// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokBuild",
    platforms: [.macOS("26.0")],
    products: [
        .executable(
            name: "GrokBuild",
            targets: ["GrokBuild"]
        ),
        .executable(
            name: "GrokBuildComputerUseMCP",
            targets: ["GrokBuildComputerUseMCP"]
        ),
        .executable(
            name: "GrokBuildProviderAuthHelper",
            targets: ["GrokBuildProviderAuthHelper"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/mattt/swift-toml.git",
            revision: "827506c90475e82d5a7f191f950fb3025cbdc0d6"
        )
    ],
    targets: [
        // Pure Computer Use contract (tool table, argv mapping, policy, env
        // keys) shared by the app, the helper executable, and the tests —
        // executable targets cannot be imported by tests.
        .target(
            name: "GrokBuildComputerUseCore",
            path: "GrokBuildComputerUseCore"
        ),
        .target(
            name: "GrokBuildProviderAuthCore",
            path: "GrokBuildProviderAuthCore"
        ),
        .executableTarget(
            name: "GrokBuild",
            dependencies: [
                "GrokBuildComputerUseCore",
                "GrokBuildProviderAuthCore",
                .product(name: "TOML", package: "swift-toml"),
            ],
            path: "GrokBuild",
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Skills/grokbuild-browser-control"),
                .copy("Resources/Skills/grokbuild-computer-use"),
                .copy("Resources/Skills/grokbuild-grok-web"),
            ]
        ),
        .executableTarget(
            name: "GrokBuildComputerUseMCP",
            dependencies: ["GrokBuildComputerUseCore"],
            path: "GrokBuildComputerUseMCP"
        ),
        .executableTarget(
            name: "GrokBuildProviderAuthHelper",
            dependencies: ["GrokBuildProviderAuthCore"],
            path: "GrokBuildProviderAuthHelper"
        ),
        .testTarget(
            name: "GrokBuildTests",
            dependencies: ["GrokBuild", "GrokBuildComputerUseCore", "GrokBuildProviderAuthCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
