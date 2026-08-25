import Foundation
@testable import Memory
import Testing

/// LongTermMemoryStore 内存索引语义 + HARNESS_HOME 覆盖分支
@Suite("LongTermMemoryStore")
struct LongTermMemoryStoreTests {
    private func makeItem(_ id: String, topic: String = "t") -> MemoryItem {
        MemoryItem(id: id, kind: .fact, topic: topic, content: "content \(id)",
                   significance: 0.8, sourceSession: "s", origin: .manual, vector: [])
    }

    @Test("byID returns stored item, nil for unknown")
    func byIDLookup() async {
        let store = LongTermMemoryStore()
        await store.upsert(makeItem("m1"))
        #expect(await store.byID("m1")?.content == "content m1")
        #expect(await store.byID("nope") == nil)
    }

    @Test("remove returns true once, false for unknown or already removed")
    func removeSemantics() async {
        let store = LongTermMemoryStore()
        await store.upsert(makeItem("m1"))
        #expect(await store.remove("m1") == true)
        #expect(await store.remove("m1") == false)
        #expect(await store.remove("never-existed") == false)
    }

    @Test("clear empties items and bumps revision")
    func clearSemantics() async {
        let store = LongTermMemoryStore()
        await store.upsert(makeItem("m1"))
        await store.upsert(makeItem("m2"))
        let revBefore = await store.revision
        await store.clear()
        #expect(await store.count() == 0)
        #expect(await store.count(activeOnly: false) == 0)
        #expect(await store.revision == revBefore + 1)
    }

    @Test("HARNESS_HOME env overrides defaultFileURL")
    func harnessHomeOverride() {
        let oldPtr = getenv("HARNESS_HOME")
        let oldStr = oldPtr.map { String(cString: $0) }
        let tmp = NSTemporaryDirectory() + "harness-cov-\(UUID().uuidString)"
        setenv("HARNESS_HOME", tmp, 1)
        defer {
            if let oldStr {
                setenv("HARNESS_HOME", oldStr, 1)
            } else {
                unsetenv("HARNESS_HOME")
            }
        }
        let url = LongTermMemoryStore.defaultFileURL
        #expect(url.path.hasSuffix("/.harness/memory/longterm.json"))
        #expect(url.path.hasPrefix(tmp))
    }
}
