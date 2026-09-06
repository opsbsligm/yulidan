@testable import HarnessApp
import SwiftUI
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

    @Test("TileFaceMode：native→常驻玻璃面（D-1 面数根因）/ 降级+选中→solid / 降级+未选中→素面（三态不变量）")
    func tileFaceModeResolve() {
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: true, isNative: true) == .glassBase)
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: true, isNative: false) == .solid)
        // 09-06 D-1 实施：native 态**未选中也常驻玻璃面**（旧 `.plain` ⇒ 容器内仅 1 面＝§3-A1 根因 GAP）
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: false, isNative: true) == .glassBase)
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: false, isNative: false) == .plain)
    }
}

// MARK: - G2/F1 Morph 几何判据（容器 spacing 覆盖最坏最近边距离 = morph 生效前提）

@Suite("G2 MorphTabGeometry 容器 spacing 判据")
struct MorphTabGeometryTests {
    @Test("容器 spacing 覆盖最坏最近边距离（覆盖不足 → 远距离切换静默退化为淡变 = P1.2 实机症状根因）")
    func containerSpacingCoversWorstDistance() {
        let spacing = MorphTabGeometry.fullGridSpacing
        let worst = MorphTabGeometry.worstNearestEdgeDistance(
            tileWidth: MorphTabGeometry.tileWidthCap,
            tileHeight: MorphTabGeometry.tileHeight,
            gridSpacing: MorphTabGeometry.gridSpacing,
            columns: MorphTabGeometry.columns
        )
        #expect(spacing >= worst, "容器 spacing 必须 ≥ 最坏最近边距离")
        #expect(MorphTabGeometry.qualifiesForMatchedGeometry(
            nearestEdgeDistance: worst,
            containerSpacing: spacing
        ))
    }

    @Test("相邻面与最远面均落入 matchedGeometry 适用域（同列/隔列/跨行三类切换一致，无部分生效）")
    func allTransitionPairsQualify() {
        let spacing = MorphTabGeometry.fullGridSpacing
        let gap = MorphTabGeometry.gridSpacing
        let worst = MorphTabGeometry.worstNearestEdgeDistance(
            tileWidth: MorphTabGeometry.tileWidthCap,
            tileHeight: MorphTabGeometry.tileHeight,
            gridSpacing: gap,
            columns: MorphTabGeometry.columns
        )
        // 同列相邻行 / 同行相邻列 最近边 = 网格间距；最坏 = 跨 2 列跨 1 行
        for distance in [gap, worst] {
            #expect(
                MorphTabGeometry.qualifiesForMatchedGeometry(
                    nearestEdgeDistance: distance,
                    containerSpacing: spacing
                ),
                "该切换距离应落入 morph 适用域"
            )
        }
    }

    @Test("列数退化防御（0/1 列）：距离有限为正，且容器 spacing 仍覆盖")
    func degenerateGeometryIsSafe() {
        for columns in [0, 1] {
            let worst = MorphTabGeometry.worstNearestEdgeDistance(
                tileWidth: MorphTabGeometry.tileWidthCap,
                tileHeight: MorphTabGeometry.tileHeight,
                gridSpacing: MorphTabGeometry.gridSpacing,
                columns: columns
            )
            #expect(worst.isFinite && worst > 0, "列数退化时距离必须有限且为正")
            #expect(MorphTabGeometry.containerSpacing(columns: columns) >= worst)
        }
    }

    @Test("间距单调性：网格间距增大 → 容器 spacing 同向增大（调参可预测，覆盖度不倒退）")
    func monotonicInGridSpacing() {
        #expect(MorphTabGeometry.containerSpacing(gridSpacing: 12) > MorphTabGeometry.containerSpacing(gridSpacing: 4))
    }

    @Test("覆盖度层级：全网格 spacing 严格大于仅相邻 spacing")
    func fullCoversAdjacent() {
        #expect(MorphTabGeometry.fullGridSpacing > MorphTabGeometry.adjacentSpacing())
    }
}

// MARK: - G2/F2 选中面材质：interactive 显式开启（官方原文 = 需 Add，非默认自带）

@Suite("G2 选中面材质解析")
struct SelectedGlassTests {
    @Test("选中面追加 interactive()，且与裸材质可区分（F2 确已落地）")
    func selectedFaceEnablesInteractive() {
        let base = Glass.regular
        #expect(GlassMorphTabBar.selectedGlass(from: base, isSelected: true) == base.interactive())
        #expect(GlassMorphTabBar.selectedGlass(from: base, isSelected: true) != base)
    }

    @Test("未选中面保持原样（不扩散玻璃/不加 interactive，避免全网格噪声）")
    func unselectedFaceKeepsGlassUnchanged() {
        let base = Glass.clear.tint(Color.orange)
        #expect(GlassMorphTabBar.selectedGlass(from: base, isSelected: false) == base)
    }

    @Test("主题 tint 与 interactive 叠加后 tint 不丢失（材质不因 F2 丢主题参数）")
    func tintSurvivesInteractiveComposition() {
        let themed = Glass.regular.tint(Color.purple)
        let result = GlassMorphTabBar.selectedGlass(from: themed, isSelected: true)
        #expect(result == themed.interactive())
        #expect(result != Glass.regular.interactive())
    }
}

// MARK: - D-1 实施判据（09-06）：常驻玻璃面数 == 分段数（静默口径，A 层可证）

@Suite("D-1 玻璃面数与身份（§3-A1 根因 GAP 的永久护栏）")
struct GlassFaceCoverageTests {
    /// 静默判据：native 态参与同一容器的玻璃面数**必须等于分段数**；
    /// 若退回到「仅选中面有玻璃」＝旧缺陷复发，本判据当场失败。
    @Test("native 面数 == segments.count；降级态零原生玻璃面（A14 保 solid 不变量）")
    func nativeFaceCoverageIsComplete() {
        #expect(GlassMorphTabBar.glassFaceCount(segmentCount: 6, isNative: true) == 6)
        #expect(GlassMorphTabBar.glassFaceCount(segmentCount: 6, isNative: false) == 0)
        for n in [1, 2, 5, 6, 12] {
            #expect(GlassMorphTabBar.glassFaceCount(segmentCount: n, isNative: true) == n)
        }
    }

    /// 身份：常驻面用逐段稳定 ID（互不相同 ⇒ 可被容器分别认得），选中面另用统一 morph 身份
    @Test("逐段 ID 互不相同且稳定，且不等于 selectionID")
    func tileFaceIDsAreStableAndDistinct() {
        let ids = (1 ... 6).map { GlassMorphTabBar.tileFaceID("tab" + String($0)) }
        #expect(Set(ids).count == 6)
        #expect(ids.first == GlassMorphTabBar.tileFaceID("tab1"))
        #expect(!ids.contains(GlassMorphTabBar.selectionID))
    }
}
