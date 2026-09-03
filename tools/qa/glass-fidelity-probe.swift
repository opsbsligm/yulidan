//
//  glass-fidelity-probe.swift — Liquid Glass 离屏渲染保真度探针（静默 A 层）
//
//  用途：判定「ImageRenderer 离屏渲染能否作为 Liquid Glass / morph 的像素判据」。
//  结论（2026-09-03 本机 macOS 27.0 / Xcode 26.6 SDK 实测）：**不能** ——
//  同布局「有玻璃 vs 无玻璃」两张位图 24000 像素逐点完全一致（差异 0），
//  即 ImageRenderer 不合成 glassEffect（与既有 ThemeLiveRenderTests 注释
//  「系统玻璃折射仍归真机抽样」互证）。任何以 ImageRenderer 像素判定玻璃效果的
//  宣称均不成立 → 见 docs/BENCHMARK_CHECKLIST.md 取证通道能力表。
//
//  静默性（铁律 8）：纯进程内位图渲染，零窗口 / 零激活 / 零键鼠 / 锁屏可跑。
//
//  编译运行（必须用 Xcode 内 SDK；xcrun 默认指向 CommandLineTools 旧 SDK 无 Glass API）：
//    SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
//    swiftc -sdk "$SDK" -target arm64-apple-macos26.0 -O tools/qa/glass-fidelity-probe.swift -o /tmp/glass-fidelity-probe
//    /tmp/glass-fidelity-probe
//

import AppKit
import SwiftUI

// MARK: - 被测视图

/// 高信息量背景（渐变 + 白点阵）：玻璃若被合成，折射/采样必然改变像素
private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.red, .green, .blue], startPoint: .top, endPoint: .bottom)
            ForEach(0 ..< 12, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 18, height: 18)
                    .offset(x: CGFloat(index % 4) * 44 - 66, y: CGFloat(index / 4) * 34 - 34)
            }
        }
        .frame(width: 200, height: 120)
    }
}

/// 有玻璃：两个相邻玻璃面放入同一容器（容器 spacing / 面间隙作为对照组）
private struct WithGlass: View {
    let containerSpacing: CGFloat
    let faceGap: CGFloat

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Backdrop().overlay(
            GlassEffectContainer(spacing: containerSpacing) {
                HStack(spacing: faceGap) {
                    ForEach(0 ..< 2, id: \.self) { _ in
                        Color.clear
                            .frame(width: 60, height: 40)
                            .glassEffect(.regular, in: shape)
                    }
                }
            }
        )
    }
}

/// 无玻璃控制组：布局完全一致，仅不含 glassEffect
private struct WithoutGlass: View {
    let faceGap: CGFloat

    var body: some View {
        Backdrop().overlay(
            HStack(spacing: faceGap) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    Color.clear.frame(width: 60, height: 40)
                }
            }
        )
    }
}

// MARK: - 渲染与比对

@MainActor
private func render(_ view: some View) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1 // 像素与点一一对应，避免倍率放大掩盖差异
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          rep.pixelsWide > 1 else {
        return nil
    }
    return rep
}

/// 逐点比对两张同尺寸位图，返回不一致像素数
private func differingPixels(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return .max }
    var count = 0
    for x in 0 ..< lhs.pixelsWide {
        for y in 0 ..< lhs.pixelsHigh where lhs.colorAt(x: x, y: y) != rhs.colorAt(x: x, y: y) {
            count += 1
        }
    }
    return count
}

@MainActor
private func probe(containerSpacing: CGFloat, faceGap: CGFloat) {
    guard let glass = render(WithGlass(containerSpacing: containerSpacing, faceGap: faceGap)),
          let plain = render(WithoutGlass(faceGap: faceGap)) else {
        print("spacing=\(containerSpacing) gap=\(faceGap): 渲染失败")
        return
    }
    let diff = differingPixels(glass, plain)
    let total = glass.pixelsWide * glass.pixelsHigh
    let verdict = diff == 0 ? "玻璃不可见（离屏无玻璃像素）" : "玻璃可见（差异 \(diff) 像素）"
    print("spacing=\(containerSpacing) gap=\(faceGap): 差异 \(diff)/\(total) → \(verdict)")
}

@MainActor
private func run() {
    print("== ImageRenderer × Liquid Glass 保真度探针 ==")
    // 多组 spacing/间隙：覆盖「融合提前量」可能的取值区间
    probe(containerSpacing: 10, faceGap: 8)
    probe(containerSpacing: 30, faceGap: 10)
    probe(containerSpacing: 60, faceGap: 40)
    print("判据：全部差异 0 → ImageRenderer 不能作为玻璃/morph 像素判据（证据通道需按 BENCHMARK_CHECKLIST 重定义）")
}

await MainActor.run { run() }
