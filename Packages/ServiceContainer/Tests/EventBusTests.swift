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
