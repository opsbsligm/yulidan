import ArgumentParser
import Foundation
import MCP

// MARK: - dsh cordis（G4c：社区 Cordis 插件兼容，D-5=做）

// 设计：docs/G4C_SIDECAR_DESIGN.md。授权清单 S-4；sidecar=bridge 即 MCP server（S-3）；
// Node 本机发现 S-1；env 洗刷走 /usr/bin/env -i 白名单（不改 StdioMCPClient 达成）。

enum CordisPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var root: URL {
        // 测试缝（同 reduceTransparencyTestOverride 模式在册）：隔离环境验收专用
        if let override = ProcessInfo.processInfo.environment["DSH_CORDIS_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent(".harness/cordis", isDirectory: true)
    }

    static var envDir: URL {
        root.appendingPathComponent("env", isDirectory: true)
    }

    static var allowlist: URL {
        root.appendingPathComponent("allowlist.json")
    }

    static var bridgeDir: URL {
        // bridge 源放 env/bridge-src（非 node_modules）：npm install reify 会清
        // extraneous 包（09-04 实测教训）；node 解析自 bridge-src 向上即达 env/node_modules
        envDir.appendingPathComponent("bridge-src", isDirectory: true)
    }

    /// bridge 源目录：环境变量优先；本地开发经 #filePath 回源仓（发布分发=另行拍板，已登记）
    static func bridgeSource() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["DSH_CORDIS_BRIDGE_SRC"], FileManager.default.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let here = URL(fileURLWithPath: #filePath) // Apps/DSHCLI/Sources/CordisCommands.swift
        // file → Sources → DSHCLI → Apps → 仓库根（四层）
        let candidate = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tools/cordis-bridge", isDirectory: true)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw CLIError.message("cordis bridge 源未找到（设 DSH_CORDIS_BRIDGE_SRC 指向 tools/cordis-bridge）")
        }
        return candidate
    }

    static func nodePath() -> String? {
        for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return which("node")
    }

    static func npmPath() -> String? {
        for p in ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return which("npm")
    }
}

struct CordisAllowEntry: Codable, Sendable {
    var package: String
    var version: String
    var addedAt: String
    /// 授权声明（红线：必须显式知晓 JS=任意代码执行）
    var consent: String
}

enum CordisAllowlist {
    static let consentText = "I understand: community plugin JS runs in an isolated-process sidecar but equals arbitrary code execution (upstream README: sandbox is NOT a security boundary)."

