import Foundation
import PluginXPC
import Testing

// MARK: - 覆盖审计轮 17：PluginXPC 残余兜底行（ProcessCommandRunner 非 UTF-8 输出回退 / XPCPluginHost 默认 terminate thunk 创建）

/// 空命令运行器（仅验证 XPCPluginHost 装配不触网不触 launchd）
private struct NoopRunner: CommandRunner {
    func run(_: [String]) throws -> (exitCode: Int32, output: String) {
        (0, "")
    }
}

@Suite("PluginXPC R17 Gap Coverage")
struct PluginXPCR17GapTests {
    /// ① XPCPluginHost 省略 terminate 参数 → 默认参数闭包（SIGTERM thunk）被创建
    @Test("XPCPluginHost: 默认 terminate thunk 创建")
    func defaultTerminateThunkCreated() async {
        let host = XPCPluginHost(runner: NoopRunner())
        // 仅验证装配成功；不触发 connect/deregister（避免 launchd 副作用）
        let available = await host.isAvailable
        #expect(!available)
    }

    /// ② 非 UTF-8 子进程输出 → `String(data:encoding:.utf8) ?? ""` 兜底
    /// ⚠️ 参数必须经 shell printf 产出原始 0xFF 字节（Swift String 无法承载 0xFF 字面量）
    @Test("ProcessCommandRunner: 非 UTF-8 输出 → 空串兜底")
    func runnerNonUTF8Output() throws {
        let runner = ProcessCommandRunner()
        let (exitCode, output) = try runner.run(["/bin/sh", "-c", "printf '\\377\\376'"])
        #expect(exitCode == 0)
        #expect(output.isEmpty)
    }
}
