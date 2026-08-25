import Foundation
import Session
import Testing
import Tools

// MARK: - Tools 包薄弱分支覆盖（覆盖审计轮 14）

/// 共享就绪标志：协议投递响应后置位，测试侧确认已进入字节迭代再取消
final class FetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _ready = false

    var isReady: Bool {
        lock.withLock { _ready }
    }

    func markReady() {
        lock.withLock { _ready = true }
    }

    func reset() {
        lock.withLock { _ready = false }
    }
}

private let fetchGate = FetchGate()

/// 沉默协议桩：返回 200 响应 + 1 字节后既不完成也不报错（下载流悬挂）
/// 配合执行任务取消 → 字节迭代抛 CancellationError（非 FetchError）
/// → download 内层 catch 重抛 FetchError.failed → execute 的 .failed 分支
private final class SilenceProtocol: URLProtocol {
    // URLProtocol 要求 class func（无法用 static override），行内豁免
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // ⚠️ 实测（探针实锤）：AsyncBytes 的 bytes(for:) 需收到可观数据量才返回 tuple（1 字节不触发）；
        // 256KB < maxBytes(512KB) 不会触发 tooLarge，之后流悬挂等待任务取消
        client?.urlProtocol(self, didLoad: Data(count: 256_000))
        fetchGate.markReady()
        // 不发送 didComplete / didFailWithError：流悬挂，等待任务取消
    }

    override func stopLoading() {}
}

@Suite("Tools Gap Coverage")
struct ToolsGapCoverageTests {
    /// web_fetch：下载进行中执行任务被取消 → 字节迭代抛错（非 FetchError）
    ///   → download 内层 catch 重抛 FetchError.failed → execute 的 .failed 分支回传 fetch_failed
    ///   （区别于 URLError 外层 catch / http / tooLarge / badResponse 分支；路径判定靠行转储）
    @Test("web_fetch：下载中任务取消 → CancellationError → FetchError.failed → fetch_failed 回传")
    func fetchCancelledMidStreamReturnsFailed() async throws {
        fetchGate.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SilenceProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let tool = WebFetchTool(session: session, timeout: 30)
        let context = ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
        let child = Task { try await tool.execute(["url": "http://silence.local/x"], context: context) }
        // 等待协议投递响应（确保 bytes(for:) 已返回、进入字节迭代），上限 3s
        let deadline = Date().addingTimeInterval(3)
        while !fetchGate.isReady, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(fetchGate.isReady)
        try await Task.sleep(for: .milliseconds(300)) // 迭代读完 256KB 并悬挂的余量
        child.cancel()
        let result = try await child.value
        #expect(result.error?.code == "fetch_failed")
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        #expect(text.hasPrefix("❌ 抓取失败"))
        // ⚠️ 消息体 = 底层取消错误的 localizedDescription，locale 相关（中文化环境实锤 "已取消"，
        // xcode 门禁实锤失败过一次）；分支路径判定一律以 llvm-cov 行转储为准（L299-300 / L351），不做 locale 锚定断言
    }
}
