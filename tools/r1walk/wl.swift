// 窗口枚举：owner name + window id + bounds + layer
import CoreGraphics
import Foundation

let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(opts, CGWindowID(0)) as? [[String: Any]] else { exit(1) }
for info in infoList {
    let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
    let name = info[kCGWindowName as String] as? String ?? ""
    let num = info[kCGWindowNumber as String] as? Int ?? -1
    let layer = info[kCGWindowLayer as String] as? Int ?? -999
    let b = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    if owner.contains("Harness") || owner.contains("System Settings") || !name.isEmpty {
        print("WID=\(num) layer=\(layer) owner=\(owner) name=\(name) x=\(Int(b["X"] ?? 0)) y=\(Int(b["Y"] ?? 0)) w=\(Int(b["Width"] ?? 0)) h=\(Int(b["Height"] ?? 0))")
    }
}
