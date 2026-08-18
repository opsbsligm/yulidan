import Foundation

// MARK: - 服务发现

/// MCP 服务器服务发现
///
/// 配置源：`~/.harness/mcp/servers.json`（`{"servers": [MCPServerConfig]}`），
/// 探测：逐个启动 stdio 服务器完成 initialize 握手 + tools/list，报告可用性与工具数。
public enum MCPDiscovery {
    /// 默认配置文件：~/.harness/mcp/servers.json
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".harness")
            .appendingPathComponent("mcp")
            .appendingPathComponent("servers.json")
    }

    private struct ConfigFile: Codable {
        let servers: [MCPServerConfig]
    }

    /// 读取服务器配置（文件缺失/损坏 → 空数组）
    public static func loadConfigs(url: URL = defaultURL) -> [MCPServerConfig] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode(ConfigFile.self, from: data))?.servers ?? []
    }

    /// 保存服务器配置（自动创建目录；原子写入）
    @discardableResult
    public static func save(_ configs: [MCPServerConfig], url: URL = defaultURL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(ConfigFile(servers: configs))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 探测单个服务器配置：启动 + 握手 + 工具清单；成功 → isAvailable + toolCount + serverInfo
    @discardableResult
    public static func probe(_ config: MCPServerConfig, startupTimeout: TimeInterval = 5) async -> MCPServer {
        let client = StdioMCPClient(name: config.name, configuration: StdioMCPConfiguration(
            command: config.command,
            arguments: config.arguments,
            environment: config.environment,
            workingDirectory: config.workingDirectory,
            startupTimeout: startupTimeout
        ))
        do {
            let specs = try await client.listTools()
            var descriptor = MCPServer(name: config.name, transport: "stdio",
                                       isAvailable: true, toolCount: specs.count)
            if let caps = await client.capabilities() {
                descriptor.serverInfo = "\(caps.serverName)@\(caps.serverVersion)"
            }
            await client.stop()
            return descriptor
        } catch {
            await client.stop()
            return MCPServer(name: config.name, transport: "stdio", isAvailable: false)
        }
    }

    /// 批量探测（串行；本地 stdio 场景足够）
    public static func discover(configs: [MCPServerConfig] = loadConfigs()) async -> [MCPServer] {
        var results: [MCPServer] = []
        for config in configs {
            await results.append(probe(config))
        }
        return results
    }
}
