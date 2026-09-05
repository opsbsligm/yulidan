import AppKit
import SwiftUI

// MARK: - WWDC26 Liquid Glass 表面系统

//
// 三层策略（降级链）：
//   1. macOS 26+：原生 Liquid Glass（glassEffect / LiquidGlassEffectStyle）
//   2. macOS 15–25：NSVisualEffectView 材质近似（既有 VisualEffectMaterial）
//   3. 系统开启「减弱透明度」：纯色表面（无障碍，最高优先级，覆盖前两层）
//
// 动效：沿用全局 .smooth 动画体系，玻璃表面不引入独立动效；
// 无障碍：除减弱透明度降级外，玻璃表面保持完整对比度（文字始终走 textPrimary 等语义色）。

/// 玻璃**语义**层级（对应不同表面用途），⚠️ 非「玻璃厚度」——
/// HIG 明文材质变体＝regular/clear 两档（HIG Materials 原文在案
/// docs/BENCHMARK_CHECKLIST.md §1.9），不存在 thin/prominent 材质档。
/// ⚠️ SDK 签名层另有第三个静态成员 `Glass.identity`（编译期 26.5 SDK
/// `SwiftUICore.swiftinterface` L5753–5762 实测；HIG 未描述该值 ⇒ 非设计意义上的
/// 材质变体，详见 BENCHMARK §21.2 第 1 条）。
/// 本枚举在 macOS 26 **原生态下不改变 Glass**（三档同走
/// `resolvedGlass` 单点），仅在降级路径生效——legacy → NSVisualEffectView 材质（hudWindow/
/// popover/sidebar），solid → 三档不同实色。故命名口径 = 「用途分层」，勿理解为强度差异。
/// 待办 BENCHMARK_CHECKLIST A11：是否改名为 SurfaceRole 以彻底消除误导。
enum GlassLevel {
    /// 薄玻璃（语义）：气泡、内联行、chip —— 注：内容层元素按 HIG 宜用 Standard materials（A10）
    case thin
    /// 常规玻璃（语义）：面板、侧栏、卡片
    case regular
    /// 重玻璃（语义）：顶层浮层、设置面板
    case prominent
}

struct GlassSurfaceModifier: ViewModifier {
    var level: GlassLevel
    var cornerRadius: CGFloat
    var tint: Color?
    /// P1.3 morph 身份（需与 namespace 同用：同 namespace 同 ID → 原生 morph 配对，铁律 4 原生机制）
    var morphID: String?
    /// P1.3 morph namespace（提升共享给参与 morph 的多面，如侧边栏展开/折叠两面）
    var namespace: Namespace.ID?
    /// P1.3 玻璃过渡预设（.materialize = 弹窗出入场 / .matchedGeometry = morph / .identity = 无过渡）
    var transition: GlassEffectTransition?

    /// 当前激活主题（根视图注入；glassTintHex = 主题插件玻璃 tint，P1.1 起生效）
    @Environment(\.harnessThemeSpec) private var themeSpec

    /// 系统「减弱透明度」（SwiftUI 文档化可观察途径；true → solid 降级即时生效，无需重启）
    @Environment(\.accessibilityReduceTransparency) private var envReduceTransparency

    /// 渲染模式解析（纯函数，可单测）
    enum Mode {
        case solid // 无障碍降级：纯色
        case native // macOS 26+：原生 Liquid Glass
        case legacy // macOS 15–25：NSVisualEffectView 近似
    }

    static func resolveMode(osAtLeast26: Bool, reduceTransparency: Bool) -> Mode {
        if reduceTransparency {
            return .solid
        }
        if osAtLeast26 {
            return .native
        }
        return .legacy
    }

    /// 减弱透明度检测（测试可 override）
    static let reduceTransparencyOverride: LockedBox<Bool?> = .init(initial: nil)
    static var reduceTransparencyTestOverride: Bool? {
        get { reduceTransparencyOverride.withLock { $0 } }
        set { reduceTransparencyOverride.withLock { $0 = newValue } }
    }

    /// 减弱透明度合成（纯函数，可单测）：测试 override 最优先（保证用例隔离），
    /// 否则「SwiftUI 环境键 ∨ NSWorkspace 即时值」。环境键是 Apple 文档给出的**可观察**
    /// 读取途径（EnvironmentValues.accessibilityReduceTransparency，macOS 11+）；
    /// NSWorkspace 值只在 body 求值时被读到，本身不构成视图失效依赖。
    static func resolveReduceTransparency(override: Bool?, envReduceTransparency: Bool,
                                          workspaceFlag: Bool) -> Bool {
        override ?? (envReduceTransparency || workspaceFlag)
    }

