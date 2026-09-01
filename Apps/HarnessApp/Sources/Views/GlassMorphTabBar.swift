import SwiftUI

// MARK: - P1.2 Tab 分段 Morph 流动玻璃（目标 P1 §2 核心件）

//
// 原生 morph 机制（官方语义已核验，docs/P1_GLASS_API_VERIFICATION.md §六）：
//   选中玻璃面在切换时被移除/插入，同 @Namespace + 同 glassEffectID + 同 Glass 变体 + 同型 shape
//   → SwiftUI 原生把形状从旧分段位置动画到新分段位置（"animate shapes to and from each other during transitions"）
//   折射高光随玻璃本体连续移动 = 流体形变；❌ 禁 ZStack 滑块位移模拟（铁律 4）
// 降级链（P1.1 不变量）：reduceTransparency → solid 选中块（无 morph，对齐 P0 NavRow 基准）
// 快捷键口径（P1.2 起展开/折叠两态一致）：⌘N = 新对话（此前仅折叠 rail 注册，现展开态亦生效）；
// ⌘1–⌘5 = 五面板切换（展开态 ⌘1 原为「新对话」，P1.2 起与 rail 一致 = 切换到对话面板）
// 主题：Glass 从主题上下文解析（glassTintHex → tint，fallback .regular，P1.1 resolvedGlass 单点）

/// 分段定义（数据驱动；UI 代码不硬编码业务语义）
struct MorphTabSegment: Identifiable {
    enum Action: Hashable {
        /// 瞬时动作（无持久选中态，如「新对话」）
        case newChat
        /// tab 选择
        case select(AppTab)
    }

    let id: String
    let title: String
    let icon: String
    let action: Action
    /// 快捷键（nil = 不注册；修饰键固定 ⌘）
    var key: KeyEquivalent?
}

/// 六分区 Morph 玻璃切换容器：新对话（瞬时）+ 对话/多Agent/插件/技能/工具（tab 选中）
struct GlassMorphTabBar: View {
    let segments: [MorphTabSegment]
    let selectedID: String?
    let onSelect: (MorphTabSegment) -> Void

    @Environment(\.harnessThemeSpec) private var themeSpec
    /// morph namespace：同 namespace 同 ID 的玻璃面参与原生 morph
    @Namespace private var morphNS

    /// 3 列 × 2 行（侧边栏 260pt 宽下的可读布局）
    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    /// 统一选中 ID：切换时旧段移除/新段插入 → 触发原生 morph（官方文档语义）
    private static let selectionID = "harness-sidebar-selection"

    /// 分段面 shape（morph/union 官方约束：同变体 + 同型 shape）
    private static let tileShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// 系统「减弱透明度」环境键（与 GlassSurface 同源；true → 非 native，solid 选中块且无 morph）
    @Environment(\.accessibilityReduceTransparency) private var envReduceTransparency

    private var isNative: Bool {
        GlassSurfaceModifier.currentMode(envReduceTransparency: envReduceTransparency) == .native
    }

