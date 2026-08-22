@testable import Agent
import Foundation
import LLM
import Session
import Testing
import Tools

// MARK: - P2 ① 在途 LLM 调用联动取消（stopGenerating 中断真实请求，而非仅协调层释放）

//
// 背景：AgentLoop.cancel 原语义「在途 LLM 调用后台自行完成」——远程模型浪费一次请求配额，
// 且延迟响应曾进入 wire 历史。现改为 turn 入可取消 Task：cancel() 联动取消，
// 支持取消的 provider（全部 URLSession 适配器）立即中止请求；
// 不支持取消的 provider 其延迟响应被 runTurn 丢弃（不进 wire 历史、不作最终回答、不产错误消息）。

/// 支持取消的 provider：request 睡眠 8s，被 Task 取消时抛错（模拟 URLSession 适配器）
private final class AwareSlowProvider: LLMProvider, @unchecked Sendable {
    let id = "aware-slow"
    let supportedModels = ["mock-model"]
    private let lock = NSLock()
    private var count = 0
    private var cancelled = false
    private var finishedFlag = false

    var requestCount: Int {
        lock.withLock { count }
    }

    var wasCancelled: Bool {
        lock.withLock { cancelled }
    }

    var finished: Bool {
        lock.withLock { finishedFlag }
    }

    func request(_: LLMRequest) async throws -> LLMResponse {
        lock.withLock { count += 1 }
        do {
            try await Task.sleep(for: .seconds(8))
            lock.withLock { finishedFlag = true }
            return LLMResponse(model: "mock-model", content: [.text("慢速回答")], finishReason: .stop)
        } catch {
            lock.withLock { cancelled = true }
            throw error
        }
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// 不支持取消的 provider：try? 吞掉取消（模拟忽略 Task 取消的第三方实现）
/// 第 1 次请求 0.8s 后返回「慢速回答」；第 2 次立即返回「done」
private final class UnawareSlowProvider: LLMProvider, @unchecked Sendable {
    let id = "unaware-slow"
    let supportedModels = ["mock-model"]
    private let lock = NSLock()
    private var count = 0
    private var finishedFlag = false
    private var histories: [[LLM.Message]] = []

    var requestCount: Int {
        lock.withLock { count }
    }

    var finished: Bool {
        lock.withLock { finishedFlag }
    }

    var capturedHistories: [[LLM.Message]] {
        lock.withLock { histories }
    }

    func request(_ req: LLMRequest) async throws -> LLMResponse {
        let idx: Int
        lock.withLock {
            count += 1
            histories.append(req.messages)
        }
        idx = lock.withLock { count - 1 }
        if idx == 0 {
            try? await Task.sleep(for: .seconds(0.8))
            lock.withLock { finishedFlag = true }
            return LLMResponse(model: "mock-model", content: [.text("慢速回答")], finishReason: .stop)
        }
        return LLMResponse(model: "mock-model", content: [.text("done")], finishReason: .stop)
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<LLM.StreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@Suite("AgentLoop 在途 LLM 调用联动取消", .serialized)
struct AgentInFlightCancellationTests {
    /// 等待条件成立（有界，防测试悬挂）
    private func waitFor(_ what: @Sendable () async -> Bool, seconds: Double = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await what() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await what()
    }

    /// 扁平化 wire 历史文本（断言用）
    private func historyText(_ messages: [LLM.Message]) -> String {
        messages.compactMap { msg -> String? in
            msg.content.compactMap { block in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.joined()
        }.joined(separator: "\n")
    }

    @Test("在途取消：支持取消的 provider 请求被立即中断，中性收敛（无错误消息/无最终回答）")
    func cancellationInterruptsAwareRequest() async {
        let llm = AwareSlowProvider()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: ToolRegistry(), model: "mock-model")
        await loop.followup(UserMessage(content: [.text("慢速问题")]))
        #expect(await waitFor { llm.requestCount >= 1 })

        await loop.cancel(keepInbox: false)
        #expect(await waitFor { await (loop.currentStatus) == .idle }, "turn 应收敛回 idle")

        // 在途请求被 Task 取消中断（未跑满 8s、未返回响应）
        #expect(llm.wasCancelled, "支持取消的 provider 应观测到 Task 取消")
        #expect(llm.finished == false, "慢速请求不应完成")
        let result = await loop.lastTurnResult
        #expect(result.error == nil, "取消路径不得产生错误消息")
        #expect(result.messages.isEmpty, "中断的请求不得产生最终回答")
    }

    @Test("在途取消：不支持取消的 provider 延迟响应被丢弃，不污染 wire 历史")
    func cancellationDiscardsDelayedResponse() async {
        let llm = UnawareSlowProvider()
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: ToolRegistry(), model: "mock-model")
        await loop.followup(UserMessage(content: [.text("慢速问题")]))
        #expect(await waitFor { llm.requestCount >= 1 })

        await loop.cancel(keepInbox: false)
        // provider 忽略取消 → turn 在其自身时长（0.8s）内收敛
        #expect(await waitFor { await (loop.currentStatus) == .idle }, "turn 应有限收敛")
        #expect(llm.finished, "不支持取消的 provider 调用确实完成")
        let first = await loop.lastTurnResult
        #expect(first.error == nil, "取消路径不得产生错误消息")
        #expect(first.messages.isEmpty, "延迟响应不得成为最终回答")

        // 第二 turn：wire 历史必须不含被丢弃的「慢速回答」
        await loop.followup(UserMessage(content: [.text("下一个问题")]))
        #expect(await waitFor { llm.requestCount >= 2 })
        #expect(await waitFor { await (loop.currentStatus) == .idle })
        #expect(llm.capturedHistories.count >= 2)
        let secondHist = historyText(llm.capturedHistories[1])
        #expect(!secondHist.contains("慢速回答"), "被丢弃的延迟响应不得进入 wire 历史")
        #expect(secondHist.contains("下一个问题"))
        let second = await loop.lastTurnResult
        #expect(second.messages.last.flatMap { m in
            m.content.compactMap { block in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.first
        } == "done", "取消后新 turn 应正常工作")
    }

    @Test("回归：无取消时正常 turn 不受 Task 化改造影响（最终回答完整交付）")
    func normalTurnUnaffected() async {
        let llm = ScriptedLLM(responses: [textResponse("done")])
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID(), llm: llm,
                             tools: ToolRegistry(), model: "mock-model")
        await loop.followup(UserMessage(content: [.text("直接回答")]))
        #expect(await waitFor { await (loop.currentStatus) == .idle && llm.callCount >= 1 })
        let result = await loop.lastTurnResult
        #expect(result.error == nil)
        #expect(result.messages.count == 1)
        #expect(result.messages.last.flatMap { m in
            m.content.compactMap { block in
                if case let .text(t) = block {
                    return t
                }
                return nil
            }.first
        } == "done")
    }
}
