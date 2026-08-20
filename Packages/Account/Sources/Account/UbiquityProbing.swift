import Foundation

/// iCloud 探测抽象（测试可注入 fake）
public protocol UbiquityProbing: Sendable {
    func probe(containerIdentifier: String) -> ICloudProbe
}

/// 默认实现：FileManager 官方 API（取证依据，macOS 26.5 SDK / 27 运行时实测）
/// - `url(forUbiquityContainerIdentifier:)` → 容器根（nil = 无 entitlement / 无权限）
/// - `ubiquityIdentityToken`（属性，非函数调用）→ 设备是否登录 iCloud 账号
public struct DefaultUbiquityProbe: UbiquityProbing {
    public init() {}

    public func probe(containerIdentifier: String) -> ICloudProbe {
        let fm = FileManager.default
        let containerURL = fm.url(forUbiquityContainerIdentifier: containerIdentifier)
        let hasAccount = fm.ubiquityIdentityToken != nil
        return ICloudProbe(containerURL: containerURL, hasICloudAccount: hasAccount)
    }
}
