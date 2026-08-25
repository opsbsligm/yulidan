import Foundation
@testable import ServiceContainer
import Testing

@Suite("EventBus Tests")
struct EventBusTests {
    @Test("Waterfall returns result")
    func testWaterfall() async {
        let bus = EventBus()
        let payload = AnyCodable("start")
        await bus.onWaterfall(eventType: "test") { _, _ in AnyCodable("done") }
        let result = await bus.waterfall(payload: payload, eventType: "test")
        #expect(result != nil)
    }

    @Test("Parallel runs all handlers")
    func testParallel() async {
        let bus = EventBus()
        let counter = Counter()
        await bus.onParallel(eventType: "test") { _ in await counter.increment() }
        await bus.onParallel(eventType: "test") { _ in await counter.increment() }
        await bus.parallel(payload: AnyCodable("x"), eventType: "test")
        #expect(await counter.value == 2)
    }

    @Test("Serial runs in order")
    func testSerial() async {
        let bus = EventBus()
        let order = IntArray()
        await bus.onSerial(eventType: "test") { _ in await order.append(1) }
        await bus.onSerial(eventType: "test") { _ in await order.append(2) }
        await bus.serial(payload: AnyCodable("x"), eventType: "test")
        #expect(await order.elements == [1, 2])
    }

    @Test("Clear removes handlers")
    func testClear() async {
        let bus = EventBus()
        await bus.onEmit(eventType: "test") { _ in }
        await bus.clear(eventType: "test")
    }

    @Test("ClearAll removes all")
    func testClearAll() async {
        let bus = EventBus()
        await bus.onEmit(eventType: "a") { _ in }
        await bus.onSerial(eventType: "b") { _ in }
        await bus.clearAll()
    }
}

private actor Counter {
    var value: Int = 0
    func increment() {
        value += 1
    }
}

private actor IntArray {
    var elements: [Int] = []
    func append(_ element: Int) {
        elements.append(element)
    }
}

@Suite("EventBus emit delivery")
struct EventBusEmitTests {
    private actor PayloadBox {
        var deliveries = 0
        var last: String?

        func record(_ payload: AnyCodable) {
            deliveries += 1
            last = payload.value as? String
        }

        var snapshot: (Int, String?) {
            (deliveries, last)
        }
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test("emit delivers payload to onEmit handlers")
    func emitDelivers() async {
        let bus = EventBus()
        let box = PayloadBox()
        await bus.onEmit(eventType: "emit.delivery") { payload in
            await box.record(payload)
        }
        await bus.emit(payload: AnyCodable("payload-value"), eventType: "emit.delivery")
        let delivered = await waitUntil { await box.deliveries == 1 }
        let (count, last) = await box.snapshot
        #expect(delivered)
        #expect(count == 1)
        #expect(last == "payload-value")
    }

    @Test("emit with no registered handlers is a no-op")
    func emitNoHandlersNoOp() async {
        let bus = EventBus()
        await bus.emit(payload: AnyCodable("x"), eventType: "nobody.listening")
        // 无 handler 时同步返回、不崩溃即契约
    }

    @Test("clear stops emit delivery")
    func clearStopsEmit() async {
        let bus = EventBus()
        let box = PayloadBox()
        await bus.onEmit(eventType: "emit.stopped") { payload in
            await box.record(payload)
        }
        await bus.clear(eventType: "emit.stopped")
        await bus.emit(payload: AnyCodable("late"), eventType: "emit.stopped")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await box.deliveries == 0)
    }
}
