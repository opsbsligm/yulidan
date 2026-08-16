import Foundation

/// 流式块 — 承载一次 SSE 增量数据
public struct StreamChunk: Sendable, Codable {
    public let type: String
    public let data: Data
    public let index: Int

    public init(type: String, data: Data, index: Int) {
        self.type = type
        self.data = data
        self.index = index
    }
}
