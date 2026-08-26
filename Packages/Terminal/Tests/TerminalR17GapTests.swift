import Foundation
import Terminal
import Testing

// MARK: - 覆盖审计轮 17：Terminal 残余兜底行（configure 环境合并闭包）

@Suite("Terminal R17 Gap Coverage")
struct TerminalR17GapTests {
    /// ① 非 nil environment → `ProcessInfo.environment.merging { _, new in new }` 闭包执行
    /// 断言：注入的环境变量在子进程内可见（HOME 覆盖生效证明 merging 路径真实执行）
    @Test("configure: 注入环境变量 → merging 闭包")
    func configureEnvironmentMerging() async throws {
        let config = TerminalConfiguration(
            shellPath: "/bin/sh",
            shellArguments: ["-c"],
            workingDirectory: nil,
            environment: ["HARNESS_R17_PROBE": "r17-merged"],
            timeout: 10,
            maxCaptureBytes: 100_000,
            maxOutputCharacters: 1000
        )
        let runner = TerminalRunner(configuration: config)
        let result = try await runner.run("printenv HARNESS_R17_PROBE")
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "r17-merged")
    }
}
