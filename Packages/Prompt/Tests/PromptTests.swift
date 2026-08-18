import Foundation
import Prompt
import Testing

// MARK: - 渲染器

@Suite("TemplateRenderer")
struct TemplateRendererTests {
    @Test("变量替换：标量变量")
    func variables() {
        let text = TemplateRenderer.render(
            "当前工作区：{{workspace}}，模型：{{model}}",
            context: .init(variables: ["workspace": "/tmp/ws", "model": "deepseek-chat"])
        )
        #expect(text == "当前工作区：/tmp/ws，模型：deepseek-chat")
    }

    @Test("缺失变量渲染为空")
    func missingVariable() {
        let text = TemplateRenderer.render("A-{{nope}}-B", context: .empty)
        #expect(text == "A--B") // 占位符移除，两侧字面量保留
    }

    @Test("条件块：有内容则展开")
    func blockExpanded() {
        let template = "前{{#ctx}}块内容{{/ctx}}后"
        let text = TemplateRenderer.render(template, context: .init(blocks: ["ctx": "动态上下文X"]))
        #expect(text == "前动态上下文X后")
    }

    @Test("条件块：无内容则整块移除")
    func blockRemoved() {
        let template = "前{{#ctx}}块内容{{/ctx}}后"
        let text = TemplateRenderer.render(template, context: .empty)
        #expect(text == "前后")
    }

    @Test("条件块：无闭合标记保留原文")
    func blockUnclosed() {
        let text = TemplateRenderer.render("前{{#ctx}}残留{{/ctx2}}后", context: .init(blocks: ["ctx": "x"]))
        #expect(text.contains("{{#ctx}}"))
    }

    @Test("多块与块内变量：先展开块再替换变量")
    func nestedSubstitution() {
        let template = "{{#a}}值={{v}}{{/a}}{{#b}}[{{v2}}]{{/b}}"
        let text = TemplateRenderer.render(
            template,
            context: .init(variables: ["v": "1", "v2": "2"], blocks: ["a": ""])
        )
        // a 块内容为 "" → 整块移除；b 块未提供 → 同样整块移除
        #expect(text.isEmpty)
    }

    @Test("未绑定占位符被移除，普通花括号保留")
    func unboundPlaceholders() {
        let text = TemplateRenderer.render("x={{a}} y={单} z={{bad!char}}", context: .empty)
        #expect(text == "x= y={单} z={{bad!char}}")
    }

    @Test("模板渲染：段落标题 + 优先级排序 + 禁用段跳过")
    func templateSections() throws {
        let template = PromptTemplate(
            name: "t",
            sections: [
                PromptSection(kind: .output, title: "输出", template: "OUT", priority: 50),
                PromptSection(kind: .rules, title: "规则", template: "RULES", priority: 10),
                PromptSection(kind: .context, title: "空段", template: "{{#none}}x{{/none}}", priority: 20),
            ]
        )
        let text = try TemplateRenderer.renderTemplate(template, context: .empty)
        #expect(text == "## 规则\nRULES\n\n## 输出\nOUT")
    }

    @Test("模板渲染：全空抛 emptyTemplate")
    func emptyTemplateThrows() {
        let template = PromptTemplate(name: "t", sections: [
            PromptSection(kind: .role, title: "角色", template: "{{#ghost}}x{{/ghost}}"),
        ])
        #expect(throws: PromptError.self) {
            _ = try TemplateRenderer.renderTemplate(template, context: .empty)
        }
    }
}

// MARK: - 模型档案与适配

@Suite("ModelProfile & Adapter")
struct ModelProfileTests {
    @Test("档案匹配：前缀不区分大小写")
    func profileMatch() {
        #expect(ModelProfileCatalog.profile(for: "deepseek-chat").family == "deepseek")
        #expect(ModelProfileCatalog.profile(for: "DeepSeek-Coder").family == "deepseek")
        #expect(ModelProfileCatalog.profile(for: "gpt-4o").family == "openai")
        #expect(ModelProfileCatalog.profile(for: "claude-sonnet-4-5").family == "anthropic")
        #expect(ModelProfileCatalog.profile(for: "qwen2.5-coder-7b").family == "local")
        #expect(ModelProfileCatalog.profile(for: "totally-unknown-model").family == "generic")
    }

