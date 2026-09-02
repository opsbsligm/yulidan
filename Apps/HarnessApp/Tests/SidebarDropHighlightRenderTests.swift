import AppKit
@testable import HarnessApp
import SwiftUI
import Testing

// MARK: - 拖拽落点悬停高亮·离屏渲染验证（R1 §10.3 #7 规则内核；锁屏/无显示器可跑）

/// 锁定 SidebarProjectSections.dropTargetFill 规则：
/// 非悬停=纯白（无高亮）；悬停=accent 着色且 项目头(0.14) 强度 > 全局区(0.06)。
/// 断言用「相对白底的偏离序」，对 accent 具体色值/色彩空间鲁棒（教训沿用 ThemeLiveRenderTests）。
/// 真机拖拽手势联动（targetedDrop 状态注入路径）仍归真机走测补证。
@MainActor
@Suite("拖拽落点高亮（离屏渲染）", .serialized)
struct SidebarDropHighlightRenderTests {
    /// 探针：白底 + 落点填充色满铺（采样中心必命中）
    private struct Probe: View {
        let zone: SidebarProjectSections.DropZone
        let targeted: Bool
        var body: some View {
            ZStack {
                Color.white
                SidebarProjectSections.dropTargetFill(zone, targeted: targeted)
            }
            .frame(width: 64, height: 64)
        }
    }

    private func renderProbe(_ zone: SidebarProjectSections.DropZone, _ targeted: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let renderer = ImageRenderer(content: Probe(zone: zone, targeted: targeted))
        renderer.scale = 1
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              rep.pixelsWide > 0 else {
            Issue.record("ImageRenderer 离屏渲染失败")
            return (0, 0, 0)
        }
        let raw = rep.colorAt(x: 32, y: 32) ?? .black
        let c = raw.usingColorSpace(.sRGB) ?? raw
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    /// 偏离白底的欧氏距离（accent≠白时悬停必然 >0）
    private func distFromWhite(_ p: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        (pow(1 - p.r, 2) + pow(1 - p.g, 2) + pow(1 - p.b, 2)).squareRoot()
    }

    @Test("非悬停无高亮；悬停两级着色且项目头 > 全局区")
    func hoverHighlightTwoLevels() {
        let headerOff = renderProbe(.projectHeader, false)
        #expect(distFromWhite(headerOff) < 0.02, "非悬停应无填充（纯白），实测 \(headerOff)")

        let globalOff = renderProbe(.globalList, false)
        #expect(distFromWhite(globalOff) < 0.02, "非悬停应无填充（纯白），实测 \(globalOff)")

        let headerOn = renderProbe(.projectHeader, true)
        let globalOn = renderProbe(.globalList, true)
        let dHeader = distFromWhite(headerOn)
        let dGlobal = distFromWhite(globalOn)
        #expect(dHeader > 0.05, "项目头悬停应有可见 accent 高亮，实测偏离 \(dHeader)")
        #expect(dGlobal > 0.02, "全局区悬停应有可见 accent 高亮，实测偏离 \(dGlobal)")
        // 同色同底混合强度与 opacity 线性：0.14 与 0.06 的比例关系（容差 30%）
        #expect(dHeader > dGlobal, "项目头高亮(0.14)必须强于全局区(0.06)")
        let ratio = dHeader / dGlobal
        #expect(ratio > 1.6 && ratio < 2.5, "0.14/0.06≈2.33 的强度比例，实测 \(ratio)")
    }
}
