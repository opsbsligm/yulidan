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

    @Test("TileFaceMode：选中+native→玻璃面 / 选中+降级→solid / **未选中共素面**（三态不变量）")
    func tileFaceModeResolve() {
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: true, isNative: true) == .glassBase)
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: true, isNative: false) == .solid)
        // ⁽⁰⁹⁻⁰⁷ᵉ⁾ 09-07 用户目检（G3 A-a）判「六面融成一整片、内容被洗淡」⇒ 未选中恢复素面。
        // 本行是**反向护栏**：谁再把未选中也铺上常驻玻璃面，这里先红，且必须先拿出观感证据才能改判据。
        #expect(GlassMorphTabBar.TileFaceMode.resolve(isSelected: false, isNative: true) == .plain)
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

@Suite("D-1 玻璃面数（09-07 观感证据锁死的上限）")
struct GlassFaceCoverageTests {
    /// 静默判据：native 态容器内玻璃面数**固定为 1（仅选中段）**；降级态 0。
    ///
    /// **这条判据的方向和 09-06 那版正好相反，理由是用眼见证据改的**：09-06 曾把未选中段也铺上
    /// 常驻面（=segmentCount），结构判据全绿，但 09-07 用户实机目检结论＝「整片融成一块橙色玻璃、
    /// 图标与文字被洗淡」⇒ 铺满方案回退。⇒ 本判据现在钉的是**上限**：任何人再用「铺满」去填
    /// morph 的第二面缺口（§3-A1），这里先红；要改判据必须同时提交**观感证据**（截图/像素直方图
    /// 或用户目检通过记录），不接受只拿结构测试放行（铁律 6 的可证边界）。
    @Test("native 面数 == 1（仅选中面）；降级态 0；**铺满＝违反本判据**")
    func nativeFaceCountIsCappedAtSelection() {
        #expect(GlassMorphTabBar.glassFaceCount(segmentCount: 6, isNative: true) == 1)
        #expect(GlassMorphTabBar.glassFaceCount(segmentCount: 6, isNative: false) == 0)
        for n in [1, 2, 5, 6, 12] {
            #expect(GlassMorphTabBar.glassFaceCount(segmentCount: n, isNative: true) == 1)
        }
    }
}
