import CoreGraphics

// evtype <text>  通过 CGEvent.keyboardTextLaunch 批量文本注入（Apple 文档化：CGEventSource 文本事件）
import Foundation

let a = CommandLine.arguments
guard a.count >= 2 else { print("usage: evtype <text>"); exit(2) }
/// ⛔⛔ C 层机器闸门（项目目标 v8 §〇 ＋ 铁律 8 静默验收；优先级高于本文件其余一切内容）⛔⛔
/// 为什么不是纸面禁令：README 的「仅用户手动」归档标注曾与本二进制的**零闸门**并存，
/// 且 r1walk4.sh 一度把「Agent 代跑无 tty 自动继续」写成特性 ⇒ 纸面承诺不足以兑现最高优先级铁律。
/// 双条件（缺一即拒，方向永远安全＝宁可拒真也不放行自动化）：
///   ① 用户本人在场声明：环境变量 HARNESS_WALK_MANUAL 必须逐字等于 I-AM-HUMAN
///   ② 必须是交互终端（stdin 为 TTY）——launchd／heartbeat／crontab／管道必然不满足
/// 每次放行都落审计行（时刻＋pid/ppid＋动作），使「没被自动触发」可事后核查。
struct CLayerDecision {
    let tokenOK: Bool
    let ttyOK: Bool
    var allowed: Bool {
        tokenOK && ttyOK
    }

    var missing: String {
        var parts: [String] = []
        if !tokenOK {
            parts.append("①HARNESS_WALK_MANUAL=I-AM-HUMAN（须用户本人键入）")
        }
        if !ttyOK {
            parts.append("②交互终端 TTY（自动化载体必然无）")
        }
        return parts.joined(separator: " 与 ")
    }
}

func cLayerDecision() -> CLayerDecision {
    CLayerDecision(tokenOK: ProcessInfo.processInfo.environment["HARNESS_WALK_MANUAL"] == "I-AM-HUMAN",
                   ttyOK: isatty(0) == 1)
}

/// 放行留痕：~/harness-wt/walk-audit.log（工作树外，重启幸存；失败不改变行为）
func cLayerAudit(action: String) {
    let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("harness-wt")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("walk-audit.log")
    let stamp = Int(Date().timeIntervalSince1970)
    let line = "\(stamp)\tpid=\(getpid())\tppid=\(getppid())\ttool=\(CommandLine.arguments[0])\taction=\(action)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

let cDecision = cLayerDecision()
let cAction = a.dropFirst().joined(separator: " ")
// 自证子命令：**零注入**，只报告闸门判定（让闸门可被验证，而不是只能相信声明）
if a.count > 1, a[1] == "guard-check" {
    print(cDecision.allowed
        ? "GUARD_WOULD_ALLOW token=1 tty=1（本子命令零注入，仅自证闸门；真动作需你本人授权）"
        : "GUARD_DENY missing=\(cDecision.missing)")
    exit(cDecision.allowed ? 0 : 78)
}

if !cDecision.allowed {
    FileHandle.standardError.write(Data("⛔ 拒绝执行「\(cAction.isEmpty ? "?" : cAction)」：C 层事件注入仅允许用户本人当场授权后在终端手动运行。缺少 \(cDecision.missing)\n".utf8))
    exit(78)
}

cLayerAudit(action: cAction.isEmpty ? "?" : cAction)
let text = Array(a[1].utf16)
guard let src = CGEventSource(stateID: .combinedSessionState) else { exit(1) }
for unit in text {
    var u = unit
    guard let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) else { continue }
    ev.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
    ev.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
    up?.post(tap: .cghidEventTap)
    usleep(15000)
}

print("typed \(text.count) units")
