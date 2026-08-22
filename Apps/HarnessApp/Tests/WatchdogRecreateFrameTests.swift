import AppKit
@testable import HarnessApp
import Testing

// MARK: - 看门狗重建窗口 frame 恢复（macOS 27 beta 幻影报告下不得缩小用户窗口）

@Suite("看门狗重建 frame 恢复")
struct WatchdogRecreateFrameTests {
    @Test("旧 frame 有效（在屏内）→ 原样恢复，不受幻影 visibleFrame 影响")
    func restoresOldFrame() {
        let old = NSRect(x: -1663, y: 956, width: 1920, height: 1050)
        // 幻影 visibleFrame：beta 窗口服务器报出带 234px dock inset 的缩小版
        let phantom = NSRect(x: -1429, y: 956, width: 1686, height: 1050)
        let screens = [NSRect(x: 0, y: 0, width: 1470, height: 956),
                       NSRect(x: -1663, y: 956, width: 1920, height: 1080)]
        let result = AppDelegate.recreateRestoreFrame(oldFrame: old, targetVisible: phantom, screenFrames: screens)
        #expect(result == old)
    }

    @Test("旧 frame 为 zero → 回落目标屏可见区")
    func zeroFrameFallsBack() {
        let phantom = NSRect(x: -1429, y: 956, width: 1686, height: 1050)
        let screens = [NSRect(x: -1663, y: 956, width: 1920, height: 1080)]
        let result = AppDelegate.recreateRestoreFrame(oldFrame: .zero, targetVisible: phantom, screenFrames: screens)
        #expect(result == phantom)
    }

    @Test("旧 frame 屏外（掉屏）→ 回落目标屏可见区")
    func offScreenFallsBack() {
        let old = NSRect(x: 9000, y: 0, width: 1920, height: 1050)
        let target = NSRect(x: -1663, y: 956, width: 1920, height: 1080)
        let screens = [NSRect(x: -1663, y: 956, width: 1920, height: 1080)]
        let result = AppDelegate.recreateRestoreFrame(oldFrame: old, targetVisible: target, screenFrames: screens)
        #expect(result == target)
    }
}

// MARK: - 看门狗持续不可见覆盖 remap 决策（掉屏卡死自愈，现场实测：4K 掉线 + recreate 预算耗尽 = 永久卡死）

@Suite("看门狗持续不可见覆盖 remap 决策")
struct WatchdogOverrideRemapTests {
    @Test("偏离目标屏 + 服务器持续不可见达 20s 阈值 → 强制 remap")
    func firesWhenOffTargetAtThreshold() {
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: true, appSideOK: false,
            serverInvisibleStreak: AppDelegate.serverInvisibleRemapThreshold
        ) == true)
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: true, appSideOK: false,
            serverInvisibleStreak: AppDelegate.serverInvisibleRemapThreshold + 7
        ) == true)
    }

    @Test("连击未达阈值（短暂掉屏会自愈）→ 不干预")
    func belowThresholdNoIntervention() {
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: true, appSideOK: false,
            serverInvisibleStreak: AppDelegate.serverInvisibleRemapThreshold - 1
        ) == false)
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: true, appSideOK: false, serverInvisibleStreak: 0
        ) == false)
    }

    @Test("位于目标屏 → 走 60s 高档阈值（防 beta 幻影撕裂可见窗口）")
    func onTargetUsesHigherThreshold() {
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: true, appSideOK: true,
            serverInvisibleStreak: AppDelegate.serverInvisibleRemapThreshold + 10
        ) == false)
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: true, appSideOK: true,
            serverInvisibleStreak: AppDelegate.serverInvisibleRemapThresholdOnTarget
        ) == true)
    }

    @Test("非 userManaged 窗口 → 走原有 n 阈值路径，不触发覆盖")
    func notUserManagedNeverOverrides() {
        #expect(AppDelegate.shouldOverrideRemap(
            userManaged: false, appSideOK: false,
            serverInvisibleStreak: AppDelegate.serverInvisibleRemapThresholdOnTarget + 100
        ) == false)
    }
}
