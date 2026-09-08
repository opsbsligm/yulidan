import SwiftUI
import AppKit

/// 本机用户身份唯一数据源（展开态底栏与折叠态 rail 共用；2026-09-08 解耦收口）。
/// 此前两处 View 各自直调 NSFullUserName()（逻辑重复、无头像图能力），现收敛到本文件。
enum UserProfile {
    /// macOS 系统账户全名（系统设置 → 用户与群组；未设全名时系统回退 POSIX 名，不会为空串）
    static var displayName: String { NSFullUserName() }

    /// 头像缺省字＝全名首字（与解耦前逐字一致）
    static var initial: String { String(NSFullUserName().prefix(1)) }

    /// 系统自定义头像（dslocal JPEGPhoto 属性，与系统设置显示的头像是同一份数据）。
    /// 未设置 / 不可读 ⇒ nil，调用方回退首字徽标。
    /// 实测（09-08）：dscl 自读 <10ms 且无权限弹窗；static let 仅首访问执行一次，主线程访问可接受。
    static let avatarImage: NSImage? = {
        guard let data = fetchAvatarData() else { return nil }
        return NSImage(data: data)
    }()

    /// 经 dscl 自读 JPEGPhoto（与目录服务属性查询同源；OpenDirectory 的 Swift 老式初值器
    /// 在本 SDK 映射不可用——已实测编译失败，故走进程调用，自读可读性已实测）。
    private static func fetchAvatarData() -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        p.arguments = [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe() // 属性缺失/无权限不算异常：丢弃诊断，统一走 nil 回退链
        do { try p.run() } catch { return nil }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return jpegData(fromDsclOutput: text)
    }

    /// 解析 dscl -read 输出中的 base64 属性值（多行折行拼接）。纯函数，三分支已实测：
    /// 空属性值⇒nil；折叠 base64⇒Data；无属性行⇒nil
    static func jpegData(fromDsclOutput out: String) -> Data? {
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.hasPrefix("JPEGPhoto:") else { return nil }
        // 短值同行（"JPEGPhoto: <b64>"）与长值折行（"JPEGPhoto:\n\t<b64>"）双形态兼容
        let inline = first.dropFirst("JPEGPhoto:".count).trimmingCharacters(in: .whitespaces)
        let body = inline + lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined()
        guard !body.isEmpty else { return nil }
        return Data(base64Encoded: body)
    }
}

/// 共享用户头像徽标：有系统头像显示圆形头像图，否则回退首字徽标（回退视觉与解耦前逐字一致）。
struct UserAvatarBadge: View {
    let diameter: CGFloat
    let fontSize: CGFloat

    var body: some View {
        if let image = UserProfile.avatarImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(HarnessTheme.surface)
                Text(UserProfile.initial)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(HarnessTheme.accent)
            }
            .frame(width: diameter, height: diameter)
        }
    }
}
