// evtype <text>  通过 CGEvent.keyboardTextLaunch 批量文本注入（Apple 文档化：CGEventSource 文本事件）
import Foundation
import CoreGraphics
let a = CommandLine.arguments
guard a.count >= 2 else { print("usage: evtype <text>"); exit(2) }
let text = Array(a[1].utf16)
guard let src = CGEventSource(stateID: .combinedSessionState) else { exit(1) }
for unit in text {
    var u = unit
    guard let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) else { continue }
    ev.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
    ev.post(tap: .cghidEventTap)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
    up?.post(tap: .cghidEventTap)
    usleep(15_000)
}
print("typed \(text.count) units")
