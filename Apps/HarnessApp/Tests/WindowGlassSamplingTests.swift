import AppKit
@testable import HarnessApp
import Testing

// MARK: - D-10(a) 透明窗底装配（F4 折射源 · A 层进程内结构断言）

// 玻璃是否真实采到桌面（透窗实况）无静默像素通道（ImageRenderer 不渲染 glassEffect，
// BENCHMARK §4），裁决口径 = G3 A-d 目检（补记㊹）；本文件锁定 AppKit 层可证明的窗口配置事实。

@MainActor
@Suite("D-10(a) 透明窗底装配")
struct WindowGlassSamplingTests {
    /// applyGlassSampling 装配后：isOpaque=false + 背景 alpha=0；装配前默认态提供判别力（防"不改也过"）
    @Test("装配旗标生效且装配前默认态可区分")
    func applyConfiguresWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        // 装配前基线（NSWindow 文档默认：opaque；背景 nil 视为非 clear 基线）
        #expect(window.isOpaque)
        let alphaBefore = window.backgroundColor?.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1
        #expect(alphaBefore > 0)

        AppDelegate.applyGlassSampling(to: window)

        #expect(!window.isOpaque)
        let alphaAfter = window.backgroundColor?.usingColorSpace(.deviceRGB)?.alphaComponent
        #expect(alphaAfter == 0)
    }
}
