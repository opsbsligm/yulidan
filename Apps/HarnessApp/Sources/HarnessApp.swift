import Agent
import AppKit
import LLM
import os
import ServiceContainer
import Session
import SwiftUI
import Tools

private nonisolated(unsafe) var appDelegateInstance: AppDelegate?

/// 主题管理：system / dark / light（@AppStorage("theme")，默认跟随系统）
@MainActor
enum ThemeManager {
    static let themeKey = "theme"

    static func apply(_ theme: String) {
        switch theme {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil // 跟随系统
        }
    }

    static func applyFromStorage() {
        let t = UserDefaults.standard.string(forKey: themeKey) ?? "system"
        apply(t)
    }
}

extension AppDelegate {
    /// 远程排障：HARNESS_DEBUG=1 时把窗口状态写 /tmp/harness-debug.log
    static let debugEnabled = ProcessInfo.processInfo.environment["HARNESS_DEBUG"] == "1"
    /// 重建窗口预算：窗口服务器持续碎片化时防止无限重建刷屏（最多 2 次，间隔 ≥30s）
    nonisolated static let recreateBudget = OSAllocatedUnfairLock<Int>(initialState: 2)
    nonisolated static let lastRecreate = OSAllocatedUnfairLock<Date?>(initialState: nil)

    enum RecreateState {
        /// 有预算且距上次重建 ≥30s 才允许；成功放行时消耗预算
        static func allow(now: Date) -> Bool {
            let last = lastRecreate.withLock { $0 }
            if let last, now.timeIntervalSince(last) < 30 {
                return false
            }
            let granted = recreateBudget.withLock { count -> Bool in
                guard count > 0 else {
                    return false
                }
                count -= 1
                return true
            }
            guard granted else {
                return false
            }
            lastRecreate.withLock { $0 = now }
            return true
        }
    }

    static func debugLog(_ msg: String) {
        guard debugEnabled else { return }
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/harness-debug.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                defer { try? fh.close() }
                fh.seekToEndOfFile()
                fh.write(data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    /// 长生命周期 hosting：重建窗口时复用，避免 AppViewModel（会话状态）丢失
    private var hosting: NSHostingController<ContentView>?

    func applicationDidFinishLaunching(_: Notification) {
        // 不再强制深色 — 跟随系统 / 用户设置
        ThemeManager.applyFromStorage()
        NSApp.setActivationPolicy(.regular)

        let hosting = NSHostingController(rootView: ContentView())
        self.hosting = hosting
        let window = makeWindow()
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)
        // 启动时铺满“用户所在屏”的可视区域：
        // 无头/远程双屏场景下，窗口若落在菜单栏屏上，用户实际在看的那块屏就看不到
        // 调试/远程场景支持：HARNESS_FRAME 环境变量或 UserDefaults "harnessFrame"（AppKit 坐标 x,y,w,h）
        let frameSpec = ProcessInfo.processInfo.environment["HARNESS_FRAME"]
            ?? UserDefaults.standard.string(forKey: "harnessFrame")
        if let spec = frameSpec {
            let parts = spec.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4 {
                window.setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: true)
            }
        } else {
            window.setFrame(AppDelegate.pickUserFacingScreen().visibleFrame, display: true)
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.debugLog("launched win#\(window.windowNumber) frame=\(window.frame) mini=\(window.isMiniaturized) screens=\(NSScreen.screens.map { "\($0.frame)" })")
        startFrameWatchdog(for: window)
    }

    /// 创建标准主窗口（启动与重建共用）
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Harness"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 800, height: 500)
        window.backgroundColor = NSColor.windowBackgroundColor
        return window
    }

    /// 窗口服务器把窗口压成碎片且重映射无效时：重建整个窗口（换 windowNumber 重新映射）
    /// 顺序讲究：先建新窗口挂好 VC 并映射，再释放旧窗口，避免 use-after-free
    func recreateWindow(target: NSScreen) {
        guard let old = window, let contentVC = hosting else { return }
        AppDelegate.debugLog("recreateWindow: replacing fragmented win#\(old.windowNumber)")
        frameWatchdog?.invalidate()
        let newWindow = makeWindow()
        old.contentViewController = nil
        newWindow.contentViewController = contentVC
        newWindow.setFrame(target.visibleFrame, display: true)
        newWindow.makeKeyAndOrderFront(nil)
        old.isReleasedWhenClosed = false
        old.orderOut(nil)
        old.close()
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.debugLog("recreateWindow: new win#\(newWindow.windowNumber) frame=\(newWindow.frame)")
        startFrameWatchdog(for: newWindow)
    }

    /// 看门狗：无头/远程环境下显示配置可能抖动（窗口掉屏、被窗口服务器压成碎片、被最小化）。
    /// 每 2 秒检查：应用侧 frame 与窗口服务器实际边界是否一致（用 CGWindowList 对账），
    /// 不一致则钉回目标屏（面积最大的屏 = 用户主屏）并强制重映射，保证窗口始终可见
    private var frameWatchdog: Timer?

