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
//
// G2 打磨轮 F1/F2（2026-09-03，官方判据纠偏，docs/BENCHMARK_CHECKLIST.md §1.8-1.10 逐字在案）：
// 官方《Applying Liquid Glass to custom views》原文：
//   morph 触发条件 = "For effects you want to add or remove that are **positioned within the
//     container's assigned spacing**, the default transition type is matchedGeometry"；
//     超出该距离须用 .materialize（"farther from each other than the container's assigned spacing"）
//   判据尺寸 = 最近边："morphs ... when the eraser's **nearest edge is less than or equal to the
//     container's spacing**"
//   "Animating views in or out causes the shapes to **morph apart or together as the space in the
//     container changes**." → 我们的「移除旧选中面 + 插入新选中面」**符合官方描述的 morph
// 触发方式**（＝我方解读：官方示例 §18.2 给的是其中一种构造，非唯一规定）⇒ 无需补面
//   spacing 过大的唯一代价 = "causes Liquid Glass effects to **blend together at rest** because the
//     views are too close"；本容器静止态恒 1 面 → 该代价结构性不可达 → 放心取覆盖全网格的值
//   interactive = **显式开启**："**Add** interactive(_:) to custom components to make them react to
//     touch and pointer interactions"（旧注释「材质自带」属未证实宣称，本轮纠偏 → 见 F2）
// 上一轮 A1「需给未选中面补玻璃」的推断已撤销：官方原文说明 add/remove 本身即触发
// morph（上方逐字引文）⇒ 补面并非必要。⚠️ 而「补面会制造静止态融合与噪声」是**我方
// 推论**（据官方 at-rest 告警推出，原文见 §19.1 第 2 句），非官方明文（§21.2 第 6 条）。

/// Morph 几何判据（纯函数，可单测；F1 核心）
///
/// 官方判据（逐字见档 §1.8）：add/remove 的两个玻璃面「最近边 ≤ 容器 spacing」才走 matchedGeometry
/// morph，超出则须 materialize。故容器 spacing 必须覆盖本网格内**最坏最近边距离**，
/// 否则远距离切换（隔一列 / 跨行）静默退回淡变 —— 这正是 P1.2 实机「交叉淡变」的根因。
enum MorphTabGeometry {
    /// 单格宽度保守上界：侧栏固定 260pt − 内容内边距 10~14pt，3 列 − 网格间距 → 实测 ≤76pt，
    /// 取 80pt 上界（偏大只会让更多面落入 morph 适用域；静止态单面 → 融合代价不可达）
    static let tileWidthCap: CGFloat = 80
    /// 单格高度（与 tileContent 的 frame(height:) 同源）
    static let tileHeight: CGFloat = 46
    /// 网格间距（列/行同值）
    static let gridSpacing: CGFloat = 6
    /// 列数
    static let columns: Int = 3

    /// 最坏「最近边」距离：跨 2 列 + 跨 1 行的两个玻璃面（本网格内距离最大的一对）
    /// 水平净距 = 2×网格间距 + 一个面宽；垂直净距 = 1×网格间距；取欧氏距离（对「最近边」的保守上界）
    static func worstNearestEdgeDistance(
        tileWidth: CGFloat,
        tileHeight _: CGFloat,
        gridSpacing: CGFloat,
        columns: Int
    ) -> CGFloat {
        let stepsAcross = min(2, max(columns - 1, 0))
        let horizontal = gridSpacing * CGFloat(stepsAcross + 1) + tileWidth * CGFloat(stepsAcross)
        let vertical = gridSpacing
        return (horizontal * horizontal + vertical * vertical).squareRoot()
    }

    /// 容器 spacing = 最坏最近边距离向上取整。官方判据为「最近边 ≤ 容器 spacing」（逐字见
    /// §1.8）；⚠️「取整即覆盖全部切换距离」＝**我方保守取整**，非官方承诺（§21.2 第 8 条）
    static func containerSpacing(
        tileWidth: CGFloat = tileWidthCap,
        tileHeight: CGFloat = tileHeight,
        gridSpacing: CGFloat = gridSpacing,
        columns: Int = columns
    ) -> CGFloat {
        worstNearestEdgeDistance(
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            gridSpacing: gridSpacing,
            columns: columns
        ).rounded(.up)
    }

