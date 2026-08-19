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

/// 玻璃强度层级（对应不同表面语义）
enum GlassLevel {
    /// 薄玻璃：气泡、内联行、chip
    case thin
    /// 常规玻璃：面板、侧栏、卡片
    case regular
    /// 重玻璃：顶层浮层、设置面板
    case prominent
}

struct GlassSurfaceModifier: ViewModifier {
    var level: GlassLevel
    var cornerRadius: CGFloat
    var tint: Color?

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

    static func isReduceTransparency() -> Bool {
        if let override = reduceTransparencyTestOverride {
            return override
        }
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static func currentMode() -> Mode {
        resolveMode(
            osAtLeast26: {
                if #available(macOS 26.0, *) {
                    return true
                }
                return false
            }(),
            reduceTransparency: isReduceTransparency()
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

    func body(content: Content) -> some View {
        switch Self.currentMode() {
        case .solid:
            // 无障碍降级：纯色表面（保留 0.5pt 描边维持边界感）
            content
                .background(solidColor.opacity(0.95))
                .clipShape(shape)
                .overlay(shape.stroke(HarnessTheme.border, lineWidth: 0.5))
        case .native:
            // macOS 26+ 原生 Liquid Glass：内容区域整体成为玻璃表面
            if #available(macOS 26.0, *) {
                if let tint {
                    content.glassEffect(.regular.tint(tint), in: shape)
                } else {
                    content.glassEffect(.regular, in: shape)
                }
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
    func glassSurface(
        _ level: GlassLevel = .regular,
        cornerRadius: CGFloat = HarnessTheme.radiusLarge,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassSurfaceModifier(level: level, cornerRadius: cornerRadius, tint: tint))
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
