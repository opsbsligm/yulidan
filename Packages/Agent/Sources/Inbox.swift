import Foundation
import Session

/// 输入箱 — 非 actor，使用内部同步
final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var nextTurn: [UserMessage] = []
    private var nextStep: [UserMessage] = []
    
    func append(_ message: UserMessage, target: InboxTarget) {
        lock.lock()
        defer { lock.unlock() }
        switch target {
        case .nextTurn: nextTurn.append(message)
        case .nextStep: nextStep.append(message)
        }
    }
    
    func claimNext() -> [UserMessage]? {
        lock.lock()
        defer { lock.unlock() }
        var batch: [UserMessage] = []
        batch.append(contentsOf: nextStep)
        nextStep.removeAll()
        if let first = nextTurn.first {
            batch.append(first)
            nextTurn.removeFirst()
        }
        return batch.isEmpty ? nil : batch
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        nextTurn.removeAll()
        nextStep.removeAll()
    }
    
    var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !nextTurn.isEmpty || !nextStep.isEmpty
    }
}