    /// 帧监视器连续异常计数（主线程 Timer 回调使用）
    private var frameMismatch = OSAllocatedUnfairLock<Int>(initialState: 0)

    private func startFrameWatchdog(for window: NSWindow) {
        frameWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak window] _ in
            guard let window else { return }
            // Timer 挂在主 run loop：回调在主线程执行
            MainActor.assumeIsolated {
                self.watchdogTick(window: window)
            }
        }
    }

    @MainActor
    private func watchdogTick(window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
            return
        }
        guard let target = NSScreen.screens.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) else { return }

        // 应用侧认为的 frame 已经在目标屏可见区 → 还需和窗口服务器实际边界对账
        let appSideOK = window.screen == target && target.visibleFrame.intersects(window.frame)
        let serverOK = Self.cgWindowBounds(windowNumber: window.windowNumber).map { cg in
            let expected = Self.appKitToCG(window.frame)
            return abs(cg.width - expected.width) <= 64 && abs(cg.height - expected.height) <= 64
        } ?? false

        if appSideOK, serverOK {
            frameMismatch.withLock { $0 = 0 }
            return
        }
        let screenDesc = String(describing: window.screen?.frame)
        let state = "win#\(window.windowNumber) frame=\(window.frame) appOK=\(appSideOK) srvOK=\(serverOK) scr=\(screenDesc) tgt=\(target.frame)"
        AppDelegate.debugLog("watchdog mismatch " + state)
        let n = frameMismatch.withLock { count in
            count += 1
            return count
        }
        // 连续 2 次异常才重映射，避免瞬时抖动导致闪烁
        guard n >= 2 else { return }
        // 连续 4 次仍异常（重映射已失效，窗口被压成碎片）→ 重建窗口
        if n >= 4 {
            frameMismatch.withLock { $0 = 0 }
            let now = Date()
            let budgetOK = AppDelegate.RecreateState.allow(now: now)
            AppDelegate.debugLog("watchdog recreate-check budgetOK=\(budgetOK)")
            if budgetOK, let delegate = appDelegateInstance {
                delegate.recreateWindow(target: target)
            }
            return
        }
        // 不清零：让计数持续累积，重映射无效时升级到现场重建
        window.orderOut(nil)
        window.setFrame(target.visibleFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        AppDelegate.debugLog("watchdog REMAPPED to \(target.visibleFrame) -> win#\(window.windowNumber) frame=\(window.frame)")
    }

    /// AppKit frame（左下原点）→ CG 全局边界（左上原点）
    private static func appKitToCG(_ f: NSRect) -> CGRect {
        let c = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY ?? 0
        return CGRect(x: f.minX, y: c - f.maxY, width: f.width, height: f.height)
    }

    /// 窗口服务器侧该窗口的真实边界（查不到 = 未映射）
    private static func cgWindowBounds(windowNumber: Int) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for w in list {
            guard (w[kCGWindowNumber as String] as? Int) == windowNumber,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any]
            else { continue }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        return nil
    }

    /// 选择用户正面对的屏幕：按“屏上可见的常规应用窗口数（layer 0）”打分取最高，
    /// 避免双屏/无头环境下窗口开在用户看不到的那块屏；无应用窗口时回退到菜单栏屏
    static func pickUserFacingScreen() -> NSScreen {
        let screens = NSScreen.screens
        guard screens.count > 1,
              let list = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]]
        else {
            return screens.first(where: { $0.frame.origin == .zero }) ?? screens[0]
        }
        // CGWindowList 是左上原点 y 向下，NSScreen.frame 是左下原点 y 向上：
        // appkit_y = c - cg_y，其中 c 是 CG y=0（菜单栏屏顶部）对应的 AppKit y
        let base = screens.first(where: { $0.frame.minY == 0 }) ?? screens.max(by: { $0.frame.maxY < $1.frame.maxY })
        let c = base?.frame.maxY ?? 0
        var counts = Array(repeating: 0, count: screens.count)
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any]
            else { continue }
            let cg = CGRect(dictionaryRepresentation: bounds as CFDictionary) ?? .zero
            let rect = CGRect(x: cg.minX, y: c - cg.maxY, width: cg.width, height: cg.height)
            if layer == 0 {
                for (i, screen) in screens.enumerated() where screen.frame.intersects(rect) {
                    counts[i] += 1
                }
            }
        }
        if let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 {
            return screens[best]
        }
        return screens.first(where: { $0.frame.origin == .zero }) ?? screens[0]
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }
}

@main
struct HarnessApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegateInstance = delegate
        app.delegate = delegate
        app.run()
    }
}
