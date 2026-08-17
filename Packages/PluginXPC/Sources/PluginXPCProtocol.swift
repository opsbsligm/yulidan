import Foundation

/// XPC 远端对象协议：worker 进程导出（须为 @objc 协议，NSXPCInterface 按 ObjC 协议建接口）。
/// 所有方法必须提供 reply，XPC 跨进程调用异步执行。
@objc public protocol RemotePluginEndpoint {
    /// 探活（主进程用其确认 worker 可用）
    func ping(reply: @escaping (Bool) -> Void)
    /// 在 worker 进程内实例化 + initialize + start 插件
    func start(pluginID: String, reply: @escaping (Bool, String) -> Void)
    /// 停止 worker 进程内的插件
    func stop(pluginID: String, reply: @escaping (Bool, String) -> Void)
    /// worker 进程内全部插件状态（pluginID -> "active" / "stopped" / "failed"）
    func status(reply: @escaping ([String: String]) -> Void)
    /// 健康检查：返回 (是否健康, 附加信息)
    func healthCheck(pluginID: String, reply: @escaping (Bool, String?) -> Void)
}
