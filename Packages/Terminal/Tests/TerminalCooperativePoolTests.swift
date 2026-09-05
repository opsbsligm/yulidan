import Foundation
import Terminal
import Testing

// MARK: - D-17 判别器：终端阻塞体不得占死调用方的 Swift 协作线程

//
// 存在理由（D-17，09-06）：`TerminalRunner.run` 原把「`pollUntilExit` 的 50ms `Thread.sleep`
// 轮询 + `process.waitUntilExit()` + `group.wait()`」三处**同步等待**直接跑在调用方所在的
// Swift 协作线程池上 ⇒ 每条终端命令从发起一直占住一条协作线程到命令结束。协作线程数
// == activeProcessorCount，故并发终端工具（母 Agent 并行派发子任务、多会话同时执行命令）
// 会占满该池，同进程其它 async 工作随之停摆。改法＝阻塞体整体投 `Thread.detachNewThread`。
//
// ⚠️ 判据选型经过一次自我否证（务必按此口径理解本文件，勿改回墙钟）：
//   第一版判据是「并发 cores+8 条 `sleep 0.4` 的墙钟 < 串行下界」。它在开发态很灵
//   （原实现实测 1.045s vs 下界 0.800s ⇒ 红；改后 0.534s ⇒ 绿），但同一用例在
//   `main` 门禁（Release + 覆盖率插桩 + 795 测试并行）下测得 0.814s，**压过 0.800s 阈值假红**。
//   放宽阈值不可行——原实现的变异值 1.045s 离阈值太近，放宽即失去判别力。
//   ⇒ 改用**线程同一性**判据：它测的是「阻塞体跑在哪条线程」这一结构事实，与机器负载无关。

/// 线程同一性判据要求判据与被测实现同步落地，故用最小锁盒记录一次观测值。
private final class ProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: (blocking: ObjectIdentifier, caller: ObjectIdentifier)?

    func record(blocking: ObjectIdentifier, caller: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        if recorded == nil {
            recorded = (blocking, caller)
        }
    }

    var value: (blocking: ObjectIdentifier, caller: ObjectIdentifier)? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

@Test("终端阻塞体不得跑在调用方线程上（线程同一性判据，与负载无关）")
func blockingBodyDoesNotRunOnCallerThread() async throws {
    let box = ProbeBox()
    let runner = TerminalRunner(
        configuration: TerminalConfiguration(timeout: 20),
        runThreadProbe: { blockingID, callerID in
            box.record(blocking: blockingID, caller: callerID)
        }
    )

    let result = try await runner.run("printf ok")
    // 缝空转就会让下面的判据失去意义 ⇒ 先证明这条命令真的跑完并捕获到输出
    #expect(
        result.terminationStatus == 0 && result.stdout == "ok" && !result.timedOut && !result.cancelled,
        "命令未正常完成（status=\(result.terminationStatus) stdout=\(result.stdout.prefix(20))），线程判据无效"
    )

    guard let seen = box.value else {
        Issue.record("探针未被调用：缝已失效，本用例无法判别（等同判别器失效，不得视为通过）")
        return
    }
    #expect(
        seen.blocking != seen.caller,
        """
        阻塞体与调用方在同一条线程（\(seen.blocking)）：\
        50ms 轮询 + waitUntilExit + group.wait 仍在调用方的 Swift 协作线程上执行，\
        每条终端命令都会把一条协作线程占死到命令结束（D-17 未修）
        """
    )
}

@Test("并发终端命令全部成功（功能面护栏：换线程不得改变执行语义）")
func concurrentRunsAllSucceed() async {
    let count = max(1, ProcessInfo.processInfo.activeProcessorCount) + 8
    let runner = TerminalRunner(configuration: TerminalConfiguration(timeout: 20))

    let results: [Int32] = await withTaskGroup(of: Int32.self) { group in
        for index in 0 ..< count {
            group.addTask {
                do {
                    let result = try await runner.run("printf r\(index)")
                    return result.stdout == "r\(index)" ? result.terminationStatus : -999
                } catch {
                    return -998
                }
            }
        }
        var codes: [Int32] = []
        for await code in group {
            codes.append(code)
        }
        return codes
    }

    #expect(results.count == count, "应收敛 \(count) 条结果，实际 \(results.count)")
    #expect(results.allSatisfy { $0 == 0 }, "存在未成功的命令（各自 stdout 须与自身序号一致）：\(results)")
}
