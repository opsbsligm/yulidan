import Foundation
@testable import HarnessApp
import Testing
import Tools

// MARK: - AppViewModel 工具面板（场景测试：executeTool 真实执行 / 参数容错 / 沙箱根切换端到端）

@MainActor
@Suite("AppViewModel 工具面板", .serialized)
struct AppViewModelToolPanelTests {
    init() {
        // 只重置通知工厂；provider 不触碰（本 suite 不驱动 LLM 生成）
        AppViewModel.notificationServiceFactory = { NoopNotificationService() }
    }

    private func tempDBURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-toolpanel-test-\(UUID().uuidString).sqlite")
    }

    private func tempDir(_ name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-toolpanel-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 轮询等待启动工具注册完成、指定工具出现在展示列表
    private func waitForTool(_ vm: AppViewModel, _ name: String, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if vm.tools.contains(where: { $0.name == name }) {
                return true
            }
            await vm.refreshTools()
            try? await Task.sleep(for: .milliseconds(50))
        }
        return vm.tools.contains(where: { $0.name == name })
    }

    /// 通过工具面板执行 read_file，等待执行完成并返回展示结果
    private func runRead(_ path: String, vm: AppViewModel) async -> String? {
        guard let idx = vm.tools.firstIndex(where: { $0.name == "read_file" }) else { return nil }
        vm.executeTool(at: idx, withParams: #"{"path":"\#(path)"}"#)
        // 25s 上限：吸收 macOS 协作池瞬态调度停滞（~10-13s，QUALITY_REPORT P1 环境类）；
        // 停滞期间完成态/重注册不派发，10s 上限会误报超时（2026-08-21 并发全量门禁首轮实测 3 断言超时）
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if !vm.tools[idx].executing {
                return vm.tools[idx].lastResult
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return vm.tools[idx].lastResult
    }

    // MARK: 场景 1：executeTool 真实执行 + 结果回显 + 清除

    @Test("executeTool：注册工具 → 面板执行 → 真实工具调用 → 结果回显 → 清除")
    func executeToolRealExecution() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempDir("skills")
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        let tool = EchoTool() // 复用既有测试桩（AppViewModelToolLoopTests）
        await vm.toolRegistry.register(tool)
        #expect(await waitForTool(vm, "echo_tool"))

        guard let idx = vm.tools.firstIndex(where: { $0.name == "echo_tool" }) else {
            Issue.record("echo_tool 不在展示列表"); return
        }
        vm.executeTool(at: idx, withParams: #"{"text":"ping"}"#)
        #expect(vm.tools[idx].executing) // 执行中状态立即置位

        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline, vm.tools[idx].executing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        // 完成态按身份（echo_tool）定位断言：并发 refreshTools() 可能重排数组，裸 index 不可靠
        let doneDeadline = Date().addingTimeInterval(25)
        while Date() < doneDeadline {
            guard let i = vm.tools.firstIndex(where: { $0.id == "echo_tool" }) else { break }
            if !vm.tools[i].executing {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let i = vm.tools.firstIndex(where: { $0.id == "echo_tool" }) else {
            Issue.record("echo_tool 不在展示列表"); return
        }
        #expect(vm.tools[i].executing == false)
        #expect(vm.tools[i].isExecuted == true)
        #expect(vm.tools[i].lastResult == "echo: ping")
        #expect(tool.executionCount == 1) // 真实工具执行一次

        // 清除结果：复位未执行状态
        vm.clearToolResult(at: i)
        #expect(vm.tools[i].isExecuted == false)
        #expect(vm.tools[i].lastResult == nil)
        #expect(vm.tools[i].executing == false)
    }

    // MARK: 场景 2：越界 index no-op

    @Test("executeTool 越界 index：guard 拦截，展示列表不变不崩溃")
    func executeToolOutOfRangeNoop() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempDir("skills")
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        let tool = EchoTool()
        await vm.toolRegistry.register(tool)
        #expect(await waitForTool(vm, "echo_tool"))

        let before = vm.tools
        vm.executeTool(at: 9999, withParams: "{}")
        #expect(vm.tools == before)
        #expect(tool.executionCount == 0)
    }

    // MARK: 场景 3：参数解析容错（纯函数）

    @Test("parseParams 容错：JSON 对象 / 数值转字符串 / 非 JSON 整体作 cmd / 空串")
    func parseParamsTolerance() {
        let json = AppViewModel.parseParams(#"{"a":"x","n":2,"f":true}"#)
        #expect(json == ["a": "x", "n": "2", "f": "1"])
        #expect(AppViewModel.parseParams("plain command --flag") == ["cmd": "plain command --flag"])
        #expect(AppViewModel.parseParams("") == [:])
        #expect(AppViewModel.parseParams("   ") == [:])
    }

    // MARK: 场景 4：缺参错误回显

    @Test("executeTool 缺参：工具返回错误文本回显到面板")
    func executeToolMissingParamError() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempDir("skills")
        defer { try? FileManager.default.removeItem(at: skillDir) }
        // 无沙箱启动（测试开始已清 sandboxRoot，见场景 4 的隔离约定）
        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        #expect(await waitForTool(vm, "read_file"))

        guard let idx = vm.tools.firstIndex(where: { $0.name == "read_file" }) else {
            Issue.record("read_file 不在展示列表"); return
        }
        vm.executeTool(at: idx, withParams: "{}")
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline, vm.tools[idx].executing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(vm.tools[idx].lastResult?.contains("错误：缺少参数 path") == true)
    }

    // MARK: 场景 5：沙箱根切换端到端（内置工具重注册立即生效）

    @Test("沙箱根切换：越界拒绝 / 范围内放行 / 恢复 nil 后放行（重注册即时生效）")
    func sandboxRootSwitchScenario() async throws {
        // UserDefaults 沙箱设置是全局的：保存当前值，结束恢复（防跨 run/跨 suite 串扰）
        let prevRoot = UserDefaults.standard.string(forKey: "sandboxRoot")
        UserDefaults.standard.removeObject(forKey: "sandboxRoot")
        defer {
            if let prevRoot {
                UserDefaults.standard.set(prevRoot, forKey: "sandboxRoot")
            } else {
                UserDefaults.standard.removeObject(forKey: "sandboxRoot")
            }
        }

        let root = tempDir("sandbox-root")
        defer { try? FileManager.default.removeItem(at: root) }
        let outsideDir = tempDir("outside")
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        let inRoot = root.appendingPathComponent("in.txt")
        let outside = outsideDir.appendingPathComponent("out.txt")
        try "hello-sandbox".write(toFile: inRoot.path, atomically: true, encoding: .utf8)
        try "outside-content".write(toFile: outside.path, atomically: true, encoding: .utf8)

        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempDir("skills")
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        #expect(await waitForTool(vm, "read_file"))

        // 1. 初始无沙箱：范围外文件可读
        let r0 = await runRead(outside.path, vm: vm)
        #expect(r0?.contains("✅ 已读取") == true)

        // 2. 设置沙箱根 → 内置工具重注册，read_file 携带沙箱
        vm.setSandboxRoot(root.path)
        let d1 = Date().addingTimeInterval(25)
        while Date() < d1 {
            let t = await vm.toolRegistry.tool(named: "read_file") as? ReadFileTool
            if t?.sandbox != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let active = await vm.toolRegistry.tool(named: "read_file") as? ReadFileTool
        #expect(active?.sandbox != nil)

        // 3. 越界路径被拒绝（outside_sandbox）
        let r1 = await runRead(outside.path, vm: vm)
        #expect(r1?.contains("❌ 路径超出沙箱允许范围") == true)
        // 4. 范围内路径放行
        let r2 = await runRead(inRoot.path, vm: vm)
        #expect(r2?.contains("hello-sandbox") == true)

        // 5. 恢复无沙箱：范围外再次可读
        vm.setSandboxRoot(nil)
        let d2 = Date().addingTimeInterval(25)
        while Date() < d2 {
            let t = await vm.toolRegistry.tool(named: "read_file") as? ReadFileTool
            if t?.sandbox == nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let r3 = await runRead(outside.path, vm: vm)
        #expect(r3?.contains("✅ 已读取") == true)
    }

    // MARK: 场景 6：并发回归 — 执行中展示数组被并发 refreshTools 重建，完成态按身份落对槽（串槽根因闭环）

    @Test("并发重建：完成态按身份落对槽，其他槽位不污染")
    func completionSurvivesConcurrentRebuild() async {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        let skillDir = tempDir("skills")
        defer { try? FileManager.default.removeItem(at: skillDir) }

        let vm = AppViewModel(skillUserDirectory: skillDir, sessionDBURL: dbURL)
        let tool = SlowEchoTool()
        await vm.toolRegistry.register(tool)
        #expect(await waitForTool(vm, "slow_echo"))

        guard let idx = vm.tools.firstIndex(where: { $0.name == "slow_echo" }) else {
            Issue.record("slow_echo 不在展示列表"); return
        }
        vm.executeTool(at: idx, withParams: #"{"text":"race"}"#)

        // 执行中（150ms 窗口内）反复重建展示数组（模拟 MCP list_changed / 启动发现 / 插件注册触发）
        for _ in 0 ..< 8 {
            await vm.refreshTools()
            try? await Task.sleep(for: .milliseconds(10))
        }

        // 完成态必须落在 slow_echo 槽（身份查找），而非过期下标
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            guard let i = vm.tools.firstIndex(where: { $0.id == "slow_echo" }) else { break }
            if vm.tools[i].isExecuted {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let i = vm.tools.firstIndex(where: { $0.id == "slow_echo" }) else {
            Issue.record("slow_echo 不在展示列表"); return
        }
        #expect(vm.tools[i].executing == false)
        #expect(vm.tools[i].isExecuted == true)
        #expect(vm.tools[i].lastResult == "slow: race")
        // 其他槽位不得残留完成态（串槽检测）
        #expect(vm.tools.allSatisfy { $0.lastResult == nil || $0.name == "slow_echo" })
    }
}

/// 慢回显工具：执行开始让出 150ms，制造“执行中展示数组被重建”的重叠窗口
final class SlowEchoTool: Tool, @unchecked Sendable {
    let name = "slow_echo"
    let description = "慢速回显（竞态测试用）"
    let parameterSchema = #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#

    func execute(_ args: [String: String], context _: ToolRunContext) async throws -> ToolResult {
        try await Task.sleep(for: .milliseconds(150))
        return ToolResult(content: [.text("slow: \(args["text"] ?? "")")])
    }
}
