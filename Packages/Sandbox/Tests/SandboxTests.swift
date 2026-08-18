import Foundation
@testable import Sandbox
import XCTest

final class PathSandboxTests: XCTestCase {
    // XCTest 标准模式：setUp 中赋值（与 BuiltinToolsTests 一致）
    // swiftlint:disable:next implicitly_unwrapped_optional
    var base: URL!
    // swiftlint:disable:next implicitly_unwrapped_optional
    var sandbox: PathSandbox!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("harness-sandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        sandbox = PathSandbox(allowedRoots: [base.path])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func write(_ rel: String, contents: String = "x") throws -> URL {
        let url = base.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    func testInsideSandboxAllowed() throws {
        let file = try write("a/b.txt")
        XCTAssertTrue(sandbox.isAllowed(file.path))
        XCTAssertNoThrow(try sandbox.assertAllowed(file.path))
    }

    func testDotDotEscapeBlocked() throws {
        let file = try write("inner.txt")
        // 词法上绕出沙箱
        let escaped = file.deletingLastPathComponent().path + "/../out.txt"
        XCTAssertFalse(sandbox.isAllowed(escaped))
        XCTAssertThrowsError(try sandbox.assertAllowed(escaped))
    }

    func testDotDotInsideSandboxAllowed() throws {
        _ = try write("sub/inner.txt")
        // 沙箱内部的 .. 归约仍然允许
        let inside = base.appendingPathComponent("sub/../inner.txt").path
        XCTAssertTrue(sandbox.isAllowed(inside))
        XCTAssertEqual(sandbox.resolve(inside).lastPathComponent, "inner.txt")
    }

    func testSymlinkEscapeBlocked() throws {
        // 沙箱内符号链接指向外部目录
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("escape"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc"))
        let target = base.appendingPathComponent("escape/hostname").path
        XCTAssertFalse(sandbox.isAllowed(target))
        XCTAssertThrowsError(try sandbox.assertAllowed(target))
    }

    func testSymlinkedRootIsCanonicalized() {
        // macOS /tmp 是符号链接；用 real 形式注册根，访问 /tmp 形式也应允许
        let real = base.resolvingSymlinksInPath().path
        let viaSymlink = base.path // 原始（未解析）形式
        let fs = PathSandbox(allowedRoots: [real])
        XCTAssertTrue(fs.isAllowed(viaSymlink + "/a.txt"))
    }

    func testMissingTargetInsideAllowed() throws {
        // 写入场景：目标不存在但父目录在沙箱内
        let missing = base.appendingPathComponent("new/dir/file.txt").path
        XCTAssertTrue(sandbox.isAllowed(missing))
        XCTAssertNoThrow(try sandbox.assertAllowed(missing))
    }

    func testMissingTargetUnderSymlinkedParentBlocked() throws {
        // 父目录经符号链接指向外部
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("escape"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc"))
        let missing = base.appendingPathComponent("escape/new/file.txt").path
        XCTAssertFalse(sandbox.isAllowed(missing))
        XCTAssertThrowsError(try sandbox.assertAllowed(missing))
    }

    func testPrefixSiblingNotAllowed() {
        // /base 不能放行 /base-evil
        let sibling = base.deletingLastPathComponent().appendingPathComponent(base.lastPathComponent + "-evil")
        XCTAssertFalse(sandbox.isAllowed(sibling.path + "/a.txt"))
    }

    func testTildeExpansion() {
        let homeSandbox = PathSandbox(allowedRoots: [base.path])
        // ~ 展开为 $HOME；HOME 不在沙箱内 → 拒绝
        XCTAssertFalse(homeSandbox.isAllowed("~/Documents"))
    }

    func testEmptyPathThrows() {
        XCTAssertThrowsError(try sandbox.assertAllowed("   ")) {
            guard case PathSandboxError.emptyPath = $0 else {
                return XCTFail("应为 emptyPath，实际：\($0)")
            }
        }
    }

    func testErrorDescriptions() {
        let outside = PathSandboxError.outsideSandbox(attempted: "/tmp/evil", allowedRoots: ["/a", "/b"])
        XCTAssertTrue(outside.description.contains("/tmp/evil"))
        XCTAssertTrue(outside.description.contains("/a, /b"))
        XCTAssertEqual(PathSandboxError.emptyPath.description, "路径不能为空")
    }

    func testResolveEmptyPathFallsBackToCurrentDirectory() {
        let resolved = sandbox.resolve("")
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        XCTAssertEqual(resolved, cwd)
        // 纯空白同样按当前目录处理
        XCTAssertEqual(sandbox.resolve("   "), cwd)
    }

    func testResolveTrimsWhitespace() throws {
        let file = try write("t.txt")
        XCTAssertEqual(sandbox.resolve("  " + file.path + "  "), file)
    }

    func testAssertAllowedOutsideCarriesAttemptedAndRoots() {
        let missingOutside = base.deletingLastPathComponent()
            .appendingPathComponent("no-such-dir-\(UUID().uuidString)")
            .appendingPathComponent("deep.txt").path
        XCTAssertThrowsError(try sandbox.assertAllowed(missingOutside)) {
            guard let err = $0 as? PathSandboxError, case let PathSandboxError.outsideSandbox(attempted, roots) = err else {
                return XCTFail("应为 outsideSandbox，实际：\($0)")
            }
            XCTAssertEqual(attempted, missingOutside)
            XCTAssertEqual(roots, [base.path])
        }
    }

    func testRootPathItselfIsAllowed() {
        // url.path == root.path 相等分支
        XCTAssertTrue(sandbox.isAllowed(base.path))
        XCTAssertNoThrow(try sandbox.assertAllowed(base.path))
    }
}
