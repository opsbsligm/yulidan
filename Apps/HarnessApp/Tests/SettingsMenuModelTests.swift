@testable import HarnessApp
import Testing

// MARK: - 设置两级菜单模型不变量（前端阶段1）

@Suite("设置两级菜单模型")
struct SettingsMenuModelTests {
    @Test("每个一级分类至少有一个子页")
    func everyTabHasChildren() {
        for tab in SettingsTab.allCases {
            #expect(!tab.children.isEmpty, "\(tab.title) 缺少子页")
        }
    }

    @Test("rootSubTab 恒为 children 首元素")
    func rootSubTabIsFirstChild() {
        for tab in SettingsTab.allCases {
            #expect(tab.rootSubTab == tab.children.first)
        }
    }

    @Test("子页 parentTab 与其所属一级分类一致")
    func subTabParentMatches() {
        for tab in SettingsTab.allCases {
            for sub in tab.children {
                #expect(sub.parentTab == tab, "\(sub.title) 的 parentTab 应为 \(tab.title)")
            }
        }
    }

    @Test("子页集合 = 各分类 children 并集（无孤儿/无重复）")
    func subTabUniverseIsConsistent() {
        let allChildren = SettingsTab.allCases.flatMap(\.children)
        #expect(Set(allChildren).count == allChildren.count, "存在重复子页")
        #expect(Set(allChildren).isSuperset(of: Set(SettingsSubTab.allCases)),
                "存在未挂到任何一级分类的孤儿子页")
        #expect(Set(allChildren).isSubset(of: Set(SettingsSubTab.allCases)),
                "children 中出现未定义的子页")
    }

    @Test("标题与图标非空且互不重复")
    func titlesAndIconsUnique() {
        let tabTitles = SettingsTab.allCases.map(\.title)
        #expect(Set(tabTitles).count == tabTitles.count)
        let subTitles = SettingsSubTab.allCases.map(\.title)
        #expect(Set(subTitles).count == subTitles.count)
        let subIcons = SettingsSubTab.allCases.map(\.icon)
        #expect(Set(subIcons).count == subIcons.count)
        for sub in SettingsSubTab.allCases {
            #expect(!sub.title.isEmpty)
            #expect(!sub.icon.isEmpty)
        }
    }

    @Test("模拟导航：切换分类重置栈，根子页不压栈，子页跳转压栈，返回清空栈")
    func navigationPathSemantics() {
        for tab in SettingsTab.allCases {
            var nav = SettingsNavigationState()

            // 默认状态：选中 general，currentSub = 其根子页
            #expect(nav.path.isEmpty)
            #expect(nav.selectedTab == .general)
            #expect(nav.currentSub == SettingsTab.general.rootSubTab)

            // 切换到该分类：栈被重置，currentSub = 该分类根子页
            nav.selectTab(tab)
            #expect(nav.selectedTab == tab)
            #expect(nav.path.isEmpty)
            #expect(nav.currentSub == tab.rootSubTab)

            // 点击根子页：path 保持空
            nav.selectSub(tab.rootSubTab)
            #expect(nav.path.isEmpty)
            #expect(nav.currentSub == tab.rootSubTab)

            // 点击非根子页：path = [sub]
            if let nonRoot = tab.children.first(where: { $0 != tab.rootSubTab }) {
                nav.selectSub(nonRoot)
                #expect(nav.path == [nonRoot])
                #expect(nav.currentSub == nonRoot)

                // 返回：path 清空，回到根子页
                nav.goBack()
                #expect(nav.path.isEmpty)
                #expect(nav.currentSub == tab.rootSubTab)
            }

            // 跨分类防护：其他分类的子页不生效
            if let foreign = SettingsSubTab.allCases.first(where: { $0.parentTab != tab }) {
                let before = nav.path
                nav.selectSub(foreign)
                #expect(nav.path == before)
                #expect(nav.selectedTab == tab)
            }
        }
    }
}