    @Test("适配：jsonFenced 追加工具调用格式约定")
    func jsonFenced() {
        let sections = [PromptSection(kind: .tools, title: "工具", template: "基础说明")]
        let profile = ModelProfile(family: "local", contextWindow: 8192, toolCallStyle: .jsonFenced)
        let adapted = ModelPromptAdapter.adapt(sections, profile: profile)
        let tools = adapted.first { $0.kind == .tools }
        #expect(tools?.template.contains(ModelPromptAdapter.jsonFencedDirective) == true)
    }

    @Test("适配：none 移除 tools 段")
    func noneRemovesTools() {
        let sections = [
            PromptSection(kind: .role, title: "角色", template: "r"),
            PromptSection(kind: .tools, title: "工具", template: "t"),
        ]
        let profile = ModelProfile(family: "x", contextWindow: 1024, toolCallStyle: .none)
        let adapted = ModelPromptAdapter.adapt(sections, profile: profile)
        #expect(adapted.allSatisfy { $0.kind != .tools })
        #expect(adapted.count == 1)
    }

    @Test("适配：promptNotes 追加模型说明段")
    func notesAppended() {
        let sections = [PromptSection(kind: .role, title: "角色", template: "r")]
        let profile = ModelProfile(family: "y", contextWindow: 1024, toolCallStyle: .native,
                                   promptNotes: ["注意A", "注意B"])
        let adapted = ModelPromptAdapter.adapt(sections, profile: profile)
        let notes = adapted.first { $0.title == ModelPromptAdapter.modelNotesTitle }
        #expect(notes?.template == "注意A\n注意B")
    }

    @Test("token 估算：中文按 1、ASCII 按 0.25")
    func estimate() {
        #expect(ModelPromptAdapter.estimateTokens("中文") == 3) // 2 CJK + 1 保底
        #expect(ModelPromptAdapter.estimateTokens("abcd") == 2)
        #expect(ModelPromptAdapter.estimateTokens("") >= 1)
    }
}

// MARK: - 模板存储（版本快照）

@Suite("PromptTemplateStore")
struct PromptStoreTests {
    @Test("注册拒绝同名；查询返回")
    func register() async {
        let store = PromptTemplateStore()
        let t = PromptTemplate(name: "a", sections: [PromptSection(kind: .role, template: "v1")])
        #expect(await store.register(t) == true)
        #expect(await store.register(t) == false)
        #expect(await store.template(named: "a")?.version == 1)
    }

    @Test("update：版本递增 + 历史快照可回放")
    func updateVersions() async {
        let store = PromptTemplateStore()
        _ = await store.register(PromptTemplate(name: "a", sections: [PromptSection(kind: .role, template: "v1")]))
        let v2 = await store.update(named: "a") { t in
            PromptTemplate(name: t.name, description: t.description,
                           sections: [PromptSection(kind: .role, template: "v2")],
                           version: t.version, updatedAt: t.updatedAt, isBuiltIn: t.isBuiltIn)
        }
        #expect(v2?.version == 2)
        #expect(await store.template(named: "a", version: 1)?.sections.first?.template == "v1")
        #expect(await store.template(named: "a", version: 2)?.sections.first?.template == "v2")
        #expect(await store.template(named: "a")?.version == 2)
        #expect(await (store.versions(of: "a")) == [1, 2])
    }

    @Test("历史 FIFO 淘汰（上限 2）")
    func historyTrim() async {
        let store = PromptTemplateStore(historyLimit: 2)
        _ = await store.register(PromptTemplate(name: "a", sections: [PromptSection(kind: .role, template: "v1")]))
        for v in 2 ... 4 {
            _ = await store.update(named: "a") { t in
                PromptTemplate(name: t.name, description: "", sections: [PromptSection(kind: .role, template: "v\(v)")],
                               version: t.version, updatedAt: t.updatedAt, isBuiltIn: false)
            }
        }
        #expect(await store.template(named: "a", version: 1) == nil) // 最旧被淘汰
        #expect(await store.template(named: "a", version: 3)?.sections.first?.template == "v3")
        #expect(await store.template(named: "a", version: 4) != nil)
    }

    @Test("快照含稳定 SHA-256 指纹")
    func snapshotHash() async {
        let store = PromptTemplateStore()
        let t = PromptTemplate(name: "a", sections: [PromptSection(kind: .role, template: "hello")])
        _ = await store.register(t)
        let snap = await store.latestSnapshot(named: "a")
        #expect(snap?.version == 1)
        #expect(snap?.contentHash.count == 64)
        // 相同内容 → 相同指纹
        let store2 = PromptTemplateStore()
        _ = await store2.register(t)
        #expect(await (store2.latestSnapshot(named: "a"))?.contentHash == snap?.contentHash)
    }

