import Foundation
import Prompt
import Testing

// MARK: - Prompt 包薄弱分支覆盖（覆盖审计轮 13）

@Suite("Prompt Gap Coverage")
struct PromptGapCoverageTests {
    /// ① PromptTemplateStore.all()：按模板名升序返回全部模板
    @Test("all()：多模板注册后按名升序返回")
    func allReturnsSortedTemplates() async {
        let store = PromptTemplateStore()
        _ = await store.register(PromptTemplate(name: "b", sections: [PromptSection(kind: .role, template: "B")]))
        _ = await store.register(PromptTemplate(name: "a", sections: [PromptSection(kind: .role, template: "A")]))
        let all = await store.all()
        #expect(all.map(\.name) == ["a", "b"])
    }

    /// ② placeholderClose：占位符名后直接到字符串尾（无 }} 闭合）→ 返回 nil → 原文保留
    @Test("占位符字符串尾未闭合（abc{{xyz）：EOF 分支保留原文")
    func unterminatedPlaceholderAtEOF() {
        let text = TemplateRenderer.render("abc{{xyz", context: .empty)
        #expect(text == "abc{{xyz")
    }

    /// ③ PromptRenderer.render：全部段落渲染为空 → 抛 emptyTemplate
    @Test("PromptRenderer.render：全空段落 → 抛 emptyTemplate")
    func rendererEmptyTemplateThrows() async {
        let store = PromptTemplateStore()
        _ = await store.register(PromptTemplate(name: "empty", sections: [
            PromptSection(kind: .role, title: "角色", template: "{{#ghost}}x{{/ghost}}"),
        ]))
        let renderer = PromptRenderer(store: store)
        await #expect(throws: PromptError.self) {
            _ = try await renderer.render(template: "empty", model: "totally-unknown-model", context: .empty)
        }
    }
}
