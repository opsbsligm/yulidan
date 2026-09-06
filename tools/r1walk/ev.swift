import AppKit
import CoreGraphics

// 事件探针：ev activate <pid> | ev key <cmd|none> <char> | ev rclick x y | ev click x y | ev drag sx sy ex ey
import Foundation

let a = CommandLine.arguments
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
    if cDecision.allowed {
        cLayerAudit(action: "guard-check(零注入自证)") // 让审计写入路径本身也可被验证
        print("GUARD_WOULD_ALLOW token=1 tty=1（本子命令零注入，仅自证闸门；真动作需你本人授权）")
        exit(0)
    }
    print("GUARD_DENY missing=\(cDecision.missing)")
    exit(78)
}

if !cDecision.allowed {
    FileHandle.standardError.write(Data("⛔ 拒绝执行「\(cAction.isEmpty ? "?" : cAction)」：C 层事件注入仅允许用户本人当场授权后在终端手动运行。缺少 \(cDecision.missing)\n".utf8))
    exit(78)
}

cLayerAudit(action: cAction.isEmpty ? "?" : cAction)
func flush(_ e: CGEvent?) {
    e?.post(tap: .cghidEventTap)
}

func key(_ keyChar: String, cmd: Bool) {
    let map: [Character: CGKeyCode] = ["n": 45, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, ".": 47, "s": 1, ",": 43]
    var code: CGKeyCode
    if keyChar == "return" {
        code = 36
    } else if keyChar == "tab" {
        code = 48
    } else if let c = map[keyChar.first!] {
        code = c
    } else {
        print("unmapped key \(keyChar)"); exit(2)
    }
    let flags: CGEventFlags = cmd ? .maskCommand : []
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
    down.flags = flags; up.flags = flags
    flush(down); usleep(60000); flush(up)
    print("key \(cmd ? "⌘" : "")\(keyChar) posted")
}

switch a[1] {
case "activate":
    let pid = pid_t(a[2])!
    if let r = NSRunningApplication(processIdentifier: pid) {
        r.activate(options: [.activateIgnoringOtherApps])
        print("activated \(pid) front=\(r.isActive)")
    }
case "key": key(a[3], cmd: a[2] == "cmd")
case "esc":
    let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
    let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)!
    flush(down); usleep(50000); flush(up)
    print("esc posted")
case "click", "rclick":
    let x = Double(a[2 + 1])!, y = Double(a[2 + 2])!
    let p = CGPoint(x: x, y: y)
    flush(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    usleep(80000)
    let btn: CGMouseButton = a[1] == "rclick" ? .right : .left
    let typeDown: CGEventType = a[1] == "rclick" ? .rightMouseDown : .leftMouseDown
    let typeUp: CGEventType = a[1] == "rclick" ? .rightMouseUp : .leftMouseUp
    flush(CGEvent(mouseEventSource: nil, mouseType: typeDown, mouseCursorPosition: p, mouseButton: btn))
    usleep(80000)
    flush(CGEvent(mouseEventSource: nil, mouseType: typeUp, mouseCursorPosition: p, mouseButton: btn))
    print("\(a[1]) at \(x),\(y)")
case "drag":
    let s = CGPoint(x: Double(a[2])!, y: Double(a[3])!), e = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    let steps = a.count > 6 ? Int(a[6])! : 20
    flush(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: s, mouseButton: .left))
    usleep(120_000)
    flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: s, mouseButton: .left))
    usleep(250_000)
    for i in 1 ... steps {
        let t = Double(i) / Double(steps)
        let p = CGPoint(x: s.x + (e.x - s.x) * t, y: s.y + (e.y - s.y) * t)
        flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left))
        usleep(30000)
    }
    // 可选悬停保持（终点处停顿 N ms，供外部在保持窗口内截图取证悬停高亮）
    if a.count > 7, let hold = Int(a[7]) {
        for _ in 0 ..< 10 { // 终点微动保持拖拽会话活跃（原生拖拽需要持续事件流）
            let p = CGPoint(x: e.x + CGFloat(Int.random(in: -1 ... 1)) * 0.5, y: e.y + CGFloat(Int.random(in: -1 ... 1)) * 0.5)
            flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left))
            usleep(UInt32(hold))
        }
    }
    usleep(200_000)
    flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: e, mouseButton: .left))
    print("drag (\(s.x),\(s.y))→(\(e.x),\(e.y)) \(steps) steps hold=\(a.count > 7 ? a[7] : "0")")
default: print("usage"); exit(2)
}
