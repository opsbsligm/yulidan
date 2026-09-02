// 事件探针：ev activate <pid> | ev key <cmd|none> <char> | ev rclick x y | ev click x y | ev drag sx sy ex ey
import Foundation
import CoreGraphics
import AppKit

let a = CommandLine.arguments
func flush(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func key(_ keyChar: String, cmd: Bool) {
    let map: [Character: CGKeyCode] = ["n": 45, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, ".": 47, "s": 1, ",": 43]
    var code: CGKeyCode
    if keyChar == "return" { code = 36 } else if keyChar == "tab" { code = 48 } else if let c = map[keyChar.first!] { code = c } else { print("unmapped key \(keyChar)"); exit(2) }
    let flags: CGEventFlags = cmd ? .maskCommand : []
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
    down.flags = flags; up.flags = flags
    flush(down); usleep(60_000); flush(up)
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
    flush(down); usleep(50_000); flush(up)
    print("esc posted")
case "click", "rclick":
    let x = Double(a[2 + 1])!, y = Double(a[2 + 2])!
    let p = CGPoint(x: x, y: y)
    flush(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    usleep(80_000)
    let btn: CGMouseButton = a[1] == "rclick" ? .right : .left
    let typeDown: CGEventType = a[1] == "rclick" ? .rightMouseDown : .leftMouseDown
    let typeUp: CGEventType = a[1] == "rclick" ? .rightMouseUp : .leftMouseUp
    flush(CGEvent(mouseEventSource: nil, mouseType: typeDown, mouseCursorPosition: p, mouseButton: btn))
    usleep(80_000)
    flush(CGEvent(mouseEventSource: nil, mouseType: typeUp, mouseCursorPosition: p, mouseButton: btn))
    print("\(a[1]) at \(x),\(y)")
case "drag":
    let s = CGPoint(x: Double(a[2])!, y: Double(a[3])!), e = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    let steps = a.count > 6 ? Int(a[6])! : 20
    flush(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: s, mouseButton: .left))
    usleep(120_000)
    flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: s, mouseButton: .left))
    usleep(250_000)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let p = CGPoint(x: s.x + (e.x - s.x) * t, y: s.y + (e.y - s.y) * t)
        flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left))
        usleep(30_000)
    }
    // 可选悬停保持（终点处停顿 N ms，供外部在保持窗口内截图取证悬停高亮）
    if a.count > 7, let hold = Int(a[7]) {
        for _ in 0..<10 { // 终点微动保持拖拽会话活跃（原生拖拽需要持续事件流）
            let p = CGPoint(x: e.x + CGFloat(Int.random(in: -1...1)) * 0.5, y: e.y + CGFloat(Int.random(in: -1...1)) * 0.5)
            flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left))
            usleep(UInt32(hold))
        }
    }
    usleep(200_000)
    flush(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: e, mouseButton: .left))
    print("drag (\(s.x),\(s.y))→(\(e.x),\(e.y)) \(steps) steps hold=\(a.count > 7 ? a[7] : "0")")
default: print("usage"); exit(2)
}
