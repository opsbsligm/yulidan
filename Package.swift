// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-harness",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HarnessCore", targets: ["HarnessCore"]),
        .executable(name: "dsh", targets: ["DSHCLI"]),
        .executable(name: "HarnessApp", targets: ["HarnessApp"]),
        .executable(name: "MemProbe", targets: ["MemProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        // Core
        .target(name: "ServiceContainer",
                dependencies: [.product(name: "Logging", package: "swift-log")],
                path: "Packages/ServiceContainer/Sources"),
        .testTarget(name: "ServiceContainerTests",
                    dependencies: ["ServiceContainer"],
                    path: "Packages/ServiceContainer/Tests"),

        .target(name: "Session",
                dependencies: ["ServiceContainer", .product(name: "GRDB", package: "GRDB.swift")],
                path: "Packages/Session/Sources"),
        .testTarget(name: "SessionTests",
                    dependencies: ["Session", "ServiceContainer"],
                    path: "Packages/Session/Tests"),

        .target(name: "LLM",
                dependencies: ["ServiceContainer"],
                path: "Packages/LLM/Sources"),
        .testTarget(name: "LLMTests",
                    dependencies: ["LLM"],
                    path: "Packages/LLM/Tests"),

        .target(name: "Tools",
                dependencies: ["ServiceContainer", "Session", "LLM", "Terminal", "Sandbox"],
                path: "Packages/Tools/Sources"),
        .testTarget(name: "ToolsTests",
                    dependencies: ["Tools", "ServiceContainer", "Session", "LLM", "Terminal", "Sandbox"],
                    path: "Packages/Tools/Tests"),

        .target(name: "Agent",
                dependencies: ["ServiceContainer", "Session", "LLM", "Tools"],
                path: "Packages/Agent/Sources"),
        .testTarget(name: "AgentTests",
                    dependencies: ["Agent", "Session", "LLM", "Tools"],
                    path: "Packages/Agent/Tests"),

        .target(name: "HarnessCore",
                dependencies: ["ServiceContainer", "Session", "LLM", "Tools", "Agent"],
                path: "Apps/HarnessCore/Sources"),

        .executableTarget(name: "DSHCLI",
                          dependencies: ["HarnessCore", "Agent", "LLM", "Tools", "ServiceContainer", "Session",
                                         .product(name: "ArgumentParser", package: "swift-argument-parser")],
                          path: "Apps/DSHCLI/Sources"),

        // 内存/性能探针
        .executableTarget(name: "MemProbe",
                          dependencies: ["ServiceContainer", "Session", "LLM", "Tools"],
                          path: "Apps/MemProbe/Sources"),

        // macOS App
        .executableTarget(name: "HarnessApp",
                          dependencies: ["HarnessCore", "ServiceContainer", "Session", "LLM", "Tools", "Agent",
                                         "MCP", "Terminal", "Sandbox"],
                          path: "Apps/HarnessApp/Sources"),

        // Extended
        .target(name: "Workspace",
                dependencies: ["ServiceContainer", "Session"],
                path: "Packages/Workspace/Sources"),
        .target(name: "Goal",
                dependencies: ["ServiceContainer", "Session"],
                path: "Packages/Goal/Sources"),
        .target(name: "Plan",
                dependencies: ["ServiceContainer", "Goal"],
                path: "Packages/Plan/Sources"),
        .target(name: "Skill",
                dependencies: ["ServiceContainer", "Tools"],
                path: "Packages/Skill/Sources"),
        .target(name: "MCP",
                dependencies: ["ServiceContainer", "Tools"],
                path: "Packages/MCP/Sources"),
        .testTarget(name: "MCPTests",
                    dependencies: ["MCP", "ServiceContainer", "Tools", "Session"],
                    path: "Packages/MCP/Tests"),
        .target(name: "Subagent",
                dependencies: ["ServiceContainer", "Agent"],
                path: "Packages/Subagent/Sources"),
        .target(name: "Sandbox",
                dependencies: ["ServiceContainer"],
                path: "Packages/Sandbox/Sources"),
        .testTarget(name: "SandboxTests",
                    dependencies: ["Sandbox"],
                    path: "Packages/Sandbox/Tests"),
        .target(name: "Terminal",
                dependencies: ["ServiceContainer"],
                path: "Packages/Terminal/Sources"),
        .testTarget(name: "TerminalTests",
                    dependencies: ["Terminal"],
                    path: "Packages/Terminal/Tests"),
    ]
)
