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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        // 不再强制深色 — 跟随系统 / 用户设置
        ThemeManager.applyFromStorage()
        NSApp.setActivationPolicy(.regular)

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

        let hosting = NSHostingController(rootView: ContentView())
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
        startFrameWatchdog(for: window)
    }

    /// 看门狗：无头/远程环境下显示配置可能抖动（窗口掉屏、被窗口服务器压成碎片、被最小化）。
    /// 每 2 秒检查：应用侧 frame 与窗口服务器实际边界是否一致（用 CGWindowList 对账），
    /// 不一致则钉回目标屏（面积最大的屏 = 用户主屏）并强制重映射，保证窗口始终可见
    private var frameWatchdog: Timer?

    private func startFrameWatchdog(for window: NSWindow) {
        let mismatch = OSAllocatedUnfairLock<Int>(initialState: 0)
        frameWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak window] _ in
            guard let window else { return }
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
                mismatch.withLock { $0 = 0 }
                return
            }
            let n = mismatch.withLock { count in
                count += 1
                return count
            }
            // 连续 2 次异常才重映射，避免瞬时抖动导致闪烁
            guard n >= 2 else { return }
            mismatch.withLock { $0 = 0 }
            window.orderOut(nil)
            window.setFrame(target.visibleFrame, display: true)
            window.makeKeyAndOrderFront(nil)
        }
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
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegateInstance = delegate
        app.delegate = delegate
        app.run()
    }
}
