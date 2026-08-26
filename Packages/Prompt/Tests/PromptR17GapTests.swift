import Foundation
import Prompt
import Testing

// MARK: - 覆盖审计轮 17：Prompt 残余兜底行（versions ?? [] / latestSnapshot max 闭包 / FIFO 淘汰 / 渲染排序闭包）

@Suite("Prompt R17 Gap Coverage")
struct PromptR17GapTests {
    private func makeTemplate(_ name: String) -> PromptTemplate {
        PromptTemplate(
            name: name,
            description: "r17 gap 测试模板",
            sections: [PromptSection(kind: .role, title: "角色", template: "你是{{agent}}助手")]
        )
    }

    /// ① 未注册模板 → `(history[name]?.keys.sorted()) ?? []` 兜底
    @Test("versions: 未注册模板 → 空数组兜底")
    func versionsOfGhostTemplate() async {
        let store = PromptTemplateStore()
        #expect(await store.versions(of: "ghost-template") == [])
    }

    /// ② 注册 + 一次更新 → 两个快照 → `max { $0.version < $1.version }` 闭包执行
    @Test("latestSnapshot: 多版本 max 闭包")
    func latestSnapshotMaxClosure() async {
        let store = PromptTemplateStore()
        _ = await store.register(makeTemplate("multi"))
        let updated = await store.update(named: "multi") { template in
            var copy = template
            copy.description = "updated"
            return copy
        }
        #expect(updated?.version == 2)
        let snapshot = await store.latestSnapshot(named: "multi")
        #expect(snapshot?.version == 2)
        #expect(snapshot?.template.description == "updated")
    }

    /// ③ historyLimit=2 连续两次更新 → FIFO 淘汰最旧版本
    @Test("update: historyLimit FIFO 淘汰")
    func fifoEviction() async {
        let store = PromptTemplateStore(historyLimit: 2)
        _ = await store.register(makeTemplate("fifo"))
        _ = await store.update(named: "fifo") { $0 }
        _ = await store.update(named: "fifo") { $0 }
        #expect(await store.versions(of: "fifo") == [2, 3])
        // 被淘汰的版本取不到，最新快照仍可取
        #expect(await store.template(named: "fifo", version: 1) == nil)
        #expect(await (store.latestSnapshot(named: "fifo"))?.version == 3)
    }

    /// ④ 双条件块 + 双变量 → expandBlocks / substituteVariables 两个 sorted 闭包执行
    @Test("render: 双块双变量 → 排序闭包")
    func renderSortClosures() {
        let template = "{{#alpha}}A块内容{{/alpha}} {{#beta}}B块内容{{/beta}} 变量{{one}}/{{two}}"
        let out = TemplateRenderer.render(template, context: .init(
            variables: ["one": "1", "two": "2"],
            blocks: ["alpha": "A内容", "beta": "B内容"]
        ))
        #expect(out.contains("A内容"))
        #expect(out.contains("B内容"))
        #expect(out.contains("变量1/2"))
    }
}
