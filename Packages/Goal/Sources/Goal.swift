/// Goal — 目标管理
public struct Goal {
    public var description: String
    public var isCompleted: Bool
    public init(description: String, isCompleted: Bool = false) {
        self.description = description
        self.isCompleted = isCompleted
    }
}
