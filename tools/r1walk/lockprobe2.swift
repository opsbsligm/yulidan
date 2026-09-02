import CoreGraphics

@_silgen_name("CGSessionCopyCurrentDictionary")
func CGSessionCopyCurrentDictionary() -> CFDictionary?
if let d = CGSessionCopyCurrentDictionary() {
    let dict = d as? [String: Any] ?? [:]
    print("ScreenIsLocked:", dict["CGSSessionScreenIsLocked"] as? Int ?? -1)
} else {
    print("probe failed")
}