    /// - Parameter envReduceTransparency: 视图侧传入的 `@Environment(\.accessibilityReduceTransparency)`。
    ///   传入即建立对系统开关的观察依赖：用户在「系统设置 › 辅助功能 › 显示」切换
    ///   「减弱透明度」时无需重启 App，视图被 SwiftUI 重新求值 → 即时降级 / 即时恢复。
    static func isReduceTransparency(envReduceTransparency: Bool = false) -> Bool {
        resolveReduceTransparency(
            override: reduceTransparencyTestOverride,
            envReduceTransparency: envReduceTransparency,
            workspaceFlag: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    static func currentMode(envReduceTransparency: Bool = false) -> Mode {
        resolveMode(
            osAtLeast26: {
                if #available(macOS 26.0, *) {
                    return true
                }
                return false
            }(),
            reduceTransparency: isReduceTransparency(envReduceTransparency: envReduceTransparency)
        )
    }

    /// 层级 → legacy 材质映射（纯函数，可单测）
    static func material(for level: GlassLevel) -> NSVisualEffectView.Material {
        switch level {
        case .thin: .hudWindow
        case .regular: .popover
        case .prominent: .sidebar
        }
    }

    /// P1.4 玻璃材质档位（manifest 值 → HIG 官方 Glass 变体；开放 regular/clear 两档，
    /// `Glass.identity` 不开放——HIG 未描述，见 BENCHMARK §21.2 第 1 条）
    enum GlassMaterial {
        case regular
        case clear
    }

    /// P1.4 纯函数：manifest 材质值 → 材质档位（宽容回落：nil/空/未知值 → .regular，
    /// 与 tint 回落同口径——主题参数缺失/异常不得破坏渲染，铁律：fallback .regular）
    static func resolveMaterial(_ raw: String?) -> GlassMaterial {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "clear": .clear
        default: .regular
        }
    }

    /// P1.4 材质档位展示文案（设置 UI 明示用；与渲染同一 resolveMaterial 单点，口径不漂移）
    static func materialLabel(glassMaterial: String?) -> String {
        switch resolveMaterial(glassMaterial) {
        case .regular: "标准（.regular）"
        case .clear: "透明（.clear）"
        }
    }

    /// P1.1/P1.4 玻璃解析（纯函数，可单测）：显式 tint > 主题 glassTintHex > 无 tint；
    /// 材质档位取自主题 manifest（P1.4 打通，fallback .regular；显式 tint 不覆盖档位）
    static func resolvedGlass(explicitTint: Color?, themeTintHex: String?, themeMaterial: String? = nil) -> Glass {
        let base: Glass = switch resolveMaterial(themeMaterial) {
        case .regular: .regular
        case .clear: .clear
        }
        let tint = explicitTint ?? Color(hex: themeTintHex)
        if let tint {
            return base.tint(tint)
        }
        return base
    }

    /// P1.3 morph/过渡配置解析（纯函数，可单测）
    /// 优先级：morph 配对（id + namespace）> 纯过渡（如 sheet materialize）> 无
    enum MorphConfig {
        case none
        case transitionOnly(GlassEffectTransition)
        case morphed(id: String, transition: GlassEffectTransition)
    }

    static func resolveMorph(
        morphID: String?,
        namespaceBound: Bool,
        transition: GlassEffectTransition?
    ) -> MorphConfig {
        if let morphID, namespaceBound {
            // morph 需要过渡描述（缺省 .matchedGeometry，与 P1.2 一致）
            return .morphed(id: morphID, transition: transition ?? .matchedGeometry)
        }
        if let transition {
            // 无完整 morph 配对（缺 id 或 namespace）→ 降级纯过渡（不产生假 morph）
            return .transitionOnly(transition)
        }
        return .none
    }

    private var material: NSVisualEffectView.Material {
        Self.material(for: level)
    }

