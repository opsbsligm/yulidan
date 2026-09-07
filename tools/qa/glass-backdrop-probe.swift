// glass-backdrop-probe —— D-10(a) 透明窗底 vs D-10(b) 实底窗底 像素对照探针（取证用，非 App 代码）
//
// 【存在理由】QUALITY ㊿：全屏玻璃面的颜色由「窗后有什么」决定，而 A 层没有玻璃像素通道
//   （ImageRenderer 不渲染 glassEffect，BENCHMARK §4）⇒ 唯一静默可复算的取证办法是自己造一个
//   最小窗口并截屏。本探针把「窗底是否透明」做成唯一变量，直接量出两种装配下玻璃面的实测 RGB。
//
// 【用法】swiftc -O tools/qa/glass-backdrop-probe.swift -o /tmp/glassprobe && /tmp/glassprobe
//   产物：/tmp/probe/winA.png（透明窗底＝D-10(a) 形态）、/tmp/probe/winB.png（实底＝修复态）、
//        /tmp/probe/shot{A,B}.png（全屏帧，含壁纸）、frames.txt（几何）。
//
// 【09-07 实测基线（同一份玻璃代码，唯一变量＝窗底）】
//   · 透明窗底 `screencapture -l<windowNumber>` 单窗取证＝(99,99,99) 中性偏暗（玻璃背后无物）
//   · 实底窗底同位取证＝(230,230,230) 中性浅灰（玻璃背后＝我方 bgPrimary）⇒ 与壁纸解耦，可交付
//   · 用户实机（暖棕壁纸 R−B=+44）侧栏实测＝(204,181,150) R−B=+54 ⇒ 证明透明态色相不可控
//
// 【两条已踩过的坑（勿再靠记忆绕开）】
//   1) `screencapture -l` 取的是**单窗**合成图：透明窗时**不含窗后壁纸** ⇒ 单窗图不能用来复现
//      「用户看到的暖橙」，只能对比「我方窗底装配」的差异；要看壁纸叠加必须用全屏帧 + 正确换算：
//      NSWindow.frame 是 Cocoa 左下原点**全局**坐标，多屏（本机有负坐标副屏）时不可假设 origin=(0,0)，
//      本次窗口就被窗口服务器从请求的 (30,736) 平移到 (221,704) ⇒ 位置必须由程序自己打印。
//   2) `close()` 在 isReleasedWhenClosed=true 时会在下一个 asyncAfter 里踩已释放对象（实测 SIGSEGV）
//      ⇒ 本探针统一 `isReleasedWhenClosed=false` ＋ `orderOut(nil)`。
//
// ⚠️ 非静默工具：会在屏幕闪现两个 240×192 小窗各 ~1.4s（`.accessory` 不进 Dock、不抢前台）。
//    属低频手动取证（QUALITY ㊾-3「改变可见形态须有 before/after 证据」的执行手段），不进 CI 门禁。
//
// 严格 A/B：两窗用**同一屏幕矩形**、先后出现，各截一帧 ⇒ 唯一变量＝窗底是否透明。
// 每窗左侧 120pt 为「侧栏」= 与 SidebarView 同型的全屏 .regular 玻璃面；右侧 120pt 为主区实底。
// ⚠️ 会在屏幕上短暂闪现两个小窗（各约 1.4s），不激活、不进 Dock；仅取证用，不属于 App 运行时。
import AppKit
import SwiftUI

struct Col: View {
    let label: String
    let fullBleed: Bool // true = D-10(b) 根实底满铺；false = D-10(a) 根无背景（实底只贴主区）
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.clear
                Text(label).font(.system(size: 26, weight: .bold))
            }
            .frame(width: 120)
            .modifier(GlassLike())
            Color(nsColor: .windowBackgroundColor)
                .frame(width: 120)
                .overlay(Text("main").font(.system(size: 10)).foregroundStyle(.secondary))
        }
        .frame(width: 240, height: 160)
        .background(fullBleed ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }
}

struct GlassLike: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 0, style: .continuous))
        } else {
            content
        }
    }
}

func makeWindow(label: String, transparent: Bool, rect: NSRect) -> NSWindow {
    let w = NSWindow(contentRect: rect,
                     styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                     backing: .buffered, defer: false)
    w.title = "PROBE-\(label)"
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.isOpaque = !transparent
    w.backgroundColor = transparent ? .clear : .windowBackgroundColor
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: Col(label: label, fullBleed: !transparent))
    return w
}

func shotWindow(_ name: String, _ w: NSWindow) {
    try? FileManager.default.createDirectory(atPath: "/tmp/probe", withIntermediateDirectories: true)
    // -l <windowNumber> 直接从窗口服务器取该窗合成图（含玻璃），与位置/遮挡无关
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", String(w.windowNumber), "/tmp/probe/\(name)"]
    try? task.run(); task.waitUntilExit()
    FileHandle.standardError.write(Data("probe \(name): visible=\(w.isVisible) frame=\(w.frame)\n".utf8))
}

final class Del: NSObject, NSApplicationDelegate {
    var win: NSWindow?
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory) // 不进 Dock、不抢前台
        let screen = NSScreen.main!.frame
        let rect = NSRect(x: 30, y: screen.height - 60 - 160, width: 240, height: 160)
        // 记录几何（top-left 坐标系）供裁图
        let tlY = screen.height - (rect.origin.y + rect.height)
        let line = "screen=\(screen.width)x\(screen.height) rect=\(rect.origin.x),\(tlY),\(rect.width),\(rect.height)\n"
        try? Data(line.utf8).write(to: URL(fileURLWithPath: "/tmp/probe/frames.txt"))

        func phase(_ label: String, transparent: Bool, delay: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let w = makeWindow(label: label, transparent: transparent, rect: rect)
                self.win = w
                w.orderFrontRegardless()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.1) {
                if let w = self.win {
                    shotWindow("win\(label).png", w)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.4) { self.win?.orderOut(nil); self.win = nil }
        }
        phase("A", transparent: true, delay: 0.2) // D-10(a) 透明窗底（现状＝用户所见）
        phase("B", transparent: false, delay: 2.2) // D-10(b) 实底窗底（修复后）
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let d = Del(); app.delegate = d
app.run()
