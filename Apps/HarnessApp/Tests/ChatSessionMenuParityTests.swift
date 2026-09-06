import Foundation
@testable import HarnessApp
import Testing

// MARK: - R1 #3 永久回归护栏：顶栏「会话标题右键菜单 ≡ 溢出菜单」同动作集（09-06）

//
// 为什么需要这条护栏（口径来源）：目标 v8 走测项 R1 #3 =「聊天顶栏会话标题右键菜单
// （与溢出菜单同动作集）」。此前该子句只有一次性走测/像素证据，功能冻结后若有人把
// 其中一处改成内联副本、或往共享动作集加/删一项而漏了另一处，现有测试全部无感。
//
// 实现事实（Apps/HarnessApp/Sources/Views/ChatAreaView.swift，写测试前已核）：
//   · ChatTopBar.body 的会话标题 Text 上挂 `.contextMenu { sessionMenuActions }`；
//   · 右侧 … 按钮是 `Menu { sessionMenuActions } label: { … }`；
//   · 两处引用同一私有计算属性 sessionMenuActions ⇒ 引用内容一致由编译器保证，
//     但「两处确实引用它」本身无编译期保证，故需本判据。
//
// 判据分层（全部 A 层：进程内只读文件 + 纯字符串判定，零前台、零键鼠、锁屏可跑）：
//   T1 引用判据：两个入口各自确实引用共享动作集（防内联副本漂移）。
//   T2 内容+顺序判据：动作 token 序列逐位相等（防加/删/换序静默失配）。
//   T3 登记门：动作集内出现判据未登记的 viewModel 调用即红（防护栏静默失效）。
//   T4 挂载位置判据：右键菜单挂在会话标题 Text 之后（防挂错宿主元素）。
//   T5 副本禁令：动作集定义体之外不得再出现任何菜单项 Label 字面量。
//
// 已知局限（勿误读为行为级证明）：本判据证明「两入口在源码上共享同一动作集且动作集
// 未漂移」；菜单渲染实况属 B 层（ax showmenu，需用户择时同意）或用户手动走查。
// 点击后的真实行为另有 AppViewModelSessionLifecycleTests / PinnedSessionTests 覆盖。
//
// 提取器局限：括号配对扫描不识别字符串字面量内的花括号——本目标文件当前无此类字面量；
// 若将来在 ChatAreaView.swift 引入含花括号的字符串常量，需同步升级本提取器。

@Suite("R1 #3 顶栏会话菜单双入口同动作集（结构性护栏）")
struct ChatSessionMenuParityTests {
    private static let relativePath = "Apps/HarnessApp/Sources/Views/ChatAreaView.swift"
    private static let topBarAnchor = "struct ChatTopBar: View {"
    private static let menuDeclAnchor = "private var sessionMenuActions: some View {"

    /// 共享动作集里「动作」的白名单（T2 顺序判据与 T3 登记门的唯一依据）
    private static let knownActionCalls = [
        "togglePinSession",
        "attachFiles",
        "spawnSubagentFromChat",
        "shareChat",
        "exportChat",
        "renameSession",
        "deleteSession",
        "clearChat",
    ]

    /// 动作集体内允许出现的非动作辅助调用（取标题等），不计入动作序列
    private static let helperCalls: Set<String> = ["sessionTitle"]

    /// 三个确认态入口（真正的 viewModel 调用在 alert/dialog 内，体内只置标志位）
    private static let confirmFlags: Set<String> = ["showRenameAlert", "showClearConfirm", "showDeleteConfirm"]

    /// T2 预期 token 序列（逐位相等；Divider 计入，因为它决定分组视觉）
    private static let expectedTokenSequence = [
        "call:togglePinSession",
        "call:attachFiles",
        "call:spawnSubagentFromChat",
        "divider",
        "call:shareChat",
        "call:exportChat",
        "flag:showRenameAlert",
        "divider",
        "flag:showClearConfirm",
        "flag:showDeleteConfirm",
    ]

    enum ParityError: Error {
        case noRepoRoot
        case missingFile(String)
        case missingAnchor(String)
        case unbalanced(String)
    }

    // MARK: 源码定位与解析（仓库根定位复用 WorkspaceRoutingTests 的 .git 上溯口径）

