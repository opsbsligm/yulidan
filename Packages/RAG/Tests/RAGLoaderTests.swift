import Foundation
import RAG
import Testing

/// DocumentLoader 单元测试：各格式解析 + 错误分支
@Suite("DocumentLoader")
struct RAGLoaderTests {
    private let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rag-tests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    private func write(_ name: String, _ content: String) throws -> String {
        let url = tmp.appendingPathComponent(name)
        try content.data(using: .utf8)?.write(to: url)
        return url.path
    }

    @Test func loadTxt() throws {
        let path = try write("a.txt", "hello world\nsecond line")
        let doc = try DocumentLoader.load(path: path)
        #expect(doc.text == "hello world\nsecond line")
        #expect(doc.title == "a")
        #expect(doc.source.hasSuffix("a.txt"))
    }

    @Test func loadMarkdownStripsSyntax() throws {
        let md = """
        # 标题一

        正文段落，带**粗体**和[链接文字](https://example.com)。

        - 列表项
        1. 编号项

        ```swift
        let x = 1
        ```
        """
        let path = try write("doc.md", md)
        let doc = try DocumentLoader.load(path: path)
        #expect(!doc.text.contains("# 标题一"))
        #expect(doc.text.contains("标题一"))
        #expect(!doc.text.contains("**"))
        #expect(doc.text.contains("链接文字"))
        #expect(!doc.text.contains("https://example.com"))
        #expect(!doc.text.contains("- 列表项"))
        #expect(doc.text.contains("let x = 1"))
    }

    @Test func loadHTMLStripsTags() throws {
        let html = """
        <html><head><style>body{color:red}</style></head>
        <body><h1>大标题</h1><p>第一段&amp;第二段</p><ul><li>条目</li></ul></body></html>
        """
        let path = try write("page.html", html)
        let doc = try DocumentLoader.load(path: path)
        #expect(doc.text.contains("大标题"))
        #expect(doc.text.contains("第一段&第二段"))
        #expect(doc.text.contains("条目"))
        #expect(!doc.text.contains("<"))
        #expect(!doc.text.contains("color:red"))
    }

    @Test func loadJSONExtractsTexts() throws {
        let json = """
        {"title":"手册","items":["条目A","条目B"],"count":2}
        """
        let path = try write("data.json", json)
        let doc = try DocumentLoader.load(path: path)
        #expect(doc.text.contains("title: 手册"))
        #expect(doc.text.contains("条目A"))
        #expect(doc.text.contains("条目B"))
        #expect(doc.text.contains("count: 2"))
    }

    @Test func loadNotFound() {
        do {
            _ = try DocumentLoader.load(path: tmp.appendingPathComponent("nope.txt").path)
            Issue.record("应当抛出 notFound")
        } catch let err as DocumentLoadError {
            guard case .notFound = err else {
                Issue.record("错误类型不对：\(err)")
                return
            }
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    @Test func loadUnsupportedExtension() throws {
        let path = try write("binary.bin", "xx")
        do {
            _ = try DocumentLoader.load(path: path)
            Issue.record("应当抛出 unsupportedExtension")
        } catch let err as DocumentLoadError {
            guard case .unsupportedExtension = err else {
                Issue.record("错误类型不对：\(err)")
                return
            }
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    @Test func loadTooLarge() throws {
        let path = tmp.appendingPathComponent("big.txt").path
        FileManager.default.createFile(atPath: path, contents: nil)
        let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer {
            try? FileManager.default.removeItem(atPath: path)
        }
        // 上限 5MB，写 5MB+1 字节（稀疏写：只移动 offset 再写 1 字节）
        try fh.seek(toOffset: UInt64(DocumentLoader.maxBytes))
        try fh.write(contentsOf: Data([0x41]))
        try fh.close()
        do {
            _ = try DocumentLoader.load(path: path)
            Issue.record("应当抛出 tooLarge")
        } catch let err as DocumentLoadError {
            guard case .tooLarge = err else {
                Issue.record("错误类型不对：\(err)")
                return
            }
        } catch {
            Issue.record("错误类型不对：\(error)")
        }
    }

    @Test func loadTextHelper() {
        let doc = DocumentLoader.loadText("正文内容", source: "mem:1", title: "自定义标题", metadata: ["tag": "t"])
        #expect(doc.text == "正文内容")
        #expect(doc.title == "自定义标题")
        #expect(doc.metadata["tag"] == "t")
    }
}
