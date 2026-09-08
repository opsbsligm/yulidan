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

/// 应用图标位图：直接读 bundle 内 AppIcon.icns（与 Dock 图标同源文件，但不经 LaunchServices 缓存）。
/// 09-08 实测：LS 图标缓存对新写入的 icns 反应滞后，NSApplicationIcon 会拿到灰色通用图标；
/// 改从 Bundle.main 确定加载，icns 缺失/解码失败时回退 NSApplicationIconName 保底不空白。
enum AppIconImage {
    static let value: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }()
}

/// 邪能光圈头像：多彩朦胧光晕缓慢旋转（AngularGradient＋blur＋linear repeatForever，全 SwiftUI 原生）。
/// 配色取伊利丹角色色系（邪能绿→紫→粉→青→回环），首尾同色保证旋转无缝；
/// 仅存在于欢迎页/空态——来消息即离场，不构成常态动画负载。
struct FelAuraAvatar: View {
    let diameter: CGFloat
    @State private var spinning = false

    private static let felSpectrum: [Color] = [
        Color(red: 0.45, green: 0.92, blue: 0.35),  // 邪能绿
        Color(red: 0.62, green: 0.35, blue: 0.90),  // 恶魔紫
        Color(red: 0.95, green: 0.45, blue: 0.75),  // 魔粉
        Color(red: 0.35, green: 0.80, blue: 0.95),  // 奥术青
        Color(red: 0.45, green: 0.92, blue: 0.35),  // 回环起点
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: Self.felSpectrum, center: .center))
                .frame(width: diameter * 1.32, height: diameter * 1.32)
                .blur(radius: diameter * 0.13)                    // 朦胧感
                .opacity(0.8)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 7).repeatForever(autoreverses: false), value: spinning)
            Image(nsImage: AppIconImage.value)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.2)) // 内圈描边与光分离
        }
        .frame(width: diameter * 1.32, height: diameter * 1.32)
        .onAppear { spinning = true }
    }
}
