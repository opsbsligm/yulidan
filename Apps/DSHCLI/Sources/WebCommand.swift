import Agent
import ArgumentParser
import Foundation
import LLM
import Prompt
import Tools
import WebUI

// MARK: - web（本地 HTTP 服务器 + 浏览器会话界面）

// MARK: - web（本地 HTTP 服务器 + 浏览器会话界面）

struct WebCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "web",
        abstract: "Start the local web UI (HTTP server + browser chat)",
        discussion: """
        启动本地 HTTP 服务器，浏览器打开后与 Agent 多轮对话（与 dsh run 相同的环境变量配置）。
        会话保存在进程内，Ctrl+C 停止后清空。
        """
    )

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 3080

    @Option(name: .shortAndLong, help: "Address to bind (default 127.0.0.1)")
    var host: String = "127.0.0.1"

    func run() async throws {
        let cfg = try DSHConfig.resolve()
        FileHandle.standardError.write(Data("[dsh] Web UI: \(cfg.baseURL.absoluteString) / \(cfg.model)\n".utf8))

        let llm = ProviderFactory.make(cfg)
        let promptEngine = await SharedPromptEngine.instance.get()
        var systemPrompt = cfg.systemPrompt
        if systemPrompt == nil {
            systemPrompt = try? await promptEngine.renderSystemPrompt(template: PromptEngine.agentTemplate, model: cfg.model)
        }
        let app = WebUIApp(config: WebUIApp.Config(
            llm: llm,
            toolFactory: { BuiltinTools.makeAll() },
            model: cfg.model,
            systemPrompt: systemPrompt,
            maxSteps: cfg.maxSteps
        ))
        guard port >= 1, port <= 65535 else {
            throw CLIError.configMissing("端口范围 1-65535")
        }
        let server = MiniHTTPServer(host: host, port: UInt16(port)) { request in
            await app.handle(request)
        }
        let boundPort = try await server.start()
        if server.fellBackToAnyInterface {
            print("⚠️ 无法绑定 \(host)（EADDRNOTAVAIL，环境限制），已回退到 0.0.0.0（局域网可达，请注意访问控制）")
        }
        let displayHost = host == "0.0.0.0" ? "127.0.0.1" : host
        print("鱼利丹 Web UI: http://\(displayHost):\(boundPort)")
        print("按 Ctrl+C 停止服务")

        await SignalGate.wait()
        await server.stop()
        print("已停止")
    }
}

/// 信号门：捕获 SIGINT/SIGTERM，唤醒等待方
private enum SignalGate {
    /// 全局信号标记（signal 处理器必须是 C 函数指针，不能捕获上下文）
    private static let gate = SignalFlag()

    static func wait() async {
        _ = signal(SIGINT) { _ in SignalGate.gate.set() }
        _ = signal(SIGTERM) { _ in SignalGate.gate.set() }
        while !gate.isSet {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

/// 线程安全的信号标记
private final class SignalFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSetFlag = false
    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSetFlag
    }

    func set() {
        lock.lock()
        isSetFlag = true
        lock.unlock()
    }
}
