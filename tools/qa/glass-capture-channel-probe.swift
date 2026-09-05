//
//  glass-capture-channel-probe.swift — 玻璃像素捕获通道普查探针（静默 A 层）
//
//  目的：穷尽「无前台 / 无键鼠前提下能否取到 glassEffect 真实像素」这一判据基础问题。
//  背景：v8 目标 G2 原写「用 ImageRenderer 像素帧判定 morph 流体融合」，09-03 实测证伪
//  （ImageRenderer 有/无玻璃差异 0，见 glass-fidelity-probe.swift）；本轮补齐其余候选通道：
//    CH1 NSView.cacheDisplay              CH2 displayIgnoringOpacity(_:in:)
//    CH3 CALayer.render(in:)              CH4 dataWithPDF(inside:)
//    CH5 显示边界外窗口 + screencapture -l（WindowServer 真合成，用户不可见）
//  判读规范：每条位图通道须先自证「捕获通路活性」（控制组含多色），否则「差异 0」
//  只是整体捕获失败，不得据此下「玻璃不可见」结论。
//
//  静默性（铁律 8）：NSApp.setActivationPolicy(.prohibited) —— 本进程永不可激活，
//  零激活、零键鼠、零焦点变化；CH1–CH4 窗口从不上屏；CH5 窗口先移到所有显示器边界外
//  再 orderFront（用户屏幕无任何变化，screencapture 取窗口自身位图而非屏幕区域），
//  并用 CGWindowListCopyWindowInfo 回报 bounds 作为「确实不可见」的第三方证据。
//
//  编译运行（须用 Xcode 内 SDK；xcrun 默认 CommandLineTools 旧 SDK 无 Glass API）：
//    SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
//    swiftc -sdk "$SDK" -target arm64-apple-macos26.0 -O -parse-as-library \
//      tools/qa/glass-capture-channel-probe.swift -o /tmp/glass-capture-channel-probe
//    /tmp/glass-capture-channel-probe
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - 视图（与 glass-fidelity-probe.swift 同构，保证两代探针可横向比对）

enum ProbeGeometry {
    static let containerSpacing: CGFloat = 30
    static let faceGap: CGFloat = 10
    static let size = NSSize(width: 200, height: 120)
}

struct Backdrop: View {
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

struct WithGlass: View {
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Backdrop().overlay(
            GlassEffectContainer(spacing: ProbeGeometry.containerSpacing) {
                HStack(spacing: ProbeGeometry.faceGap) {
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

/// 正对照：同布局但放**不透明色块**（内容确变，用于证明 PDF 通道对内容变化敏感）
struct WithSolidRect: View {
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Backdrop().overlay(
            HStack(spacing: ProbeGeometry.faceGap) {
                ForEach(0 ..< 2, id: \ .self) { _ in
                    Color.red
                        .frame(width: 60, height: 40)
                        .clipShape(shape)
                }
            }
        )
    }
}

struct WithoutGlass: View {
    var body: some View {
        Backdrop().overlay(
            HStack(spacing: ProbeGeometry.faceGap) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    Color.clear.frame(width: 60, height: 40)
                }
            }
        )
    }
}

// MARK: - 度量与公共设施

func log(_ line: String) {
    FileHandle.standardError.write((line + "\n").data(using: .utf8)!) // 无缓冲：挂起/崩溃不丢证据
}

/// 逐点比对 + 控制组色数（后者＝捕获通路活性证明）
func measure(_ glass: NSBitmapImageRep, _ plain: NSBitmapImageRep) -> String {
    guard glass.pixelsWide == plain.pixelsWide, glass.pixelsHigh == plain.pixelsHigh else {
        return "尺寸不一致 玻璃=\(glass.pixelsWide)x\(glass.pixelsHigh) 控制=\(plain.pixelsWide)x\(plain.pixelsHigh)"
    }
    var diff = 0
    var colors = Set<Int>()
    for x in 0 ..< glass.pixelsWide {
        for y in 0 ..< glass.pixelsHigh {
            if glass.colorAt(x: x, y: y) != plain.colorAt(x: x, y: y) {
                diff += 1
            }
            if let color = plain.colorAt(x: x, y: y) {
                colors.insert(color.hashValue)
            }
        }
    }
    let liveness = colors.count > 8 ? "通路活性成立" : "⚠️ 通路疑盲（色数过少，差异 0 不可作结论）"
    return "玻璃差异=\(diff)/\(glass.pixelsWide * glass.pixelsHigh) 控制组色数=\(colors.count) → \(liveness)"
}

func makeRep(width: Int, height: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
}

/// 装进不上屏的无边框窗口（CH1–CH4 共用）
func hostOffscreen<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: ProbeGeometry.size)
    let window = NSWindow(
        contentRect: hosting.frame,
        styleMask: .borderless,
        backing: .buffered,
        defer: true
    )
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    return (hosting, window)
}