    static func load() -> [CordisAllowEntry] {
        guard let data = try? Data(contentsOf: CordisPaths.allowlist) else { return [] }
        return (try? JSONDecoder().decode([CordisAllowEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [CordisAllowEntry]) throws {
        try FileManager.default.createDirectory(at: CordisPaths.root, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(entries).write(to: CordisPaths.allowlist)
    }
}

/// 子进程 helper：捕获 stdout/stderr，返回 (rc, out, err)
func cordisRun(_ launchPath: String, _ args: [String], cwd: URL? = nil, timeout: TimeInterval = 240) throws -> (Int32, String, String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args
    if let cwd {
        proc.currentDirectoryURL = cwd
    }
    let out = Pipe(), err = Pipe()
    proc.standardOutput = out
    proc.standardError = err
    try proc.run()
    // 先读到 EOF 再 wait，防管道缓冲死锁（教训在册：nextLine-持锁双线程）
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    let deadline = Date().addingTimeInterval(timeout)
    while proc.isRunning, Date() < deadline {
        usleep(50000)
    }
    if proc.isRunning {
        proc.terminate()
        throw CLIError.message("命令超时：\(String(args.prefix(3).joined(separator: " ")))")
    }
    let s = { (d: Data) in String(data: d, encoding: .utf8) ?? "" }
    return (proc.terminationStatus, s(outData), s(errData))
}

func which(_ binary: String) -> String? {
    guard let (rc, out, _) = try? cordisRun("/usr/bin/env", ["-i", "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "/usr/bin/which", binary]), rc == 0 else { return nil }
    let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return p.isEmpty ? nil : p
}

struct CordisCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cordis",
        abstract: "DSH community (Cordis) plugins via isolated sidecar (G4c)",
        subcommands: [CordisAddCommand.self, CordisListCommand.self, CordisRemoveCommand.self, CordisProbeCommand.self]
    )
}

struct CordisAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Authorize + install a community plugin (explicit opt-in, S-4)")
    @Argument(help: "npm package name, optional @version pin (e.g. dsh-web-search-zai@1.0.0)")
    var package: String
    @Flag(help: "Skip the interactive-style consent echo") var iUnderstood: Bool = false

    func run() async throws {
        guard CordisPaths.nodePath() != nil, let npm = CordisPaths.npmPath() else {
            throw CLIError.message("本机未找到 node/npm（S-1：不捆绑运行时，请安装 Node 后重试）")
        }
        guard iUnderstood else {
            print("授权声明：\(CordisAllowlist.consentText)")
            print("确认后追加 --i-understood 重试。")
            return
        }
        // 1) 确保 bridge 环境（复制源 + 一次性安装 bridge 依赖，钉版本走 lock）
        try ensureBridgeEnv(npm: npm)
        // 2) 安装插件进 env
        print("安装 \(package) → \(CordisPaths.envDir.path) …")
        let (rc, out, err) = try cordisRun(npm, ["install", package, "--prefix", CordisPaths.envDir.path, "--no-audit", "--no-fund", "--ignore-scripts", "--legacy-peer-deps"])
        if rc != 0 {
            throw CLIError.message("npm install 失败：\n\(err.prefix(1200))\n\(out.prefix(400))")
        }
        // peers 补装（09-04 实测教训：@deepseek-ai 生态 peer=硬依赖，--legacy-peer-deps
        // 语义跳过 peers 致装载 Cannot find package）——一级 peer 显式安装
        try installPeerClosure(npm: npm)
        // 3) 写授权清单
        var entries = CordisAllowlist.load()
        entries.removeAll { $0.package == package.components(separatedBy: "@").filter { !$0.isEmpty }.joined(separator: "@") || package.hasPrefix($0.package + "@") }
        let resolved = resolveInstalledVersion(package: package) ?? (package, "unknown")
        entries.append(CordisAllowEntry(package: resolved.name, version: resolved.version, addedAt: ISO8601DateFormatter().string(from: Date()), consent: CordisAllowlist.consentText))
        try CordisAllowlist.save(entries)
        print("✅ 已授权并安装：\(resolved.name)@\(resolved.version)")
        print("下一步：dsh cordis probe \(resolved.name) 查看其工具面。")
    }

    /// peer 依赖传递闭包安装（09-04 双轮实测：@deepseek-ai 生态 peer=硬依赖且
    /// 递归传递——dsh-web-search-zai→dsh-web→dsh-llm；--legacy-peer-deps 语义跳过 peers）
    private func installPeerClosure(npm: String) throws {
        var rounds = 0
        while rounds < 5 {
            rounds += 1
            let missing = missingPeerPackages()
            if missing.isEmpty {
                return
            }
            print("补装 peer（闭包第 \(rounds) 轮）：\(missing.joined(separator: " "))")
            let (rc, _, err) = try cordisRun(npm, ["install"] + missing + ["--prefix", CordisPaths.envDir.path, "--no-audit", "--no-fund", "--ignore-scripts", "--legacy-peer-deps"])
            if rc != 0 {
                print("⚠️ peer 补装失败（插件装载可能受限，probe 会如实报错）：\(err.prefix(400))")
                return
            }
        }
    }

    /// 扫描 env/node_modules 全部包的一级 peer 声明，返回未落地者（scoped 目录两层）
    private func missingPeerPackages() -> [String] {
        let fm = FileManager.default
        let nm = CordisPaths.envDir.appendingPathComponent("node_modules", isDirectory: true)
        guard let top = try? fm.contentsOfDirectory(atPath: nm.path) else { return [] }
        var pkgFiles: [String] = []
        for e in top where !e.hasPrefix(".") {
            if e.hasPrefix("@") {
                if let scoped = try? fm.contentsOfDirectory(atPath: nm.appendingPathComponent(e).path) {
                    for sub in scoped {
                        pkgFiles.append("\(e)/\(sub)")
                    }
                }
            } else {
                pkgFiles.append(e)
            }
        }
        var declared = Set<String>()
        for rel in pkgFiles {
            let url = nm.appendingPathComponent("\(rel)/package.json")
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let peers = obj["peerDependencies"] as? [String: String] else { continue }
            for name in peers.keys where !name.hasPrefix("react") {
                declared.insert(name)
            } // react 半=UI 注入面，已裁决不做
        }
        let installed = Set(pkgFiles)
        return declared.subtracting(installed).sorted()
    }

    private func ensureBridgeEnv(npm: String) throws {
        let fm = FileManager.default
        let src = try CordisPaths.bridgeSource()
        let bridgeJS = CordisPaths.bridgeDir.appendingPathComponent("bridge.js")
        if fm.fileExists(atPath: bridgeJS.path) {
            return
        }
        try fm.createDirectory(at: CordisPaths.envDir, withIntermediateDirectories: true)
        // 写 package.json（钉版本），npm install 拉 bridge 依赖进 env
        let pkg = src.appendingPathComponent("package.json")
        try fm.copyItem(at: pkg, to: CordisPaths.envDir.appendingPathComponent("package.json"))
        print("首次初始化 bridge 环境（npm install 钉版本依赖）…")
        let (rc, _, err) = try cordisRun(npm, ["install", "--prefix", CordisPaths.envDir.path, "--no-audit", "--no-fund", "--ignore-scripts", "--legacy-peer-deps"])
        if rc != 0 {
            throw CLIError.message("bridge 依赖安装失败：\(err.prefix(1200))")
        }
        // bridge.js/fixtures 进 env 的 node_modules 包目录
        let dest = CordisPaths.bridgeDir
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in ["bridge.js"] {
            let d = dest.appendingPathComponent(name)
            if fm.fileExists(atPath: d.path) {
                try fm.removeItem(at: d)
            }
            try fm.copyItem(at: src.appendingPathComponent(name), to: d)
        }
        let fixturesDest = dest.appendingPathComponent("fixtures", isDirectory: true)
        if !fm.fileExists(atPath: fixturesDest.path) {
            try fm.copyItem(at: src.appendingPathComponent("fixtures"), to: fixturesDest)
        }
    }

    private func resolveInstalledVersion(package: String) -> (name: String, version: String)? {
        let name = package.replacingOccurrences(of: #"@\d+\.\d+.*$"#, with: "", options: .regularExpression)
        let pkgJson = CordisPaths.envDir.appendingPathComponent("node_modules/\(name)/package.json")
        guard let data = try? Data(contentsOf: pkgJson),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["version"] as? String else { return nil }
        return (name, v)
    }
}

struct CordisListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List allowlisted community plugins")
    func run() async throws {
        let entries = CordisAllowlist.load()
        if entries.isEmpty {
            print("无已授权社区插件。清单：\(CordisPaths.allowlist.path)"); return
        }
        for e in entries {
            print("✅ \(e.package)@\(e.version)  (\(e.addedAt))")
        }
    }
}

struct CordisRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Revoke a community plugin from the allowlist")
    @Argument var package: String
    func run() async throws {
        var entries = CordisAllowlist.load()
        let before = entries.count
        entries.removeAll { $0.package == package || package.hasPrefix($0.package + "@") }
        try CordisAllowlist.save(entries)
        print(entries.count < before ? "✅ 已撤销授权：\(package)（node_modules 残留在 env 目录，purge 需手动）" : "未找到授权项：\(package)")
    }
}

/// 包名 → 入口 file URL（读已装 package.json 的 main；exports 映射超出本轮范围，
/// main 缺失时显式报错而非猜路径——铁律 1）。loader 解析锚=baseUrl（sandbox），裸名不可用（实测）。
func cordisResolveSpecifier(package: String) throws -> String {
    let name = package.replacingOccurrences(of: #"@\d+\.\d+.*$"#, with: "", options: .regularExpression)
    let pkgDir = CordisPaths.envDir.appendingPathComponent("node_modules/\(name)", isDirectory: true)
    let pkgJson = pkgDir.appendingPathComponent("package.json")
    guard let data = try? Data(contentsOf: pkgJson),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CLIError.message("未找到已装包 \(name)（先 dsh cordis add）")
    }
    let main = (obj["main"] as? String) ?? "index.js"
    let entry = pkgDir.appendingPathComponent(main)
    guard FileManager.default.fileExists(atPath: entry.path) else {
        throw CLIError.message("包 \(name) 入口缺失（main=\(main)）；exports-only 包本轮未支持，已登记")
    }
    return entry.absoluteString // file:// URL
}

struct CordisProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "probe", abstract: "Handshake the sidecar and list tools of an allowlisted plugin")
    @Argument var package: String

