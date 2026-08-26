import Foundation
import Session
import Testing
import Tools

// MARK: - 覆盖审计轮 17：内置工具可选参数兜底 + WebFetch 非 UTF-8 + ToolRegistry 排序闭包

@Suite("Tools R17 Gap Coverage")
struct ToolsR17GapTests {
    private func context() -> ToolRunContext {
        ToolRunContext(signal: CancellationToken(), sessionID: SessionID(), metadata: [:])
    }

    /// ① write_file：缺 content 参数 → `args["content"] ?? ""` 兜底（空文件写入成功）
    @Test("write_file: 缺 content → 空串兜底")
    func writeFileMissingContent() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-r17-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = WriteFileTool()
        let result = try await tool.execute(["path": dir.appendingPathComponent("empty.txt").path], context: context())
        #expect(result.error == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("empty.txt").path))
    }

    /// ② list_files：缺 path → `?? "."`；limit 非数字 → `Int(...) ?? 100`
    @Test("list_files: 缺 path + 非法 limit → 双兜底")
    func listFilesFallbacks() async throws {
        let tool = ListFilesTool()
        let result = try await tool.execute(["limit": "abc"], context: context())
        #expect(result.error == nil)
        let text = result.content.compactMap { block -> String? in
            if case let .text(s) = block {
                return s
            }
            return nil
        }.joined()
        #expect(!text.isEmpty)
    }

    /// ③ web_fetch：响应体非 UTF-8（0xFF 填充）→ `String(utf8) ?? isoLatin1` 兜底
    private final class BadUTF8Protocol: URLProtocol {
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
            // 256KB 0xFF：非法 UTF-8 → isoLatin1 兜底解码（< maxBytes 不触发 tooLarge）
            client?.urlProtocol(self, didLoad: Data(repeating: 0xFF, count: 256_000))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @Test("web_fetch: 非 UTF-8 响应 → isoLatin1 兜底解码")
    func webFetchNonUTF8Fallback() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BadUTF8Protocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let tool = WebFetchTool(session: session, timeout: 30)
        let result = try await tool.execute(["url": "http://r17.local/binary"], context: context())
        #expect(result.error == nil)
    }

    /// ④ ToolRegistry.schemas()：跨分类多工具 → 排序比较闭包命中（既有测试单工具/零工具）
    @Test("ToolRegistry.schemas: 跨分类排序闭包")
    func schemasSortClosure() async {
        let registry = ToolRegistry()
        await registry.register(ReadFileTool()) // filesystem
        await registry.register(WebFetchTool()) // network
        await registry.register(WriteFileTool()) // filesystem（同分类按名排序）
        let schemas = await registry.schemas()
        #expect(schemas.count == 3)
        #expect(schemas.first?.name == "read_file") // filesystem(0) 且 r < w
    }
}
