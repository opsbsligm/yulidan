import CoreTransferable
import Foundation

/// 会话行拖拽载荷（macOS 原生 Transferable；应用内拖拽，JSON 表示）
/// 用途：全局会话拖入项目 / 项目内会话拖出至全局 / A 项目会话迁移至 B 项目
public struct SessionDragPayload: Codable, Hashable, Sendable, Transferable {
    /// 被拖拽会话
    public let sessionID: UUID
    /// 拖拽起始项目（nil = 全局顶层）
    public let fromProjectID: UUID?

    public init(sessionID: UUID, fromProjectID: UUID?) {
        self.sessionID = sessionID
        self.fromProjectID = fromProjectID
    }

    /// JSON Codable 表示（应用内 .draggable/.dropDestination 直接可用）
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    /// 放置解析（纯逻辑）：起点与目标相同 = noChange，否则写入新归属（nil = 全局）
    public func resolution(target: ProjectDropTarget) -> SessionMoveResolution {
        switch target {
        case let .project(pid):
            fromProjectID == pid.rawValue ? .noChange : .assign(pid.rawValue)
        case .global:
            fromProjectID == nil ? .noChange : .assign(nil)
        }
    }
}

/// 项目放置目标（拖拽落点）
public enum ProjectDropTarget: Equatable, Sendable {
    /// 落入项目
    case project(ProjectID)
    /// 落回全局顶层
    case global
}
