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

    /// 主窗口：不启用 constrainFrameRect 裁剪。
    /// macOS 27 beta 窗口服务器对副屏报幻影 visibleFrame（带 234px 幻影 dock inset），
    /// 默认 constrainFrameRect 会把用户窗口 frame 裁到幻影可见区（现场实测 1920→1686）；
    /// 看门狗负责掉屏/碎片恢复，frame 约束交还给应用侧。
    private final class UnconstrainedWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
            frameRect
        }
    }

    /// D-10(a) 透明窗底配置（测试缝：进程内单测对装配实例断言旗标；不产生任何 ordering/前台动作）
    static func applyGlassSampling(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    /// 创建标准主窗口（启动与重建共用）
    private func makeWindow() -> NSWindow {
        let window = UnconstrainedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Harness"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 800, height: 500)
        // D-10(a)/BENCHMARK §13-F4：透明窗底——让玻璃获得「窗后」（桌面）采样源，恢复 macOS 侧栏传统。
        // 透窗采样实况成败仅 G3 A-d 目检裁决（补记㊹：官方无透窗采样明文，锚定 legacy behindWindow 在册能力）；
        // 可读性兜底 = 侧栏 GlassSurface(.regular) 底（native 玻璃 / legacy 材质 / solid 回落）+ 主区 bgPrimary 实底。
        Self.applyGlassSampling(to: window)
        return window
    }

    /// 窗口服务器把窗口压成碎片且重映射无效时：重建整个窗口（换 windowNumber 重新映射）
    /// 顺序讲究：先建新窗口挂好 VC 并映射，再释放旧窗口，避免 use-after-free
    func recreateWindow(target: NSScreen) {
        guard let old = window, let contentVC = hosting else { return }
        AppDelegate.debugLog("recreateWindow: replacing fragmented win#\(old.windowNumber) oldFrame=\(old.frame)")
        frameWatchdog?.invalidate()
        let newWindow = makeWindow()
        old.contentViewController = nil
        newWindow.contentViewController = contentVC
        // 优先恢复旧窗口应用侧 frame（用户真实 frame；碎片化是窗口服务器映射问题，
        // 应用侧 frame 是可信事实源）；target.visibleFrame 在 beta 窗口服务器下可能
        // 携带幻影 dock/菜单栏 inset，直接采用会缩小用户窗口（现场实测 1920→1686）
        let frame = AppDelegate.recreateRestoreFrame(
            oldFrame: old.frame,
            targetVisible: target.visibleFrame,
            screenFrames: NSScreen.screens.map(\.frame)
        )
        newWindow.setFrame(frame, display: true)
        newWindow.makeKeyAndOrderFront(nil)
        old.isReleasedWhenClosed = false
        old.orderOut(nil)
        old.close()
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.debugLog("recreateWindow: new win#\(newWindow.windowNumber) frame=\(newWindow.frame) (restored old=\(old.frame))")
        startFrameWatchdog(for: newWindow)
    }

    /// 重建窗口采用 frame：旧应用侧 frame 有效（非零且落在任一已连屏内）→ 原样恢复；否则目标屏可见区
    nonisolated static func recreateRestoreFrame(oldFrame: NSRect, targetVisible: NSRect, screenFrames: [NSRect]) -> NSRect {
        guard oldFrame != .zero, screenFrames.contains(where: { $0.intersects(oldFrame) }) else {
            return targetVisible
        }
        return oldFrame
    }

    /// userManaged 窗口持续不可见覆盖阈值（tick 数，2s/tick）
    /// 偏离目标屏（窗口明确卡死屏）→ 10 = 20s；短暂（<20s）抖动会在屏恢复后自愈，无需干预
    nonisolated static let serverInvisibleRemapThreshold = 10
    /// 位于目标屏但服务器持续报不可见（目标屏自身掉线 / macOS 27 beta 幻影报告）→ 30 = 60s。
    /// 更高阈值防止撕裂实际可见窗口（beta 幻影为间歇 true/false 翻转，连击会被打断，不会误触发）
    nonisolated static let serverInvisibleRemapThresholdOnTarget = 30

    /// 判定是否对 userManaged 窗口强制一次性 remap（纯决策函数，供单元测试）：
    /// userManaged（用户摆放）且窗口服务器连续 N tick 报该窗口未映射/碎片化 →
    /// 死屏残留在 NSScreen.screens 使 userManaged 推断滞后，窗口实际不可见 → 强制 remap 回目标屏。
    /// 阈值按窗口是否位于目标屏分档（见上两条常量）
    nonisolated static func shouldOverrideRemap(userManaged: Bool, appSideOK: Bool, serverInvisibleStreak: Int) -> Bool {
        guard userManaged else { return false }
        let threshold = appSideOK ? serverInvisibleRemapThresholdOnTarget : serverInvisibleRemapThreshold
        return serverInvisibleStreak >= threshold
    }

    /// 看门狗：无头/远程环境下显示配置可能抖动（窗口掉屏、被窗口服务器压成碎片、被最小化）；
    /// macOS 27 beta 窗口服务器还会对本 App 窗口间歇性报告幻影 CGWindowList 边界（P0.2 现场实测）。
    /// 每 2 秒检查：应用侧 frame 与窗口服务器实际边界是否一致（用 CGWindowList 对账）。
    /// 干预策略（反拉锯）：
    /// - 用户看不到窗口（掉屏/未映射）→ n>=2 钉回用户面对屏并强制重映射，n>=4 重建窗口（预算共 2 次、间隔 ≥30s）
    /// - 用户看得到窗口但服务器报幻影碎片 → 禁止 remap（orderOut 会撕裂可见窗口并抢焦点），
    ///   持续 n>=8 才允许 recreate 自愈（ghost 渲染唯一可靠恢复手段，实测 4s 自愈）
    /// - userManaged 窗口服务器侧持续不可见（屏掉出服务器后死屏残留 / 目标屏自身掉线）→
    ///   偏离目标屏持续 20s 或位于目标屏持续 60s → 强制一次性 remap 回目标屏自愈，
    ///   不走 n 阈值、不消耗 recreate 预算（shouldOverrideRemap；现场实测 4K 掉线+预算耗尽=永久卡死）
    private var frameWatchdog: Timer?

    /// 帧监视器连续异常计数（主线程 Timer 回调使用）
    private var frameMismatch = OSAllocatedUnfairLock<Int>(initialState: 0)
    /// 窗口服务器侧不可见连击（未映射/碎片化）；持续超阈值 → 强制 userManaged 窗口一次性 remap（shouldOverrideRemap）
    private var serverInvisibleStreak = OSAllocatedUnfairLock<Int>(initialState: 0)
    /// 看门狗目标屏缓存：仅屏幕配置变化时重算，避免每 tick 动态打分造成目标屏振荡
    private var watchdogTarget: NSScreen?
    private var watchdogScreenSig: String?

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
        // 目标屏与启动逻辑一致：用户实际面对的屏（按屏上应用窗口数打分）。
        // 旧逻辑「面积最大屏」在双屏非主屏更大时（本机：4K 外屏 > 内置屏）会把窗口
        // 推到用户看不到的屏，且该屏窗口服务器碎片化时窗口彻底不可见（P0.2 现场实测）
        let sig = NSScreen.screens.map { "\($0.frame)" }.sorted().joined()
        if watchdogTarget == nil || watchdogScreenSig != sig {
            watchdogTarget = AppDelegate.pickUserFacingScreen()
            watchdogScreenSig = sig
        }
        guard let target = watchdogTarget else { return }

        // 应用侧认为的 frame 已经在目标屏可见区 → 还需和窗口服务器实际边界对账
        let appSideOK = window.screen == target && target.visibleFrame.intersects(window.frame)
        let expected = Self.appKitToCG(window.frame)
        let cg = Self.cgWindowBounds(windowNumber: window.windowNumber)
        let serverConsistent = cg.map { abs($0.width - expected.width) <= 64 && abs($0.height - expected.height) <= 64 } ?? false
        // 碎片化判定：窗口服务器实际面积显著小于应用侧期望（窗口被压成条状/碎片）；
        // 查不到（未映射）同样视为不可见
        let serverFragmented = cg.map {
            min($0.width, expected.width) / max(expected.width, 1)
                * min($0.height, expected.height) / max(expected.height, 1) < 0.5
        } ?? true
        // 尊重用户：窗口在任一已连接屏上可见（用户可能手动移动/缩放过）且未碎片化 → 不干预。
        // 旧逻辑对「app 侧 frame 与服务器边界瞬时不一致」也强制全屏重映射，与用户拖拽/缩放
        // 形成拉锯（P0.2 现场实测：用户缩窄窗口后被每 2s 拉回全屏）
        let userManaged = window.frame != .zero
            && NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        // 窗口服务器侧不可见连击（未映射/碎片化）；健康即清零。
        // 屏掉出窗口服务器时 NSScreen.screens 残留死屏，userManaged 滞后为 true 而窗口实际不可见 → 见 shouldOverrideRemap
        let serverInvisible = cg == nil || serverFragmented
        serverInvisibleStreak.withLock { $0 = serverInvisible ? $0 + 1 : 0 }
        let serverDesc = cg.map { "srv=(\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height)))" } ?? "srv=nil"

        if (appSideOK && serverConsistent) || (userManaged && !serverFragmented) {
            frameMismatch.withLock { $0 = 0 }
            return
        }
        // 持续不可见自愈：屏掉出窗口服务器后窗口卡死屏且 recreate 预算耗尽时永远无法自愈（现场实测）。
        // 服务器连续 20s（偏离目标屏）/ 60s（位于目标屏、beta 幻影误报防护）报未映射/碎片化 →
        // 覆盖 userManaged 冻结，强制一次性 remap 回目标屏（不消耗 recreate 预算）
        let invisibleStreak = serverInvisibleStreak.withLock { $0 }
        if AppDelegate.shouldOverrideRemap(userManaged: userManaged, appSideOK: appSideOK, serverInvisibleStreak: invisibleStreak) {
            frameMismatch.withLock { $0 = 0 }
            serverInvisibleStreak.withLock { $0 = 0 }
            window.orderOut(nil)
            window.setFrame(target.visibleFrame, display: true)
            window.makeKeyAndOrderFront(nil)
            AppDelegate.debugLog("watchdog OVERRIDE-REMAP userManaged window (server invisible \(invisibleStreak) ticks) -> \(target.visibleFrame) frame=\(window.frame)")
            return
        }
        let screenDesc = String(describing: window.screen?.frame)
        let state = "win#\(window.windowNumber) frame=\(window.frame) appOK=\(appSideOK) srvConsistent=\(serverConsistent) "
            + "fragmented=\(serverFragmented) userManaged=\(userManaged) scr=\(screenDesc) tgt=\(target.frame) \(serverDesc)"
        AppDelegate.debugLog("watchdog mismatch " + state)
        let n = frameMismatch.withLock { count in
            count += 1
            return count
        }
        // 反拉锯阈值（P0.2 现场实测）：
        // macOS 27 beta 窗口服务器对本 App 窗口间歇性报幻影 CGWindowList 边界
        // （Dock 缩略图尺寸/屏外边界，同窗口服务器侧报告 true/false 翻转），
        // 若每 tick 都 orderOut+setFrame+makeKeyAndOrderFront 会撕裂可见窗口并抢焦点（闪烁拉锯）。
        // - 用户看不到窗口（掉屏/未映射）：n>=2 remap，n>=4 升级 recreate（预算 2 次/30s）
        // - 用户看得到窗口但服务器报幻影碎片：禁止 remap（信任应用侧报告），
        //   持续 n>=8 才 recreate 自愈（ghost 渲染唯一可靠恢复手段）
        if n >= (userManaged ? 8 : 4) {
            frameMismatch.withLock { $0 = 0 }
            let now = Date()
            let budgetOK = AppDelegate.RecreateState.allow(now: now)
            AppDelegate.debugLog("watchdog recreate-check budgetOK=\(budgetOK)")
            if budgetOK, let delegate = appDelegateInstance {
                delegate.recreateWindow(target: target)
            }
            return
        }
        // 强制重映射只在用户看不到窗口时执行；不清零计数，
        // 让计数持续累积，重映射无效时升级到现场重建
        guard !userManaged, n >= 2 else { return }
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
        // 排除本进程窗口：watchdog 每 tick 依此选屏，若计入自身窗口会形成反馈回路
        // （移屏→计数翻转→再移屏），窗口服务器被反复 orderOut/setFrame 压成碎片（P0.2 现场实测）
        let own = ProcessInfo.processInfo.processName
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner != own,
                  let layer = w[kCGWindowLayer as String] as? Int,
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
