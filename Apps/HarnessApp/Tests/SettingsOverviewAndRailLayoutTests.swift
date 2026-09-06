import Foundation
@testable import HarnessApp
import Testing

// MARK: - D-8 概览页「编辑…」跳转 + D-9 只读标注 + F6/D-12 rail 避让几何

// MARK: D-8：导航状态机跨分类跳转

@Suite("D-8 概览页跳转编辑 pane")
struct SettingsOverviewJumpTests {
    /// 判别器（09-06 变异实测）：把 `jumpToSub` 换成 `selectSub` 后，从「通用」跳「提供商与密钥」
    /// 会停在原分类根子页（`selectSub` 对跨分类子页直接忽略）⇒ 本组断言转红。
    @Test("jumpToSub：从任意一级分类出发都能落到目标 pane（含跨分类）")
    func jumpReachesEveryPane() {
        for start in SettingsTab.allCases {
            for target in SettingsSubTab.allCases {
                var nav = SettingsNavigationState()
                nav.selectTab(start)
                nav.jumpToSub(target)
                #expect(nav.currentSub == target, "起点=\(start.title) 目标=\(target.title)")
                #expect(nav.selectedTab == target.parentTab, "一级分类需随目标归类，起点=\(start.title)")
            }
        }
    }

    @Test("selectSub 语义未被削弱：跨分类子页仍被忽略（概览跳转必须走 jumpToSub）")
    func selectSubStillIgnoresForeignPane() {
        var nav = SettingsNavigationState()
        nav.selectTab(.general)
        nav.selectSub(.providers)
        #expect(nav.currentSub == .preferences, "跨分类不应改变当前子页")
    }

    @Test("跳到根子页等价于清空栈（jumpToSub 不产生多余栈层）")
    func jumpToRootSubClearsPath() {
        var nav = SettingsNavigationState()
        nav.selectTab(.general)
        nav.jumpToSub(.sandbox)
        #expect(nav.currentSub == .sandbox)
        nav.jumpToSub(.preferences) // general 的根子页
        #expect(nav.path.isEmpty)
    }
}

// MARK: D-8/D-9：卡片映射与只读标注

@Suite("D-8/D-9 概览卡映射与只读说明")
struct SettingsOverviewCardTests {
    @Test("五张卡各有一条映射（与概览页卡片数一致）")
    func cardsCoverOverview() {
        #expect(SettingsOverviewCard.allCases.count == 5)
    }

    @Test("有编辑入口的卡，目标 pane 必须真实存在且可跳（可达性=1 步）")
    func editableCardsTargetRealPanes() {
        for card in SettingsOverviewCard.allCases {
            guard let pane = card.editPane else { continue }
            #expect(SettingsSubTab.allCases.contains(pane), "\(card.rawValue) 指向不存在的 pane")
            var nav = SettingsNavigationState()
            nav.jumpToSub(pane)
            #expect(nav.currentSub == pane, "\(card.rawValue) 的「编辑…」跳不过去")
            #expect(card.readOnlyNote == nil, "有编辑入口的卡不应同时挂只读说明")
        }
    }

    /// D-9 的护栏：只读卡**必须**带原因文案，且只读集合固定为「工作区根 / 向量库路径」。
    /// 若将来给这两项开了编辑入口，请同步把卡片挪到 editPane 分支——本条会先提醒。
    @Test("只读卡集合固定，且每张只读卡都带原因文案")
    func readOnlyCardsCarryNotes() {
        let readOnly = Set(SettingsOverviewCard.allCases.filter { $0.editPane == nil }.map(\.rawValue))
        #expect(readOnly == ["workspace", "rag"], "只读集合变化需同步总账 D-9 记录")
        for card in SettingsOverviewCard.allCases where card.editPane == nil {
            let note = card.readOnlyNote
            #expect((note?.isEmpty == false), "\(card.rawValue) 缺只读原因文案")
        }
    }

    @Test("只读原因文案不含未实现的能力承诺")
    func readOnlyNotesDoNotPromiseCapabilities() {
        for card in SettingsOverviewCard.allCases {
            guard let note = card.readOnlyNote else { continue }
            #expect(!note.contains("即将支持") && !note.contains("敬请期待"), "不得承诺未实现能力：\(note)")
        }
    }
}

// MARK: F6/D-12：折叠 rail 避让几何

@Suite("F6/D-12 折叠 rail 与红绿灯避让几何")
struct SidebarRailGeometryTests {
    /// 判别器（before/after 均在此计算）：原实现（rail 首图标 y=0、overlay `.padding(10)`）
    /// 与红绿灯带两两相交；改后两条都必须互不相交。
    @Test("before 证据：原几何确实交叠（记录在案，防止「问题不存在」的翻案）")
    func legacyGeometryDidIntersect() {
        let band = SidebarRailLayout.trafficLightBand
        let legacyIcon = CGRect(x: 12, y: 0, width: 28, height: 28) // SidebarView 原折叠态首图标
        let legacyButton = CGRect(x: 10, y: 10, width: 26, height: 26) // 原 `.padding(10)`
        #expect(legacyIcon.intersects(band))
        #expect(legacyButton.intersects(band))
        #expect(legacyIcon.intersects(legacyButton))
    }

    @Test("after：rail 首图标与 overlay 展开按钮均脱离红绿灯带，且按钮不落在 rail 列内")
    func newGeometryClearsTrafficLights() {
        let band = SidebarRailLayout.trafficLightBand
        let icon = SidebarRailLayout.railFirstIconRect()
        let button = SidebarRailLayout.overlayButtonRect()
        #expect(!icon.intersects(band), "rail 首图标仍与红绿灯带交叠：\(icon) vs \(band)")
        #expect(!button.intersects(band), "展开按钮仍与红绿灯带交叠：\(button) vs \(band)")
        #expect(!icon.intersects(button), "展开按钮仍压住 rail 首图标：\(button) vs \(icon)")
        #expect(button.minX >= SidebarRailLayout.railWidth, "展开按钮必须落在 rail 之右（不抢 rail 点击）")
    }

    @Test("避让带高度不小于红绿灯带下沿（下沉量够）")
    func clearanceIsBelowBand() {
        #expect(SidebarRailLayout.railTopClearance >= SidebarRailLayout.trafficLightBand.maxY)
        #expect(SidebarRailLayout.railWidth < SidebarRailLayout.trafficLightBand.maxX,
                "rail 宽小于红绿灯横向带＝x 避让不可行的前提，若变化需重裁 F6(a)")
    }
}