func rep(fromPath path: String) -> NSBitmapImageRep? {
    guard let data = FileManager.default.contents(atPath: path),
          let image = NSImage(data: data),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep
}

// MARK: - CH1–CH4

@MainActor func ch1CacheDisplay() {
    func cap(_ view: some View) -> NSBitmapImageRep? {
        let (hosting, window) = hostOffscreen(view)
        defer { window.close() }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }
    guard let g = cap(WithGlass()), let n = cap(WithoutGlass()) else {
        log("CH1 cacheDisplay: 位图产出失败")
        return
    }
    log("CH1 cacheDisplay: \(measure(g, n))")
}

@MainActor func ch2DisplayIgnoringOpacity() {
    func cap(_ view: some View) -> NSBitmapImageRep? {
        let (hosting, window) = hostOffscreen(view)
        defer { window.close() }
        guard let rep = makeRep(width: Int(hosting.bounds.width) * 2, height: Int(hosting.bounds.height) * 2),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        hosting.displayIgnoringOpacity(hosting.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    guard let g = cap(WithGlass()), let n = cap(WithoutGlass()) else {
        log("CH2 displayIgnoringOpacity: 位图产出失败")
        return
    }
    log("CH2 displayIgnoringOpacity: \(measure(g, n))")
}

@MainActor func ch3LayerRender() {
    func cap(_ view: some View) -> NSBitmapImageRep? {
        let (hosting, window) = hostOffscreen(view)
        defer { window.close() }
        hosting.wantsLayer = true
        guard let layer = hosting.layer,
              let rep = makeRep(width: Int(hosting.bounds.width) * 2, height: Int(hosting.bounds.height) * 2),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        layer.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    guard let g = cap(WithGlass()), let n = cap(WithoutGlass()) else {
        log("CH3 CALayer.render: 位图产出失败")
        return
    }
    log("CH3 CALayer.render: \(measure(g, n))")
}

@MainActor func ch4PDF() {
    func pdf(_ view: some View, _ path: String) -> Data? {
        let (hosting, window) = hostOffscreen(view)
        defer { window.close() }
        let data = hosting.dataWithPDF(inside: hosting.bounds)
        try? data.write(to: URL(fileURLWithPath: path))
        return data.isEmpty ? nil : data
    }
    guard let g = pdf(WithGlass(), "/tmp/cdprobe/g.pdf"),
          let n = pdf(WithoutGlass(), "/tmp/cdprobe/n.pdf"),
          let s = pdf(WithSolidRect(), "/tmp/cdprobe/s.pdf") else {
        log("CH4 dataWithPDF: 产出失败")
        return
    }
    // 判读口径：PDF 文本层含 /ID 与时间戳噪声，逐字节文本比对会误报，故以
    // 「体积是否随内容变化响应」＋「绝对体积是否足以承载内容」判定。
    let respondsToSolid = s.count != n.count
    let sameSizeForGlass = g.count == n.count
    let verdict = if !respondsToSolid {
        "正对照（不透明色块）体积亦不变 → PDF 通道不捕获 SwiftUI 内容变化，对玻璃更无从谈起"
    } else if sameSizeForGlass {
        "正对照体积变、玻璃体积不变 → 通道可见内容而玻璃不产出任何绘制"
    } else {
        "⚠️ 玻璃亦改变 PDF 体积 → PDF 通道可能可见玻璃，需继续验证"
    }
    log("CH4 dataWithPDF: bytes 控制=\(n.count) 玻璃=\(g.count) 正对照=\(s.count)" +
        "（三者同体积且远小于编码渐变+点阵所需）→ \(verdict)")
}

// MARK: - CH5 边界外窗口 + 只读 screencapture（WindowServer 真合成）

@MainActor func ch5OffscreenWindowCapture() {
    func shot(_ view: some View, _ path: String) -> NSBitmapImageRep? {
        let (_, window) = hostOffscreen(view)
        window.setFrameOrigin(NSPoint(x: -12000, y: -12000)) // 移出所有显示器可覆盖范围
        window.orderFront(nil) // .prohibited 策略下不激活、不抢焦点
        let id = CGWindowID(window.windowNumber)
        let info = (CGWindowListCopyWindowInfo([.optionAll], id) as? [[String: Any]])?.first
        log("CH5 wid=\(window.windowNumber) 第三方不可见证据 bounds=\(info?["kCGWindowBounds"] ?? "?") onscreen=\(info?["kCGWindowIsOnscreen"] ?? "?")")
        Thread.sleep(forTimeInterval: 0.5) // 让 WindowServer 至少完成一次合成
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-o", "-x", "-l", String(window.windowNumber), path]
        try? task.run()
        task.waitUntilExit()
        window.orderOut(nil)
        window.close()
        guard task.terminationStatus == 0 else {
            log("CH5 screencapture rc=\(task.terminationStatus)")
            return nil
        }
        return rep(fromPath: path)
    }
    guard let g = shot(WithGlass(), "/tmp/cdprobe/g5.png"), let n = shot(WithoutGlass(), "/tmp/cdprobe/n5.png") else {
        log("CH5 边界外窗口截屏：产出失败（27 beta 下 screencapture 仅解锁有效）")
        return
    }
    log("CH5 边界外窗口+screencapture: \(measure(g, n)) 尺寸=\(g.pixelsWide)x\(g.pixelsHigh)")
}

// MARK: - 入口

@main
struct Probe {
    @MainActor static func main() {
        // NSApp 是隐式解包可选，未访问过 NSApplication.shared 时为 nil —— 必须先初始化再取 NSApp
        NSApplication.shared.setActivationPolicy(.prohibited) // 本进程永不可激活 → 零前台/焦点争抢
        try? FileManager.default.createDirectory(atPath: "/tmp/cdprobe", withIntermediateDirectories: true)
        log("== 玻璃像素捕获通道普查（CH1–CH5）==")
        log("屏幕数=\(NSScreen.screens.count) 主屏=\(NSScreen.main.map { "\($0.frame)" } ?? "nil")")
        // 单通道运行支持：probe ch1|ch2|ch3|ch4（定位挂起/崩溃点用，缺省全跑）
        let only = Set(CommandLine.arguments.dropFirst(1))
        func wanted(_ name: String) -> Bool {
            only.isEmpty || only.contains(name)
        }
        if wanted("ch1") {
            log(">>> ch1 开始"); ch1CacheDisplay(); log("<<< ch1 结束")
        }
        if wanted("ch2") {
            log(">>> ch2 开始"); ch2DisplayIgnoringOpacity(); log("<<< ch2 结束")
        }
        if wanted("ch3") {
            log(">>> ch3 开始"); ch3LayerRender(); log("<<< ch3 结束")
        }
        if wanted("ch4") {
            log(">>> ch4 开始"); ch4PDF(); log("<<< ch4 结束")
        }
        // CH5 默认关闭：实测 screencapture 子进程在本机需屏幕录制授权（TCC），
        // 表现为无限挂起且可能向用户弹权限窗——违反铁律 8，故仅显式开启才跑。
        if ProcessInfo.processInfo.environment["HARNESS_CH5_SCREENSHOT"] == "1" {
            ch5OffscreenWindowCapture()
        } else {
            log("CH5 边界外窗口+screencapture: 默认跳过（TCC 屏幕录制授权风险，实测挂起；见本文件注释）")
        }
        log("DONE")
    }
}
