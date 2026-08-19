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
}