    private static func findRepoRoot() -> URL? {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath),
            URL(fileURLWithPath: Bundle.main.bundlePath),
            URL(fileURLWithPath: CommandLine.arguments.first ?? ""),
        ]
        for start in candidates {
            var dir = start.standardizedFileURL
            for _ in 0 ... 12 {
                if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                    return dir
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path {
                    break
                }
                dir = parent
            }
        }
        return nil
    }

    private static func source() throws -> String {
        guard let repoRoot = findRepoRoot() else {
            Issue.record("无法定位仓库根（cwd/bundle/argv0 向上均无 .git）")
            throw ParityError.noRepoRoot
        }
        let url = repoRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParityError.missingFile(url.path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 从 anchor（以其结尾的 `{` 结束）起做括号配对，返回花括号体内容
    private static func body(after anchor: String, in src: String) throws -> String {
        guard let anchorRange = src.range(of: anchor) else { throw ParityError.missingAnchor(anchor) }
        var depth = 1
        var idx = anchorRange.upperBound
        let bodyStart = idx
        while idx < src.endIndex {
            let ch = src[idx]
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return String(src[bodyStart ..< idx])
                }
            }
            idx = src.index(after: idx)
        }
        throw ParityError.unbalanced(anchor)
    }

    /// 取 ChatTopBar 体内的共享动作集定义体
    private static func actionSetBody() throws -> String {
        let topBar = try Self.body(after: topBarAnchor, in: Self.source())
        return try Self.body(after: menuDeclAnchor, in: topBar)
    }

    private static func topBar() throws -> String {
        try body(after: topBarAnchor, in: source())
    }

    private struct Hit: Comparable {
        let location: Int
        let token: String
        static func < (lhs: Hit, rhs: Hit) -> Bool {
            lhs.location < rhs.location
        }
    }

    private static func matches(of pattern: String, in text: String) throws -> [NSTextCheckingResult] {
        let re = try NSRegularExpression(pattern: pattern)
        return re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// 按源码顺序返回动作集 token（viewModel 调用 / 确认标志 / Divider 合并排序）
    private static func actionTokens(in bodyText: String) throws -> [String] {
        var hits: [Hit] = []
        for m in try matches(of: #"viewModel\.([A-Za-z]+)\("#, in: bodyText) {
            hits.append(Hit(location: m.range.location, token: "call:\(ns(bodyText, m, 1))"))
        }
        for m in try matches(of: #"(show[A-Za-z]+) = true"#, in: bodyText) {
            hits.append(Hit(location: m.range.location, token: "flag:\(ns(bodyText, m, 1))"))
        }
        for m in try matches(of: #"Divider\(\)"#, in: bodyText) {
            hits.append(Hit(location: m.range.location, token: "divider"))
        }
        return hits.sorted().compactMap { hit in
            if hit.token == "divider" {
                return hit.token
            }
            if hit.token.hasPrefix("flag:") {
                return confirmFlags.contains(String(hit.token.dropFirst(5))) ? hit.token : nil
            }
            if hit.token.hasPrefix("call:") {
                return knownActionCalls.contains(String(hit.token.dropFirst(5))) ? hit.token : nil
            }
            return nil
        }
    }

    private static func ns(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> String {
        (text as NSString).substring(with: match.range(at: group))
    }

    // MARK: T1 双入口必须引用同一共享动作集

    @Test("两个入口（标题右键菜单 / 溢出菜单）均引用共享 sessionMenuActions（P2.2 双入口不变量）")
    func bothEntriesReferenceSharedActionSet() throws {
        let topBar = try Self.topBar()
        #expect(
            topBar.contains(".contextMenu { sessionMenuActions }"),
            "会话标题右键菜单必须引用共享动作集（此断言转红＝R1 #3 回归）"
        )
        let menuBody = try Self.body(after: "Menu {", in: topBar)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            menuBody == "sessionMenuActions",
            "溢出菜单内容必须就是共享动作集本体，实际为：\(menuBody)"
        )
        let declCount = try Self.matches(of: NSRegularExpression.escapedPattern(for: Self.menuDeclAnchor), in: topBar).count
        #expect(declCount == 1, "sessionMenuActions 定义体应恰好一处，实得 \(declCount)")
    }

    // MARK: T2 动作集内容与顺序

    @Test("共享动作集的动作序列逐位相等（8 动作 + 2 分组线，顺序即产品口径）")
    func sharedActionSetSequenceIsExactlyAsApproved() throws {
        let seq = try Self.actionTokens(in: Self.actionSetBody())
        #expect(
            seq == Self.expectedTokenSequence,
            "动作序列漂移（任一项增/删/换序都会让两个菜单与走测口径不一致）期望 \(Self.expectedTokenSequence) 实际 \(seq)"
        )
    }

    @Test("动作集可见文案与图标稳定（Label 层判据）")
    func sharedActionSetLabelsAreStable() throws {
        let menuBody = try Self.actionSetBody()
        // 置顶项是条件文案，写作 Label(pinned ? "取消置顶" : "置顶", …)，不进字面量列表，单独断言
        let titles = try Self.matches(of: #"(?<![A-Za-z])Label\(\s*"([^"]+)""#, in: menuBody)
            .map { Self.ns(menuBody, $0, 1) }
        #expect(
            titles == ["添加附件", "派生子 Agent", "复制到剪贴板", "导出为 Markdown…", "重命名对话…", "清空本对话", "删除对话"],
            "动作可见文案（顺序/措辞）发生变化：\(titles)"
        )
        #expect(try Self.matches(of: #"\"取消置顶\"\s*:\s*\"置顶\""#, in: menuBody).count == 1,
                "置顶动作应保留 置顶/取消置顶 双态文案")
        #expect(try Self.matches(of: #"\"pin\.slash\"\s*:\s*\"pin\""#, in: menuBody).count == 1,
                "置顶动作应保留 pin/pin.slash 双态图标")
        let destructiveCount = try Self.matches(of: #"Button\(role: \.destructive\)"#, in: menuBody).count
        #expect(destructiveCount == 2, "破坏性动作应恰好 2 处（清空/删除）且带 destructive 角色，实得 \(destructiveCount)")
    }

    // MARK: T3 未知动作登记门（防护栏静默失效）

    @Test("动作集内不得出现判据未登记的 viewModel 调用（新增动作必须显式改判据）")
    func noUnregisteredActionCalls() throws {
        let menuBody = try Self.actionSetBody()
        let allCalls = try Set(Self.matches(of: #"viewModel\.([A-Za-z]+)\("#, in: menuBody)
            .map { Self.ns(menuBody, $0, 1) })
        let unknown = allCalls.subtracting(Set(Self.knownActionCalls).union(Self.helperCalls)).sorted()
        #expect(
            unknown.isEmpty,
            "动作集出现未登记调用 \(unknown)：请同步更新 knownActionCalls/helperCalls 与预期序列，否则本护栏已失效"
        )
    }

    // MARK: T4 右键菜单挂载位置

    @Test("右键菜单挂在会话标题 Text 之后（宿主元素判据，防挂错对象）")
    func contextMenuIsAttachedToSessionTitle() throws {
        let topBar = try Self.topBar()
        let titleRange = try #require(
            topBar.range(of: "Text(viewModel.sessionTitle(for: session))"),
            "未找到会话标题 Text"
        )
        let menuRange = try #require(topBar.range(of: ".contextMenu { sessionMenuActions }"), "未找到标题右键菜单")
        let declRange = try #require(topBar.range(of: Self.menuDeclAnchor), "未找到动作集定义体")
        #expect(
            titleRange.lowerBound < menuRange.lowerBound && menuRange.lowerBound < declRange.lowerBound,
            "右键菜单必须紧跟会话标题（位于标题之后、动作集定义体之前）"
        )
    }

    // MARK: T5 副本禁令

    @Test("动作集定义体之外不得内联任何菜单项 Label（杜绝双入口分叉）")
    func noInlinedDuplicateMenuItems() throws {
        let topBar = try Self.topBar()
        let menuBody = try Self.actionSetBody()
        // 完整定义体文本 = anchor + 体内容 + 闭合花括号；从 ChatTopBar 中整段挖除即为「定义体之外」
        let wholeDecl = Self.menuDeclAnchor + menuBody + "}"
        var outside = topBar
        if let declInTopBar = outside.range(of: wholeDecl) {
            outside.removeSubrange(declInTopBar)
        } else {
            Issue.record("无法在 ChatTopBar 内定位完整动作集定义体（锚点或括号配对可能被改动）")
        }
        // (?<![A-Za-z]) 是为了不把 .accessibilityLabel("…") 误当成菜单项 Label
        let stray = try Self.matches(of: #"(?<![A-Za-z])Label\("#, in: outside).map { loc in
            let ns = outside as NSString
            return ns.substring(with: NSRange(location: loc.range.location, length: min(48, ns.length - loc.range.location)))
        }
        #expect(stray.isEmpty, "ChatTopBar 内、动作集之外出现内联 Label，双入口可能分叉：\(stray)")
    }
}
