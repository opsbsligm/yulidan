import SwiftUI
import AppKit
import ServiceContainer
import Session
import LLM
import Tools
import Agent

nonisolated(unsafe) private var appDelegateInstance: AppDelegate?

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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
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
