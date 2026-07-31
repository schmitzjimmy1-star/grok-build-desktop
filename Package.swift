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
        )
    ],
    dependencies: [],
    targets: [
        // Pure Computer Use contract (tool table, argv mapping, policy, env
        // keys) shared by the app, the helper executable, and the tests —
        // executable targets cannot be imported by tests.
        .target(
            name: "GrokBuildComputerUseCore",
            path: "GrokBuildComputerUseCore"
        ),
        .executableTarget(
            name: "GrokBuild",
            dependencies: ["GrokBuildComputerUseCore"],
            path: "GrokBuild",
            exclude: ["GrokBuildApp.swift"], // We use AppKit entry point instead
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Skills/grokbuild-browser-control"),
                .copy("Resources/Skills/grokbuild-computer-use"),
                .copy("Resources/Skills/grokbuild-desktop"),
                .copy("Resources/Skills/grokbuild-grok-web"),
            ]
        ),
        .executableTarget(
            name: "GrokBuildComputerUseMCP",
            dependencies: ["GrokBuildComputerUseCore"],
            path: "GrokBuildComputerUseMCP"
        ),
        .testTarget(
            name: "GrokBuildTests",
            dependencies: ["GrokBuild", "GrokBuildComputerUseCore"]
        )
    ]
)
