// axdump.swift — 只读 AX 树导出（静默铁律 A 层取证工具）
//
// 与 bin/ax（历史注入式走测工具，仅用户手动）的关键区别：
//   1. 纯只读：仅 AXUIElementCopyAttributeValue，零 AXPress/零动作/零 setAttribute，
//      不改变任何 App 可见状态；
//   2. 默认只导窗口子树（老 ax dump 实测 77 行截断于菜单栏、窗口子树未输出，补记㉙）；
//   3. 不做任何 TCC 弹窗（仅 AXIsProcessTrusted() 探测，绝不弹「辅助功能」授权框）。
//
// 用法: axdump <pid> [maxdepth] [--menubar]
//   maxdepth 默认 8；--menubar 附带菜单栏子树（默认不导，避免菜单噪音淹没窗口几何）
// 输出: 与老 ax 同型 —— [Role] t='title' d='desc' v='value' id='id' pos=x,y size=WxH
import ApplicationServices
import Foundation

let args = CommandLine.arguments
guard args.count >= 2, let pid = Int32(args[1]) else {
    FileHandle.standardError.write(Data("usage: axdump <pid> [maxdepth] [--menubar]\n".utf8))
    exit(64)
}

var maxDepth = 8
var withMenubar = false
for a in args.dropFirst(2) {
    if a == "--menubar" {
        withMenubar = true
    } else if let n = Int(a) {
        maxDepth = n
    }
}

// 绝不弹权限框：未受信任就如实退出（G3 走查前由用户一次性授权宿主，口径见补记㉙）
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("axdump: not trusted (accessibility). 不弹窗申请，请宿主预先授权。\n".utf8))
    exit(2)
}

let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 1.5)

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func text(_ el: AXUIElement, _ name: String) -> String {
    guard let v = attr(el, name) else { return "" }
    if let s = v as? String {
        return s
    }
    return "\(v)"
}

func clip(_ s: String, _ n: Int = 48) -> String {
    let one = s.replacingOccurrences(of: "\n", with: " ")
    return one.count > n ? String(one.prefix(n)) + "…" : one
}

func geometry(_ el: AXUIElement) -> String {
    guard let pRef = attr(el, kAXPositionAttribute as String),
          let sRef = attr(el, kAXSizeAttribute as String),
          CFGetTypeID(pRef) == AXValueGetTypeID(),
          CFGetTypeID(sRef) == AXValueGetTypeID()
    else { return "" }
    // CFGetTypeID 已验证 → unsafeDowncast 安全（CF 类型 as? 被编译器判恒真，as! 违反 force_cast 门禁）
    let pVal = unsafeDowncast(pRef, to: AXValue.self)
    let sVal = unsafeDowncast(sRef, to: AXValue.self)
    var pt = CGPoint.zero
    var sz = CGSize.zero
    AXValueGetValue(pVal, .cgPoint, &pt)
    AXValueGetValue(sVal, .cgSize, &sz)
    return " pos=\(Int(pt.x)),\(Int(pt.y)) size=\(Int(sz.width))x\(Int(sz.height))"
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func dumpElement(_ el: AXUIElement, depth: Int, remaining: inout Int, indent: String) {
    guard remaining > 0 else { return }
    remaining -= 1
    let role = text(el, kAXRoleAttribute as String)
    let t = clip(text(el, kAXTitleAttribute as String))
    let d = clip(text(el, kAXDescriptionAttribute as String))
    let v = clip(text(el, kAXValueAttribute as String), 24)
    let id = clip(text(el, kAXIdentifierAttribute as String), 24)
    print("\(indent)[\(role)] t='\(t)' d='\(d)' v='\(v)' id='\(id)'\(geometry(el))")
    guard depth > 0 else { return }
    for c in children(el) {
        guard remaining > 0 else { print("\(indent)  …(预算耗尽)"); return }
        dumpElement(c, depth: depth - 1, remaining: &remaining, indent: indent + "  ")
    }
}

var budget = 4000 // 全局节点预算，防失控输出
let wins = (attr(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
print("[AXApplication] pid=\(pid) windows=\(wins.count)")
for w in wins {
    dumpElement(w, depth: maxDepth, remaining: &budget, indent: "  ")
}

if withMenubar, let mbRef = attr(app, kAXMenuBarAttribute as String),
   CFGetTypeID(mbRef) == AXUIElementGetTypeID() {
    // typeID 已验证 → unsafeDowncast 安全（CF 类型 as? 会被编译器判为恒真，as! 违反门禁 force_cast）
    dumpElement(unsafeDowncast(mbRef, to: AXUIElement.self), depth: 3, remaining: &budget, indent: "  ")
}

if wins.isEmpty {
    FileHandle.standardError.write(Data("axdump: AXWindows 为空（App 隐藏/无窗/权限不足均可能）\n".utf8))
    exit(3)
}
