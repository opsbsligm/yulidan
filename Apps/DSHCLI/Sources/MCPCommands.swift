import ArgumentParser
import Foundation
import MCP

// MARK: - dsh mcp（服务发现与诊断）

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP servers (discovery / diagnostics)",
        subcommands: [MCPListCommand.self]
    )
}

struct MCPListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Discover MCP servers declared in ~/.harness/mcp/servers.json"
    )

    @Flag(name: .shortAndLong, help: "Only list configs without probing servers")
    var noProbe: Bool = false

    func run() async throws {
        let configs = MCPDiscovery.loadConfigs()
        if configs.isEmpty {
            print("无 MCP 服务器配置。")
            print("配置文件：\(MCPDiscovery.defaultURL.path)")
            print("格式：{\"servers\": [{\"name\": \"demo\", \"command\": \"/usr/bin/env\", \"arguments\": [\"python3\", \"server.py\"]}]}")
            return
        }
        let results: [MCPServer]
        if noProbe {
            results = configs.map { MCPServer(name: $0.name, transport: "stdio", isAvailable: true) }
        } else {
            print("探测中（启动 + 握手 + 工具清单）…")
            results = await MCPDiscovery.discover(configs: configs)
        }
        for server in results {
            let status = server.isAvailable ? "✅" : "❌"
            let count = server.toolCount.map { " \($0) 个工具" } ?? ""
            let info = server.serverInfo.map { "（\($0)）" } ?? ""
            print("\(status) \(server.name)\(count)\(info)")
        }
    }
}