    @Test("删除模板（含历史）")
    func remove() async {
        let store = PromptTemplateStore()
        _ = await store.register(PromptTemplate(name: "a", sections: [PromptSection(kind: .role, template: "v1")]))
        #expect(await store.remove(named: "a") == true)
        #expect(await store.remove(named: "a") == false)
        #expect(await store.template(named: "a") == nil)
    }
}

// MARK: - 渲染器（端到端）

@Suite("PromptRenderer")
struct PromptRendererTests {
    private func makeEngine() async -> PromptEngine {
        let store = PromptTemplateStore()
        let engine = PromptEngine(store: store, renderer: PromptRenderer(store: store))
        _ = await BuiltInPromptTemplates.install(into: store)
        return engine
    }

    @Test("端到端：agent 模板 + deepseek 档案适配")
    func endToEnd() async throws {
        let engine = await makeEngine()
        let rendered = try await engine.renderDetailed(
            template: PromptEngine.agentTemplate,
            model: "deepseek-chat",
            context: .init(blocks: ["context": "工作区：/tmp/ws"])
        )
        #expect(rendered.templateName == "agent")
        #expect(rendered.templateVersion == 1)
        #expect(rendered.modelFamily == "deepseek")
        #expect(rendered.text.contains("## 角色"))
        #expect(rendered.text.contains("工作区：/tmp/ws"))
        #expect(rendered.text.contains(ModelPromptAdapter.modelNotesTitle)) // deepseek 有 promptNotes
        #expect(rendered.sectionTitles.first == "角色")
        #expect(rendered.estimatedTokens > 50)
    }

    @Test("端到端：generic 模型无模型说明段")
    func genericModelNoNotes() async throws {
        let engine = await makeEngine()
        let rendered = try await engine.renderDetailed(template: PromptEngine.agentTemplate, model: "mystery-9")
        #expect(rendered.modelFamily == "generic")
        #expect(!rendered.text.contains(ModelPromptAdapter.modelNotesTitle))
    }

    @Test("指纹：同输入稳定，异输入不同")
    func fingerprintStability() async throws {
        let engine = await makeEngine()
        let a = try await engine.renderDetailed(template: "agent", model: "deepseek-chat")
        let b = try await engine.renderDetailed(template: "agent", model: "deepseek-chat")
        let c = try await engine.renderDetailed(template: "agent", model: "gpt-4o")
        #expect(a.fingerprint == b.fingerprint)
        #expect(a.fingerprint != c.fingerprint)
        #expect(a.fingerprint.count == 64)
    }

    @Test("模板不存在 / 版本不存在 抛错")
    func errors() async {
        let engine = await makeEngine()
        do {
            _ = try await engine.renderDetailed(template: "ghost", model: "deepseek-chat")
            Issue.record("expected templateNotFound")
        } catch let error as PromptError {
            guard case .templateNotFound = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        do {
            _ = try await engine.renderer.render(template: "agent", version: 99, model: "deepseek-chat")
            Issue.record("expected versionNotFound")
        } catch let error as PromptError {
            guard case .versionNotFound = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("版本回放：更新模板后可渲染 v1 与 v2")
    func versionReplay() async throws {
        let engine = await makeEngine()
        _ = await engine.store.update(named: PromptEngine.agentTemplate) { t in
            var sections = t.sections
            sections[0] = PromptSection(kind: .role, title: "角色", template: "V2 角色描述", priority: 10)
            return PromptTemplate(name: t.name, description: t.description, sections: sections,
                                  version: t.version, updatedAt: t.updatedAt, isBuiltIn: t.isBuiltIn)
        }
        let v1 = try await engine.renderer.render(template: "agent", version: 1, model: "deepseek-chat")
        let v2 = try await engine.renderer.render(template: "agent", version: 2, model: "deepseek-chat")
        #expect(!v1.text.contains("V2 角色描述"))
        #expect(v2.text.contains("V2 角色描述"))
        #expect(v1.templateVersion == 1 && v2.templateVersion == 2)
    }

    @Test("内置模板安装幂等")
    func installIdempotent() async {
        let store = PromptTemplateStore()
        let first = await BuiltInPromptTemplates.install(into: store)
        let second = await BuiltInPromptTemplates.install(into: store)
        #expect(first == ["agent", "subagent"])
        #expect(second.isEmpty)
        #expect(await store.template(named: "subagent")?.isBuiltIn == true)
    }
}
