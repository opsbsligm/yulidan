@testable import HarnessApp
import Testing

// MARK: - P1.2 GlassMorphTabBar 纯函数（分段映射 / 六分区数据形状）

@Suite("P1.2 GlassMorphTabBar 分段映射")
struct GlassMorphTabBarTests {
    @Test("selectedID：五 tab → 分段 id；settings 无分段选中态（P0 行为一致）")
    func selectedIDMapping() {
        #expect(MorphTabSegment.selectedID(for: .chat) == "chat")
        #expect(MorphTabSegment.selectedID(for: .agents) == "agents")
        #expect(MorphTabSegment.selectedID(for: .plugins) == "plugins")
        #expect(MorphTabSegment.selectedID(for: .skills) == "skills")
        #expect(MorphTabSegment.selectedID(for: .tools) == "tools")
        #expect(MorphTabSegment.selectedID(for: .settings) == nil)
    }

    @Test("sidebarDefault：六分区形状（新对话瞬时 + 五面板；⌘N + ⌘1–⌘5）")
    func sidebarDefaultShape() {
        let segs = MorphTabSegment.sidebarDefault
        #expect(segs.count == 6)
        // id 全局唯一（glassEffectID / ForEach 身份依赖）
        #expect(Set(segs.map(\.id)).count == 6)
        // 新对话 = 瞬时动作 + ⌘N
        let newChat = segs.first { $0.id == "new-chat" }
        #expect(newChat != nil)
        #expect(newChat?.action == .newChat)
        #expect(newChat?.key?.character == "n")
        // 五面板 = tab 选择 + ⌘1–⌘5（与折叠 rail NavRowShortcut 口径一致）
        let expected: [(String, Character)] = [("chat", "1"), ("agents", "2"), ("plugins", "3"), ("skills", "4"), ("tools", "5")]
        for (id, key) in expected {
            let seg = segs.first { $0.id == id }
            #expect(seg != nil)
            #expect(seg?.key?.character == key)
            #expect(seg?.action != .newChat)
        }
    }

    @Test("TileFaceMode：选中+native→玻璃morph面 / 选中+降级→solid / 未选中→素面（走查修复三态不变量）")
    func tileFaceModeResolve() {
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: true, isNative: true) == .glassMorph)
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: true, isNative: false) == .solid)
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: false, isNative: true) == .plain)
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: false, isNative: false) == .plain)
    }
}
