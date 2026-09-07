import Foundation
import Testing

// MARK: - A12 玻璃面注册表护栏（G2 质量护栏，A 层静默验证：仅读源文件，零前台零键鼠）

//
// 目的：把「玻璃封装单一入口」不变量固化为可执行守卫——
//   1. `.glassSurface(` 调用点必须与注册表逐文件一致（新增玻璃面必须入册，提醒评审走 level/variant 决策）；
//   2. `.glassSurfaceContainer(` 调用点同理（容器是多作用域 morph 的前提，多一个少一个都影响 morph 拓扑）；
//   3. 原生 glassEffect 族 API（glassEffect / glassEffectID / glassEffectTransition）仅允许出现在
//      封装文件 GlassSurface.swift 与 morph 专用文件 GlassMorphTabBar.swift —— 铁律「玻璃仅系统原生 API、
//      且仅经统一封装」的机械可查表达，杜绝业务代码绕过封装裸调原生 API。
//
// 口径说明：
//   - 只统计代码调用点：行内注释（`//` 之后，`:` 前缀的 `://` 除外）与整行注释均剔除；
//   - sessionRow 的 `.thin` 线性项运行时面数随会话行数增长，本护栏统计的是源码调用点而非运行时实例数；
//   - 定义点 `func glassSurface(` 无点号前缀，天然不被 `.glassSurface(` 模式命中。

@Suite("玻璃面注册表护栏（A12）", .serialized)
struct GlassSurfaceRegistryTests {
    /// Sources 目录 = 本测试文件所在 Tests 目录的兄弟目录（#filePath 编译期锚定）
    private static let sourcesDir: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // → Tests/
        .deletingLastPathComponent() // → HarnessApp/
        .appendingPathComponent("Sources", isDirectory: true)

    /// 注册表 ①：`.glassSurface(` 调用点（文件相对路径 → 调用点数），基线合计 14（09-06 D-19(a) 新增 ChatAreaView 顶栏）
    private static let surfaceRegistry: [String: Int] = [
        "Styles/HarnessTheme.swift": 1,
        "Views/ChatAreaView.swift": 1, // D-19(a) 09-06 顶栏纳入玻璃体系（原 .ultraThinMaterial 游离于体系外）
        "Views/ChatInputArea.swift": 1,
        "Views/MCPServerViews.swift": 1,
        "Views/SettingsSubPages.swift": 1,
        "Views/SettingsView.swift": 2,
        "Views/SidebarProjectSections.swift": 3,
        "Views/SidebarSupportViews.swift": 1,
        "Views/SidebarView.swift": 3, // D-10(a) F4 侧栏玻璃底（09-04 有意新增，登记于补记❹）
    ]

    /// 注册表 ②：`.glassSurfaceContainer(` 调用点，基线合计 4
    private static let containerRegistry: [String: Int] = [
        "Views/ChatInputArea.swift": 1,
        "Views/GlassMorphTabBar.swift": 1,
        "Views/SettingsView.swift": 1,
        "Views/SidebarView.swift": 1,
    ]

    /// 白名单 ③：原生 glassEffect 族 API 仅允许的文件（封装 + morph 特例）
    private static let nativeGlassAllowlist: Set<String> = [
        "Styles/GlassSurface.swift",
        "Views/GlassMorphTabBar.swift",
    ]

    /// 原生族 API 调用点基线（文件 → 模式 → 次数）；L202 同行双调用按两处计
    private static let nativeGlassCounts: [String: [String: Int]] = [
        "Styles/GlassSurface.swift": [".glassEffect(": 1, ".glassEffectID(": 1, ".glassEffectTransition(": 2],
        // ⁽⁰⁹⁻⁰⁷ᵉ⁾ 09-07 目检回退「铺满常驻面」⇒ 逐段 ID 撤除，回到仅选中面统一 morph 身份＝1 处
        "Views/GlassMorphTabBar.swift": [".glassEffect(": 1, ".glassEffectID(": 1, ".glassEffectTransition(": 1],
    ]

    // MARK: 源文件扫描工具

