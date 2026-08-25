import Foundation
import Terminal
import Testing

// MARK: - Terminal 包薄弱分支覆盖（覆盖审计轮 12）

/// 可中途翻转的取消信号（轮询循环内取消路径）
final class FlippingSignal: TerminalCancellationToken, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool {
        lock.withLock { _cancelled }
    }

    func cancel() {
        lock.withLock { _cancelled = true }
    }
}

@Suite("Terminal Gap Coverage")
struct TerminalGapCoverageTests {
    /// ① TerminalError.launchFailed 的 CustomStringConvertible description
    @Test("TerminalError.launchFailed：description 文案「终端启动失败：<reason>」")
    func launchFailedDescription() {
        let err = TerminalError.launchFailed("shell 路径不存在")
        #expect(err.description == "终端启动失败：shell 路径不存在")
    }

    /// ② 执行中取消：轮询循环检测到信号 → terminate（pollUntilExit 取消分支）
    ///    + 结果 cancelled=true + displayString 追加「（已取消）」
    @Test("执行中取消：轮询循环取消分支 + displayString「（已取消）」注记")
    func cancelMidFlight() async throws {
        let signal = FlippingSignal()
        let runner = TerminalRunner(configuration: TerminalConfiguration(timeout: 10))
        let task = Task { try await runner.run("sleep 30", signal: signal) }
        try await Task.sleep(for: .seconds(0.3))
        signal.cancel()
        let r = try await task.value
        #expect(r.cancelled)
        #expect(!r.timedOut)
        let display = r.displayString(maxCharacters: 200)
        #expect(display.contains("（已取消）"))
        #expect(!display.contains("超时被终止"))
    }

    /// ③ decode lossy 兜底：非法 UTF-8 字节流 → String(decoding:)（不抛错、输出保留）
    @Test("非 UTF-8 输出：lossy 解码兜底（不抛错、输出保留）")
    func nonUtf8LossyDecode() async throws {
        let runner = TerminalRunner()
        let r = try await runner.run("printf '\\xff\\xfe\\xfd'")
        #expect(r.terminationStatus == 0)
        #expect(!r.stdout.isEmpty)
        #expect(r.displayString(maxCharacters: 200).contains("退出码 0"))
    }
}
