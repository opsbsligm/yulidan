import Foundation
@testable import HarnessApp
import ServiceContainer
import Testing

// MARK: - 套件 3：文件型主题包（P0.4.3 社区主题包兼容）

@Suite("P0.4.3 文件型主题包")
struct FileThemePackageTests {
    private func writeSpec(_ dir: URL, id: String, name: String, accent: String? = "#123456") throws -> URL {
        var spec: [String: String] = ["id": id, "name": name]
        if let accent {
            spec["accentHex"] = accent
        }
        let url = dir.appendingPathComponent("spec.json")
        try JSONEncoder().encode(spec).write(to: url)
        return url
    }

    @Test("导入：spec.json → themes/<id>/ + 插件实例 + loadAll 可重扫")
    func importAndReload() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src.json")
        let json = "{\"id\":\"My Theme!\",\"name\":\"我的主题\",\"accentHex\":\"#123456\"}"
        try Data(json.utf8).write(to: source)

        let plugin = try ThemePackageImporter.importPackage(fileURL: source, into: root)
        // id 净化（My Theme! → my-theme）
        #expect(plugin.manifest.id.rawValue == "theme-file-my-theme")
        #expect(plugin.themeSpec.id == "my-theme")
        let expected = root.appendingPathComponent("my-theme/spec.json")
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(ThemePackageImporter.loadAll(in: root).count == 1)

        // 卸载删目录
        ThemePackageImporter.remove(themeID: "my-theme", from: root)
        #expect(!FileManager.default.fileExists(atPath: expected.path))
        #expect(ThemePackageImporter.loadAll(in: root).isEmpty)
    }

    @Test("目录包（内含 spec.json）可导入；缺失 spec.json 报错")
    func directoryPackage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pkgDir = root.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        _ = try writeSpec(pkgDir, id: "dircase", name: "目录包")
        let plugin = try ThemePackageImporter.importPackage(fileURL: pkgDir, into: root)
        #expect(plugin.manifest.id.rawValue == "theme-file-dircase")

        let emptyDir = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        #expect((try? ThemePackageImporter.importPackage(fileURL: emptyDir, into: root)) == nil)
    }

    @Test("二次校验：空 id / 非法颜色 / 非法 JSON 拒绝")
    func validationRejects() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = root.appendingPathComponent("bad.json")

        try Data(#"{"id":"  ","name":"x"}"#.utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)

        try Data(#"{"id":"ok","name":"x","accentHex":"red"}"#.utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)

        // P1.4：glassTintHex 纳入颜色校验（非法 hex 拒绝，与其余颜色同口径）
        try Data(#"{"id":"ok","name":"x","glassTintHex":"not-a-hex"}"#.utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)

        try Data("not-json".utf8).write(to: bad)
        #expect((try? ThemePackageImporter.importPackage(fileURL: bad, into: root)) == nil)
    }

    @Test("P1.4：glassTintHex 合法 + glassMaterial 可导入且落盘往返保持")
    func glassFieldsRoundTrip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-glass-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("src.json")
        let spec: [String: String] = ["id": "glassy", "name": "玻璃主题", "glassTintHex": "#7C3AED", "glassMaterial": "clear"]
        try JSONEncoder().encode(spec).write(to: source)
        let plugin = try ThemePackageImporter.importPackage(fileURL: source, into: root)
        #expect(plugin.themeSpec.glassTintHex == "#7C3AED")
        #expect(plugin.themeSpec.glassMaterial == "clear")
        let reloaded = try ThemePackageImporter.loadAll(in: root)
        #expect(reloaded.count == 1)
        #expect(reloaded[0].themeSpec.glassMaterial == "clear")
    }

    @Test("P2.3：blur/highlight 强度边界校验 — 0/1/nil 通过，1.5/−0.1/NaN 拒绝（导入同口径）")
    func glassIntensityValidation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("themes-intensity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func expectRejection(_ spec: ThemeSpec, _ expected: ThemePackageError? = nil) {
            do {
                try ThemePackageImporter.validate(spec)
                Issue.record("越界 spec 应被拒绝")
            } catch let e as ThemePackageError {
                if let expected {
                    #expect(e == expected)
                } // NaN 参与 == 恒 false，只验拒绝
            } catch {
                Issue.record("意外错误类型: \(error)")
            }
        }

        // nil = 系统默认（合法）；0...1 边界通过
        try ThemePackageImporter.validate(ThemeSpec(id: "t", name: "n"))
        try ThemePackageImporter.validate(ThemeSpec(id: "t", name: "n", blurIntensity: 0, highlightIntensity: 1))
        // 越界/非有限拒绝（错误携带字段名）
        expectRejection(ThemeSpec(id: "t", name: "n", blurIntensity: 1.5),
                        .invalidGlassIntensity(field: "blurIntensity", value: 1.5))
        expectRejection(ThemeSpec(id: "t", name: "n", highlightIntensity: -0.1),
                        .invalidGlassIntensity(field: "highlightIntensity", value: -0.1))
        expectRejection(ThemeSpec(id: "t", name: "n", blurIntensity: .nan))

        // 导入路径同口径：越界 spec.json 拒绝，合法 spec.json 导入往返保持
        let source = root.appendingPathComponent("src.json")
        try Data(#"{"id":"ok","name":"x","blurIntensity":1.5}"#.utf8).write(to: source)
        #expect((try? ThemePackageImporter.importPackage(fileURL: source, into: root)) == nil)
        try Data(#"{"id":"ok","name":"x","blurIntensity":0.8,"highlightIntensity":0.6}"#.utf8).write(to: source)
        let plugin = try ThemePackageImporter.importPackage(fileURL: source, into: root)
        #expect(plugin.themeSpec.blurIntensity == 0.8)
        #expect(plugin.themeSpec.highlightIntensity == 0.6)
    }

    @Test("sanitizeID：大小写/非法字符/长度")
    func sanitize() {
        #expect(ThemePackageImporter.sanitizeID("My Theme!") == "my-theme")
        #expect(ThemePackageImporter.sanitizeID("a_b-c9") == "a_b-c9")
        #expect(ThemePackageImporter.sanitizeID("---x---") == "x")
        #expect(ThemePackageImporter.sanitizeID(String(repeating: "a", count: 60)).count == 40)
    }
}
