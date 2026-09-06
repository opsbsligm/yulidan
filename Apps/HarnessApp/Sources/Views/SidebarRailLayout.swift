import CoreGraphics
import Foundation

/// 折叠 rail 的避让布局（F6/D-12，修法来源 BENCHMARK §13-F6；几何事实来源 §15-A17）
///
/// 在册实测几何（A 层静态，Y 基准＝红绿灯带）：
/// - 红绿灯带 x∈[10,62]、y∈[8,28]；
/// - 折叠 rail 宽 52（`SidebarView` 的 `.frame(width:)`，本类型是唯一定义点）；
/// - 原缺陷：rail 首个图标 y∈[0,28] 与 overlay 展开按钮（`.padding(10)` ⇒ y∈[10,36]）两两相交，
///   且都落在红绿灯带内（三方交叠，判级见 §15-A17：几何成立／功能后果 A 层不可判定）。
///
/// ⚠️ 本类型只是**几何常量与纯函数**（可单测、可判定），观感终裁仍归 G3 池 A 目检（A-b）。
enum SidebarRailLayout {
    /// 折叠 rail 宽度（原 `SidebarView.swift` 字面量 52 的唯一来源）
    static let railWidth: CGFloat = 52

    /// 红绿灯带（实测在册 x∈[10,62]、y∈[8,28]）
    static let trafficLightBand = CGRect(x: 10, y: 8, width: 52, height: 20)

    /// rail 顶部避让带高度 = 红绿灯带下沿 28 + 10 余量（x 方向无法避让：rail 宽 52 < 带宽 62）
    static let railTopClearance: CGFloat = 38

    /// overlay 展开按钮尺寸（现状 26×26）
    static let overlayButtonSize: CGFloat = 26

    /// overlay 展开按钮左缘起算：rail 右移 10 ⇒ 同时避开 rail 图标列与红绿灯带
    static let overlayButtonLeading: CGFloat = railWidth + 10

    /// overlay 展开按钮顶缘起算：与 rail 首图标同一避让基线（红绿灯带之下）
    static let overlayButtonTop: CGFloat = railTopClearance

    /// rail 首个图标占位（折叠态，图标 28×28 水平居中）
    static func railFirstIconRect(iconSize: CGFloat = 28) -> CGRect {
        CGRect(
            x: (railWidth - iconSize) / 2,
            y: railTopClearance,
            width: iconSize,
            height: iconSize
        )
    }

    /// overlay 展开按钮占位（窗口 topLeading 起算）
    static func overlayButtonRect(size: CGFloat = overlayButtonSize) -> CGRect {
        CGRect(x: overlayButtonLeading, y: overlayButtonTop, width: size, height: size)
    }
}