    var body: some View {
        // 主题玻璃单点解析（P1.1 纯函数；P1.4 主题插件 glassTintHex 实时生效）
        // P1.4：材质档位同走主题 manifest（resolvedGlass 单点；morph 同变体约束 = 分段间同 spec，不受影响）
        let glass = GlassSurfaceModifier.resolvedGlass(
            explicitTint: nil,
            themeTintHex: themeSpec.glassTintHex,
            themeMaterial: themeSpec.glassMaterial
        )
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(segments) { seg in
                segment(seg, glass: glass)
            }
        }
        // 同区域玻璃组同一容器（目标 P1 §1 光学采样一致；P1.1 修饰器，降级 no-op）
        .glassSurfaceContainer()
    }

    /// 分段面模式（纯函数，可单测）：选中 + native → 内容入玻璃（morph 面）；
    /// 选中 + 降级 → solid 块；未选中 → 素面（无玻璃）
    enum TileFaceMode {
        case glassMorph
        case solid
        case plain

        static func resolve(isSelected: Bool, isNative: Bool) -> TileFaceMode {
            guard isSelected else { return .plain }
            return isNative ? .glassMorph : .solid
        }
    }

    private func segment(_ seg: MorphTabSegment, glass: Glass) -> some View {
        let isSelected = seg.id == selectedID
        return Button {
            // 目标 P1 §2：状态切换包裹 withAnimation（morph 动画事务单一来源 = 本组件）
            withAnimation(.smooth(duration: 0.3)) {
                onSelect(seg)
            }
        } label: {
            tileContent(seg, isSelected: isSelected, glass: glass)
                .accessibilityLabel(seg.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .buttonStyle(.plain)
        .help(seg.title)
        .modifier(MorphTabKeyModifier(key: seg.key))
    }

    /// 分段面构造（2026-08-29 实机走查修复，截图 + 像素直方图证据入册）：
    /// 旧实现把 `Color.clear.glassEffect` 挂 `.background`（非标准构造）——macOS 27 beta 下
    /// 玻璃层合成在 tile 内容之上，选中 tile 图标/文字被折射采样洗淡不可见
    /// （证据：窗口截图 3x 放大空 tile + 内部像素直方图 min 亮度 118 = 内容在玻璃后）。
    /// 改官方文档模式：glassEffect 直接施加于内容 view
    /// （"Renders a shape anchored behind a view ... Applies the foreground effects of
    /// Liquid Glass over a view"，docs/P1_GLASS_API_VERIFICATION.md §六逐字在案）
    /// → 玻璃锚定内容 bounds，内容保持锐利（与 P1.1 composer / 项目卡同模式互证）。
    /// morph 不变量不变：同 glassEffectID + 同 @Namespace + 同 Glass 变体 + 同型 tileShape
    /// → 旧面移除 / 新面插入仍触发原生 morph 配对（官方 glassEffectID 语义在案）。
    @ViewBuilder
    private func tileContent(_ seg: MorphTabSegment, isSelected: Bool, glass: Glass) -> some View {
        let base = VStack(spacing: 3) {
            Image(systemName: seg.icon)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
            Text(seg.title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .contentShape(Self.tileShape)
        switch Self.TileFaceMode.resolve(isSelected: isSelected, isNative: isNative) {
        case .glassMorph:
            // 原生 morph 选中玻璃面：内容直接入玻璃（官方模式；悬停/按压反馈 = Glass.interactive 材质自带）
            base
                .glassEffect(glass, in: Self.tileShape)
                .glassEffectID(Self.selectionID, in: morphNS)
                .glassEffectTransition(.matchedGeometry)
        case .solid:
            // 降级（reduceTransparency）：solid 选中块，无 morph
            base.background(Self.tileShape.fill(HarnessTheme.sidebarHover))
        case .plain:
            base
        }
    }
}

/// 分段快捷键（⌘ + key；nil 不注册）
private struct MorphTabKeyModifier: ViewModifier {
    let key: KeyEquivalent?
    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - 侧边栏六分区数据（AppTab → 分段；设置由底栏齿轮承载，不进分段）

extension MorphTabSegment {
    /// 侧边栏默认六分区：新对话（瞬时，⌘N）+ 五个面板（⌘1–⌘5，与折叠 rail 一致）
    static let sidebarDefault: [MorphTabSegment] = [
        MorphTabSegment(id: "new-chat", title: "新对话", icon: "square.and.pencil", action: .newChat, key: "n"),
        MorphTabSegment(id: "chat", title: "对话", icon: AppTab.chat.icon, action: .select(.chat), key: "1"),
        MorphTabSegment(id: "agents", title: "多Agent", icon: AppTab.agents.icon, action: .select(.agents), key: "2"),
        MorphTabSegment(id: "plugins", title: "插件", icon: AppTab.plugins.icon, action: .select(.plugins), key: "3"),
        MorphTabSegment(id: "skills", title: "技能", icon: AppTab.skills.icon, action: .select(.skills), key: "4"),
        MorphTabSegment(id: "tools", title: "工具", icon: AppTab.tools.icon, action: .select(.tools), key: "5"),
    ]

    /// 当前选中 tab → 分段 id（.settings 无分段选中态，与 P0 导航行为一致）
    static func selectedID(for tab: AppTab) -> String? {
        switch tab {
        case .chat: "chat"
        case .agents: "agents"
        case .plugins: "plugins"
        case .skills: "skills"
        case .tools: "tools"
        case .settings: nil
        }
    }
}
