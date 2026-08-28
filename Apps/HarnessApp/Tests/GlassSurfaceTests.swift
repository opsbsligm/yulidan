import AppKit
@testable import HarnessApp
import Testing

// MARK: - GlassSurface 表面系统（resolveMode 降级链纯函数 / override 钩子 / 材质映射）

@MainActor
@Suite("GlassSurface 表面系统", .serialized)
struct GlassSurfaceTests {
    @Test("resolveMode 矩阵：减弱透明度最高优先级，其次原生，最后 legacy")
    func resolveModeMatrix() {
        // (osAtLeast26, reduceTransparency) → Mode
        #expect(GlassSurfaceModifier.resolveMode(osAtLeast26: true, reduceTransparency: true) == .solid)
        #expect(GlassSurfaceModifier.resolveMode(osAtLeast26: true, reduceTransparency: false) == .native)
        #expect(GlassSurfaceModifier.resolveMode(osAtLeast26: false, reduceTransparency: true) == .solid)
        #expect(GlassSurfaceModifier.resolveMode(osAtLeast26: false, reduceTransparency: false) == .legacy)
    }

    @Test("override=true 时 currentMode 恒降级 solid（无障碍优先于 OS 能力）")
    func overrideForcesSolid() {
        GlassSurfaceModifier.reduceTransparencyTestOverride = true
        defer { GlassSurfaceModifier.reduceTransparencyTestOverride = nil }
        #expect(GlassSurfaceModifier.currentMode() == .solid)
    }

    @Test("override=false 时 currentMode 按 OS 能力返回 native(26+)/legacy(<26)")
    func overrideResolvesByOS() {
        GlassSurfaceModifier.reduceTransparencyTestOverride = false
        defer { GlassSurfaceModifier.reduceTransparencyTestOverride = nil }
        let expected: GlassSurfaceModifier.Mode = if #available(macOS 26.0, *) {
            .native
        } else {
            .legacy
        }
        #expect(GlassSurfaceModifier.currentMode() == expected)
    }

    @Test("level → legacy 材质映射（thin→hudWindow / regular→popover / prominent→sidebar）")
    func materialMapping() {
        #expect(GlassSurfaceModifier.material(for: .thin) == .hudWindow)
        #expect(GlassSurfaceModifier.material(for: .regular) == .popover)
        #expect(GlassSurfaceModifier.material(for: .prominent) == .sidebar)
    }

    // MARK: - P1.1 主题玻璃解析（resolvedGlass 纯函数）

    @Test("resolvedGlass：无显式无主题 → .regular（系统默认 fallback）")
    func resolvedGlassNoTint() {
        #expect(GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: nil) == .regular)
    }

    @Test("resolvedGlass：主题 hex 非法/空 → .regular（解析失败回落，不抛错）")
    func resolvedGlassInvalidHex() {
        #expect(GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: "not-a-hex") == .regular)
        #expect(GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: "0A84FF") == .regular)
        #expect(GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: "#12345") == .regular)
    }

    @Test("resolvedGlass：合法主题 hex → tinted 玻璃（区别于无 tint 基准）")
    func resolvedGlassThemeTint() {
        #expect(GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: "#0A84FF") != .regular)
        #expect(GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: "#11223344") != .regular)
    }

    @Test("resolvedGlass：显式 tint 优先级高于主题 tint")
    func resolvedGlassExplicitWins() {
        let explicit = GlassSurfaceModifier.resolvedGlass(explicitTint: .red, themeTintHex: "#00FF00")
        let themed = GlassSurfaceModifier.resolvedGlass(explicitTint: nil, themeTintHex: "#00FF00")
        #expect(explicit != themed)
    }

    // MARK: - P1.1 容器包裹决策（shouldWrap 纯函数）

    @Test("容器包裹决策：仅 native 模式包裹，solid/legacy 降级 no-op")
    func containerWrapDecision() {
        #expect(GlassSurfaceContainerModifier.shouldWrap(.native))
        #expect(!GlassSurfaceContainerModifier.shouldWrap(.solid))
        #expect(!GlassSurfaceContainerModifier.shouldWrap(.legacy))
    }

    // MARK: - P1.3 morph/过渡配置解析（resolveMorph 纯函数）

    @Test("resolveMorph：id + namespace 齐备 → morphed（过渡缺省 .matchedGeometry，与 P1.2 一致）")
    func resolveMorphPairDefaultTransition() {
        guard case let .morphed(id, _) = GlassSurfaceModifier.resolveMorph(
            morphID: "harness-sidebar-collapse", namespaceBound: true, transition: nil
        ) else {
            Issue.record("expected .morphed")
            return
        }
        #expect(id == "harness-sidebar-collapse")
    }

    @Test("resolveMorph：显式过渡优先于缺省（弹窗 .materialize 出入场）")
    func resolveMorphExplicitTransition() {
        guard case .morphed = GlassSurfaceModifier.resolveMorph(
            morphID: "x", namespaceBound: true, transition: .materialize
        ) else {
            Issue.record("expected .morphed")
            return
        }
    }

    @Test("resolveMorph：缺 id 或 namespace → 降级 transitionOnly（不产生假 morph 配对）")
    func resolveMorphDegradeToTransition() {
        let missingID = GlassSurfaceModifier.resolveMorph(morphID: nil, namespaceBound: true, transition: .materialize)
        let missingNamespace = GlassSurfaceModifier.resolveMorph(morphID: "x", namespaceBound: false, transition: .materialize)
        guard case .transitionOnly = missingID, case .transitionOnly = missingNamespace else {
            Issue.record("expected .transitionOnly")
            return
        }
    }

    @Test("resolveMorph：三参全缺 → none（与既有 glassSurface 行为零差异）")
    func resolveMorphNone() {
        guard case .none = GlassSurfaceModifier.resolveMorph(
            morphID: nil, namespaceBound: false, transition: nil
        ) else {
            Issue.record("expected .none")
            return
        }
    }
}