    /// 全网格统一值（单一事实源：容器与判据同源，避免调参漂移）
    static var fullGridSpacing: CGFloat {
        containerSpacing()
    }

    /// 局部网格值：仅要求覆盖「相邻面」距离 —— 供需要收敛 spacing（例如担心跨面过度融合）时使用
    static func adjacentSpacing(
        tileHeight: CGFloat = tileHeight,
        gridSpacing: CGFloat = gridSpacing
    ) -> CGFloat {
        max(tileHeight, gridSpacing) + gridSpacing
    }

    /// 判定：某对面距离是否落在 matchedGeometry 适用域（官方：最近边 ≤ 容器 spacing，§1.8 逐字）
    static func qualifiesForMatchedGeometry(
        nearestEdgeDistance: CGFloat,
        containerSpacing: CGFloat
    ) -> Bool {
        nearestEdgeDistance <= containerSpacing
    }
}

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
    /// 单一 ID ＝**我方构造**：官方对 ID 的明文只到「保证同一个 shape 在**层级增删**时被正确
    /// 动画」（§19.1 第 3 句逐字），**未**明文「同 ID 面位移即形变」；官方示例反而是常驻面＋
    /// 条件面**不同 ID**（§18.2）⇒ 本构造的流体观感待目检，不得当作官方结论引用。
    /// ❌ 不得改为每段一个 ID —— 我方预测（**未实测**）：会退化成官方示例那种
    /// 「A 面消亡 + B 面新生」双胶囊形态（§21.2 第 4/5 条）
    /// ⚠️ `nonisolated`：一枚纯字符串常量，无 MainActor 需求；面数/身份护栏测试须在非隔离
    /// 上下文引用它（Swift 6 下 MainActor 隔离的静态量在 nonisolated 测试里不可见）。
    nonisolated static let selectionID = "harness-sidebar-selection"

    /// 分段面 shape。union 官方三同＝similar shape / Liquid Glass effect / **and ID**（§1.8 逐字）；
    /// morph 判据是另一件事＝最近边 ≤ 容器 spacing ⇒ 两套机制各自成立，勿合并引用（§21.2 第 3 条）
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
        // D-15(b) 09-06：spacing 由全网格量级（≈179）收敛到**相邻量级** `adjacentSpacing()`（=52）。
        // 依据（BENCHMARK §19 逐字原文）：容器 spacing 大于内部布局容器 spacing 时，
        //   Liquid Glass 效应会 "blend together at **rest**" ⇒ 179 量级下静止态必然过度融合。
        // 先例（BENCHMARK §18.2 F-b 官方示例）：容器 spacing 与内部布局 spacing 取同值（10.0 : 10.0）。
        // 代价（明示，我方取舍）：跨多格的远距离切换不再保证落在 morph 适用域，改走系统默认过渡；
        //   静止态过度融合是 §19 原文的必然结果，远距淡变只是少一个加成，非新增缺陷。
        // 降级态（solid/legacy）容器本身不包裹 → spacing 参数在该路径无消费方，保持 nil 不变
        .glassSurfaceContainer(spacing: isNative ? MorphTabGeometry.fullGridSpacing : nil)
        // ⁽⁰⁹⁻⁰⁷ᵉ⁾ D-15(b) 的 spacing=52 随 D-1「铺满常驻面」一并回退：只剩选中面时收敛 spacing
        // 没有配对收益，却保留官方明文的「blend together at rest」融合副作用（锚点 §19.1-1；09-07 用户目检＝整格融成一整片）。
    }

    /// 分段面模式（纯函数，可单测）：选中 + native → 内容入玻璃（morph 面）；
    /// 选中 + 降级 → solid 块；未选中 → 素面（无玻璃）。⁽⁰⁹⁻⁰⁷ᵉ⁾ 09-07 目检回退后恢复此三态口径。
    enum TileFaceMode {
        case glassBase
        case solid
        case plain

        static func resolve(isSelected: Bool, isNative: Bool) -> TileFaceMode {
            // ⁽⁰⁹⁻⁰⁷ᵉ⁾ 用户 09-07 目检（G3 A-a）判「整片融成一块橙色玻璃、内容被洗淡」＝不通过 ⇒
            // 回退「常驻面铺满全部分段」，恢复仅选中段带面。morph 缺第二面（§3-A1 根因 GAP）随本回退
            // 回到在册未决状态；**观感证据优先于结构判据**（铁律 6 的可证边界：结构判据成立≠观感成立）。
            guard isSelected else { return .plain }
            return isNative ? .glassBase : .solid
        }
    }

    /// native 态参与同一 `GlassEffectContainer` 的玻璃面数（A12 口径的机器判据）：
    /// 降级态无原生玻璃面（solid/plain 走纯色/素面）⇒ 0；native 态**仅选中段一面** ⇒ 1。
    /// ⁽⁰⁹⁻⁰⁷ᵉ⁾ 09-07 目检回退：曾短暂改为 `segmentCount`（铺满常驻面）以给 morph 配对第二面，
    /// 实测后果＝六面在容器内融成一整片玻璃并洗淡 tile 内容（用户截图为证）⇒ 判据回到 1，
    /// 「morph 需要第二面」这一结构缺口重新挂回在册（§3-A1），**不再用铺满去填**。
    nonisolated static func glassFaceCount(segmentCount _: Int, isNative: Bool) -> Int {
        isNative ? 1 : 0
    }

    /// 选中面材质解析（纯函数，可单测）：选中 → 追加 `.interactive()`（F2 显式开启指针反馈）；
    /// 未选中 → 原样。**09-06 D-1 实施后本函数成为全部玻璃面的材质单点**（未选中＝主题档位材质、
    /// 不加 interactive，守 HIG「sparingly」并避免全网格指针反馈噪声）
    nonisolated static func selectedGlass(from glass: Glass, isSelected: Bool) -> Glass {
        isSelected ? glass.interactive() : glass
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
    /// 改按官方模式：glassEffect 直接施加于内容 view（锚点＝下方逐字引文，另见 §1.8
    /// 「Apply the `glassEffect(_:in:)` modifier after other modifiers…」）
    /// （"Renders a shape anchored behind a view ... Applies the foreground effects of
    /// Liquid Glass over a view"，docs/P1_GLASS_API_VERIFICATION.md §六逐字在案）
    /// → 玻璃锚定内容 bounds，内容保持锐利（与 P1.1 composer / 项目卡同模式互证）。
    /// morph 不变量不变：同 glassEffectID + 同 @Namespace + 同 Glass 变体 + 同型 tileShape
    /// → 旧面移除 / 新面插入按官方口径处理（同 ID 保证形状增删时正确动画，§19.1-3）；
    ///   「位移即流体融合」＝我方构造，实况待 D-1 终裁（与上方 §21.2 第 4 条同口径）。
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
        case .glassBase:
            // 原生 morph 选中玻璃面：内容直接入玻璃（官方容器内语义＝each view … renders with
            // the effects behind it，逐字见 §21.5 第 3 句）
            // F2：interactive 须**显式添加**（官方原文 "Add interactive(_:) to custom components
            // to make them react to touch and pointer interactions"）——旧注释称「材质自带」无依据，
            // 已撤销；本面为导航功能层自定义件，符合 HIG「sparingly」边界（仅选中面加）
            // ⁽⁰⁹⁻⁰⁷ᵉ⁾ 09-06 D-1 曾实施「铺满全部分段」，09-07 用户目检不通过 ⇒ 已回退为仅选中面
            // （本分支只在 isSelected 时到达，见 TileFaceMode.resolve）。回退理由与证据见 glassFaceCount 注释。
            base
                .glassEffect(Self.selectedGlass(from: glass, isSelected: true), in: Self.tileShape)
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
