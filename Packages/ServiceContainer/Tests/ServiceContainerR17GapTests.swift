import Foundation
import ServiceContainer
import Testing

// MARK: - 覆盖审计轮 17：AnyCodable 终极兜底 + EventBus 四路分发闭包

@Suite("ServiceContainer R17 Gap Coverage")
struct ServiceContainerR17GapTests {
    /// ① 自定义 Decoder：decodeNil=false 且全部类型化 decode 失败
    ///    → 穷尽 bool/Int/Double/String/Array/Dict 六分支后落到终极 NSNull 兜底（L48-50）
    ///    （JSONDecoder 下不可达：非空 JSON 值必属六类之一；此为 Codable 契约下的合法输入）
    private struct FailingSingleValueContainer: SingleValueDecodingContainer {
        var codingPath: [CodingKey] {
            []
        }

        private func fail<T>(_: T.Type) throws -> T {
            throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: [], debugDescription: "无可用值"))
        }

        func decodeNil() -> Bool {
            false
        }

        func decode(_ type: Bool.Type) throws -> Bool {
            try fail(type)
        }

        func decode(_ type: String.Type) throws -> String {
            try fail(type)
        }

        func decode(_ type: Double.Type) throws -> Double {
            try fail(type)
        }

        func decode(_ type: Int.Type) throws -> Int {
            try fail(type)
        }

        func decode(_ type: Int8.Type) throws -> Int8 {
            try fail(type)
        }

        func decode(_ type: Int16.Type) throws -> Int16 {
            try fail(type)
        }

        func decode(_ type: Int32.Type) throws -> Int32 {
            try fail(type)
        }

        func decode(_ type: Int64.Type) throws -> Int64 {
            try fail(type)
        }

        func decode(_ type: UInt8.Type) throws -> UInt8 {
            try fail(type)
        }

        func decode(_ type: UInt16.Type) throws -> UInt16 {
            try fail(type)
        }

        func decode(_ type: UInt32.Type) throws -> UInt32 {
            try fail(type)
        }

        func decode(_ type: UInt64.Type) throws -> UInt64 {
            try fail(type)
        }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try fail(type)
        }
    }

    private struct FailingDecoder: Decoder {
        let container = FailingSingleValueContainer()
        var codingPath: [CodingKey] {
            []
        }

        var userInfo: [CodingUserInfoKey: Any] {
            [:]
        }

        func unkeyedContainer() throws -> UnkeyedDecodingContainer {
            throw DecodingError.valueNotFound(AnyCodable.self, DecodingError.Context(codingPath: [], debugDescription: "无"))
        }

        func container<K: CodingKey>(keyedBy _: K.Type) throws -> KeyedDecodingContainer<K> {
            throw DecodingError.valueNotFound(AnyCodable.self, DecodingError.Context(codingPath: [], debugDescription: "无"))
        }

        func singleValueContainer() throws -> SingleValueDecodingContainer {
            container
        }
    }

    @Test("AnyCodable: 全部类型化解码失败 → 终极 NSNull 兜底")
    func decodeExhaustionFallsBackToNSNull() throws {
        let value = try AnyCodable(from: FailingDecoder())
        #expect(value.value is NSNull)
    }

    /// ② decodeNil 直通分支 + NSNull encode → encodeNil（null 往返）
    @Test("AnyCodable: JSON null 往返（decodeNil 直通 + encodeNil）")
    func nullRoundTrip() throws {
        let value = try JSONDecoder().decode(AnyCodable.self, from: Data("null".utf8))
        #expect(value.value is NSNull)
        let data = try JSONEncoder().encode(value)
        #expect(String(data: data, encoding: .utf8) == "null")
    }

    private actor TagBox {
        private var tags: Set<String> = []
        func add(_ tag: String) {
            tags.insert(tag)
        }

        func has(_ tag: String) -> Bool {
            tags.contains(tag)
        }
    }

    /// ③ EventBus 四路分发：emit / waterfall（含 next() 续接闭包）/ parallel / serial
    ///    —— 各分发路径的任务组/循环闭包在「有 handler 且实际派发」时才执行
    @Test("EventBus: emit/waterfall/parallel/serial 全路径分发（含 next()）")
    func dispatchClosuresRun() async {
        let bus = EventBus()
        let box = TagBox()
        let type = "r17.dispatch"
        await bus.onEmit(eventType: type) { _ in
            await box.add("emit")
        }
        await bus.onWaterfall(eventType: type) { _, next in
            _ = await next() // 命中 `{ previous }` 续接闭包
            return AnyCodable(1)
        }
        await bus.onParallel(eventType: type) { _ in
            await box.add("parallel")
        }
        await bus.onSerial(eventType: type) { _ in
            await box.add("serial")
        }

        await bus.emit(payload: AnyCodable("p"), eventType: type)
        _ = await bus.waterfall(payload: AnyCodable(0), eventType: type)
        await bus.parallel(payload: AnyCodable("p"), eventType: type)
        await bus.serial(payload: AnyCodable("p"), eventType: type)

        // emit 走 detached Task：轮询等待
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await box.has("emit") {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(await box.has("emit"))
        #expect(await box.has("parallel"))
        #expect(await box.has("serial"))
    }
}