    private static func swiftFiles(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        let enumerator = try #require(
            fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]),
            "Sources 目录枚举器创建失败"
        )
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }

    /// 剔除行内注释：找第一个不带 `:` 前缀的 `//`（避开 `://` URL 字面量），截断其后内容
    static func stripLineComment(_ line: String) -> String {
        var searchFrom = line.startIndex
        while let range = line.range(of: "//", range: searchFrom ..< line.endIndex) {
            if range.lowerBound == line.startIndex {
                return ""
            }
            let prev = line.index(before: range.lowerBound)
            if line[prev] != ":" {
                return String(line[line.startIndex ..< range.lowerBound])
            }
            searchFrom = range.upperBound
        }
        return line
    }

    /// 统计一段文本中固定字符串出现次数（不区分定义/调用，由 pattern 点号前缀保证仅调用）
    static func countOccurrences(of pattern: String, in text: String) -> Int {
        text.components(separatedBy: pattern).count - 1
    }

    /// 读源文件并返回「相对 Sources 的路径 → 剔除注释后的内容」
    private static func scanSources() throws -> [String: String] {
        var scanned: [String: String] = [:]
        for url in try swiftFiles(in: sourcesDir) {
            let rel = url.path.replacingOccurrences(of: sourcesDir.path + "/", with: "")
            let raw = try String(contentsOf: url, encoding: .utf8)
            let codeOnly = raw
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { stripLineComment(String($0)) }
                .joined(separator: "\n")
            scanned[rel] = codeOnly
        }
        return scanned
    }

    /// 对单张「文件 → 期望调用点数」注册表做双向比对（缺文件/计数漂移/未入册新增都算失败）
    private static func verifyRegistry(
        _ registry: [String: Int],
        pattern: String,
        scanned: [String: String],
        registryName: String
    ) {
        // 方向 1：注册表每一项都要在源码中命中且计数一致
        for (file, expected) in registry {
            guard let content = scanned[file] else {
                Issue.record("『\(registryName)』登记了 \(file)，但该文件缺失或已无 pattern 『\(pattern)』")
                continue
            }
            let actual = Self.countOccurrences(of: pattern, in: content)
            #expect(actual == expected, "『\(registryName)』\(file) 期望 \(expected) 处『\(pattern)』，实际 \(actual) 处")
        }
        // 方向 2：源码中所有命中该 pattern 的文件都必须在注册表内
        for (file, content) in scanned {
            let actual = Self.countOccurrences(of: pattern, in: content)
            if actual > 0 {
                #expect(registry[file] != nil, "新增玻璃调用点未入册：\(file) 含 \(actual) 处『\(pattern)』，请登记进 \(registryName) 并过评审")
            }
        }
    }

    // MARK: 护栏测试

    @Test("注册表①：.glassSurface( 调用点与登记逐文件一致（基线 14 处）")
    func surfaceRegistryMatches() throws {
        try #require(FileManager.default.fileExists(atPath: Self.sourcesDir.path), "Sources 目录不存在：\(Self.sourcesDir.path)")
        try Self.verifyRegistry(Self.surfaceRegistry, pattern: ".glassSurface(", scanned: Self.scanSources(), registryName: "surfaceRegistry")
        let total = Self.surfaceRegistry.values.reduce(0, +)
        #expect(total == 14, "surfaceRegistry 基线总数应为 14，请确认是有意变更") // 09-06 D-19(a) ＋1（原提示文案写 12 与判据 13 自相矛盾，一并修）
    }

    @Test("注册表②：.glassSurfaceContainer( 调用点与登记逐文件一致（基线 4 处）")
    func containerRegistryMatches() throws {
        try #require(!Self.sourcesDir.path.isEmpty)
        try #require(FileManager.default.fileExists(atPath: Self.sourcesDir.path), "Sources 目录不存在：\(Self.sourcesDir.path)")
        try Self.verifyRegistry(Self.containerRegistry, pattern: ".glassSurfaceContainer(", scanned: Self.scanSources(), registryName: "containerRegistry")
        let total = Self.containerRegistry.values.reduce(0, +)
        #expect(total == 4, "containerRegistry 基线总数应为 4，请确认是有意变更")
    }

    @Test("白名单③：原生 glassEffect 族 API 仅出现在封装/morph 两文件（铁律机械守卫）")
    func nativeGlassApiConfinedToAllowlist() throws {
        try #require(FileManager.default.fileExists(atPath: Self.sourcesDir.path), "Sources 目录不存在：\(Self.sourcesDir.path)")
        let scanned = try Self.scanSources()
        let patterns = [".glassEffect(", ".glassEffectID(", ".glassEffectTransition("]
        for (file, content) in scanned {
            let hits = patterns.map { Self.countOccurrences(of: $0, in: content) }.reduce(0, +)
            if hits > 0 {
                #expect(Self.nativeGlassAllowlist.contains(file), "原生 glassEffect 族 API 绕过封装出现在业务文件：\(file)（\(hits) 处）。玻璃必须经 GlassSurface 封装（morph 特例仅限 GlassMorphTabBar）")
            }
        }
        // 精确计数：白名单两文件各自的分模式计数与基线一致
        for (file, perPattern) in Self.nativeGlassCounts {
            guard let content = scanned[file] else {
                Issue.record("白名单文件 \(file) 缺失")
                continue
            }
            for (pattern, expected) in perPattern {
                let actual = Self.countOccurrences(of: pattern, in: content)
                #expect(actual == expected, "\(file) 的『\(pattern)』期望 \(expected) 处，实际 \(actual) 处")
            }
        }
    }

    @Test("注释剔除口径：行内注释/整行注释不计入，URL 字面量不误伤")
    func commentStrippingSemantics() {
        #expect(Self.stripLineComment("let a = 1 // .glassSurface( 注释里提及") == "let a = 1 ")
        #expect(Self.stripLineComment("// .glassSurface(").isEmpty)
        #expect(Self.stripLineComment("let u = URL(string: \"https://x\") // ok") == "let u = URL(string: \"https://x\") ")
        #expect(Self.stripLineComment(".glassSurface(.regular)") == ".glassSurface(.regular)")
        #expect(Self.countOccurrences(of: ".glassSurface(", in: "") == 0)
    }
}