    func run() async throws {
        guard CordisAllowlist.load().contains(where: { $0.package == package || package.hasPrefix($0.package + "@") }) else {
            throw CLIError.message("未授权插件不可装载（S-4）。先：dsh cordis add \(package) --i-understood")
        }
        guard let node = CordisPaths.nodePath() else { throw CLIError.message("未找到 node（S-1）") }
        let bridge = CordisPaths.bridgeDir.appendingPathComponent("bridge.js")
        guard FileManager.default.fileExists(atPath: bridge.path) else { throw CLIError.message("bridge 环境未初始化（dsh cordis add 触发）") }
        let sandbox = CordisPaths.root.appendingPathComponent("sandbox", isDirectory: true)
        // loader 按 ctx.baseUrl（sandbox）解析裸包名（09-04 实测）→ 包名转 file URL
        let specifier = try cordisResolveSpecifier(package: package)
        // env 洗刷：/usr/bin/env -i 白名单（红线：不透传敏感 env）
        let config = StdioMCPConfiguration(
            command: "/usr/bin/env",
            arguments: ["-i", "HOME=\(CordisPaths.home.path)", "PATH=/usr/bin:/bin", node, bridge.path,
                        "--sandbox", sandbox.path, specifier],
            environment: [:],
            workingDirectory: CordisPaths.envDir.path
        )
        let client = StdioMCPClient(name: "cordis:\(package)", configuration: config)
        defer { Task { await client.stop() } }
        do {
            try await client.start()
        } catch {
            // 诊断透出：bridge stderr（bootstrap 失败原因等）——CLI 可运维性
            let stderr = await client.recentStderr
            throw CLIError.message("probe 失败：\(error)\nbridge stderr：\(stderr.suffix(1000))")
        }
        let tools = try await client.listTools()
        print("✅ 握手成功：\(package) 暴露 \(tools.count) 个工具")
        for t in tools {
            print("  • \(t.name): \(t.description.prefix(80))")
        }
    }
}