    private var solidColor: Color {
        switch level {
        case .thin: HarnessTheme.glassLight
        case .regular: HarnessTheme.glassMedium
        case .prominent: HarnessTheme.glassDark
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// P1.3：原生玻璃面 + 可选 morph 身份/过渡（组合形态经 /tmp/glassprobe3.swift 编译探针实证）
    @MainActor
    @ViewBuilder
    private func nativeFace(content: some View, glass: Glass) -> some View {
        let base = content.glassEffect(glass, in: shape)
        switch Self.resolveMorph(morphID: morphID, namespaceBound: namespace != nil, transition: transition) {
        case .none:
            base
        case let .transitionOnly(t):
            base.glassEffectTransition(t)
        case let .morphed(id, t):
            // 防御分支：resolveMorph 已按 namespaceBound 门控，理论上 namespace 非 nil
            if let namespace {
                base.glassEffectID(id, in: namespace).glassEffectTransition(t)
            } else {
                base
            }
        }
    }

    func body(content: Content) -> some View {
        switch Self.currentMode(envReduceTransparency: envReduceTransparency) {
        case .solid:
            // 无障碍降级：纯色表面（保留 0.5pt 描边维持边界感）
            content
                .background(solidColor.opacity(0.95))
                .clipShape(shape)
                .overlay(shape.stroke(HarnessTheme.border, lineWidth: 0.5))
        case .native:
            // macOS 26+ 原生 Liquid Glass：内容区域整体成为玻璃表面
            // P1.1：tint 解析收敛为纯函数 resolvedGlass（显式 > 主题 > 无 tint，fallback 系统默认）
            // P1.3：morph 身份 / 过渡预设（降级模式 no-op = P1.1 不变量）
            if #available(macOS 26.0, *) {
                nativeFace(content: content, glass: Self.resolvedGlass(
                    explicitTint: tint,
                    themeTintHex: themeSpec.glassTintHex,
                    themeMaterial: themeSpec.glassMaterial
                ))
            } else {
                // 防御分支（mode 解析已按 OS 门控，理论上不可达）
                content.background(VisualEffectMaterial(material: material, blendingMode: .behindWindow))
            }
        case .legacy:
            // macOS 15–25：NSVisualEffectView 近似（材质背景 + 形状裁剪）
            content
                .background(VisualEffectMaterial(material: material, blendingMode: .behindWindow))
                .clipShape(shape)
        }
    }
}

// MARK: - View 扩展

extension View {
    /// WWDC26 Liquid Glass 表面（自动降级 + 无障碍）
    /// P1.3：morphID/namespace/transition 可选 — morph 配对（侧边栏展开折叠/项目卡）与弹窗出入场（.materialize）；
    /// 降级模式（solid/legacy）三参数 no-op（无障碍降级行为不变的 P1.1 不变量）
    func glassSurface(
        _ level: GlassLevel = .regular,
        cornerRadius: CGFloat = HarnessTheme.radiusLarge,
        tint: Color? = nil,
        morphID: String? = nil,
        namespace: Namespace.ID? = nil,
        transition: GlassEffectTransition? = nil
    ) -> some View {
        modifier(GlassSurfaceModifier(
            level: level,
            cornerRadius: cornerRadius,
            tint: tint,
            morphID: morphID,
            namespace: namespace,
            transition: transition
        ))
    }
}

// MARK: - P1.1 同区域玻璃容器（GlassEffectContainer 容器化）

/// 同区域玻璃表面容器：同一区域内的多个玻璃表面放入同一 `GlassEffectContainer`
/// → 光学采样一致 + 渲染性能（官方：union 三同后合并为单一 shape ＋ 容器内可相互 blend/morph，
///   union 三同条件见 §19.1-3、容器价值句见 §1.8 逐字在案）；
/// 降级模式（solid/legacy）no-op 不包裹（容器为 macOS 26+ API）。
struct GlassSurfaceContainerModifier: ViewModifier {
    /// 融合提前量（官方：spacing 越大越早融合，§19.1-1 逐字在案）；nil = 系统默认
    var spacing: CGFloat?

    /// 系统「减弱透明度」：与 GlassSurfaceModifier 同源，保证容器与表面的降级判定一致且即时
    @Environment(\.accessibilityReduceTransparency) private var envReduceTransparency

    /// 是否真正包裹容器（纯函数，可单测）：仅 native 模式包裹
    static func shouldWrap(_ mode: GlassSurfaceModifier.Mode) -> Bool {
        mode == .native
    }

    func body(content: Content) -> some View {
        if Self.shouldWrap(GlassSurfaceModifier.currentMode(envReduceTransparency: envReduceTransparency)), #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    /// P1.1 同区域玻璃容器化（包裹 GlassEffectContainer；降级模式 no-op）
    /// spacing 为布局级调参（融合提前量），非材质参数 → 不进 ThemeSpec
    func glassSurfaceContainer(spacing: CGFloat? = nil) -> some View {
        modifier(GlassSurfaceContainerModifier(spacing: spacing))
    }
}

// MARK: - 测试辅助（同进程内测试目标可见）

/// 简单锁箱（测试 hook 用；与测试目标的 Noop 风格一致）
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(initial: Value) {
        value = initial
    }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
