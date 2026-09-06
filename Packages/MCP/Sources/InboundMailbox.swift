import Foundation

// MARK: - 入站事件与单条 FIFO（D-25(a2)）

/// 入站事件：stdout 行 / 读端 EOF / 子进程退出
enum InboundEvent: Sendable, Equatable {
    case line(String)
    case readerEnded
    case processExited
}

/// 单条入站 FIFO（D-25(a2)：拍板 2026-09-06 ／ 实施 2026-09-07）
///
/// **存在理由（缺陷原貌，勿改回）**：响应行的投递与进程退出的清理原先是两条互不相干的裸
/// `Task` hop 进同一个 actor，谁先被 actor 执行谁赢。子进程「完全合法应答后毫秒级退出」时，
/// 退出清理先跑 ⇒ `failAllPending(transportClosed)` 清空 pending ⇒ 随后到达的合法应答被
/// `resumePending` 静默丢弃 ⇒ 调用方看到「传输已断开」（D-25 H1，机制精确到行；三次真实命中）。
///
/// **本类型如何结构性消除竞速**：顺序在**生产者侧**钉死——投递方（stdout 读线程、终止回调）
/// 同步 `append`，入队序 == 它们的程序序；结算只由**一个**消费者任务串行执行。
/// 尤其：读端 EOF 天然排在读线程所见的一切数据行之后（子进程写出的字节在退出前已全部
/// 进入内核管道缓冲，读线程必先取完数据才见 EOF）。
final class InboundMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [InboundEvent] = []
    /// 单消费者：至多一枚等待（消费者只有一个，见 `consumeInbound`）
    private var waiter: CheckedContinuation<InboundEvent?, Never>?
    private var closed = false

    var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    /// 生产侧：同步入队（可在非异步线程调用；顺序 == 调用顺序）
    func append(_ event: InboundEvent) {
        var pendingWaiter: CheckedContinuation<InboundEvent?, Never>?
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        if let waiter {
            // 等待者存在 == 队列为空，直接交付不破坏顺序
            self.waiter = nil
            pendingWaiter = waiter
        } else {
            items.append(event)
        }
        lock.unlock()
        pendingWaiter?.resume(returning: event)
    }

    /// 取件结果：一条事件 / 队列终止 / 需要等待
    private enum Slot {
        case event(InboundEvent)
        case ended
        case wait
    }

    /// 消费侧：按序取出；队列关闭且取空后返回 nil（终止信号）
    ///
    /// ⚠️ Swift 6 禁止在 async 上下文直接 `lock()/unlock()` ⇒ 临界区全部放进同步私有方法
    ///    （`takeSlot` / `registerWaiter`），本方法只在两次同步取件之间 await。
    func next() async -> InboundEvent? {
        switch takeSlot() {
        case let .event(event):
            event
        case .ended:
            nil
        case .wait:
            await withCheckedContinuation { (cont: CheckedContinuation<InboundEvent?, Never>) in
                registerWaiter(cont)
            }
        }
    }

    /// 同步取件（或判定终止）
    private func takeSlot() -> Slot {
        lock.lock()
        defer { lock.unlock() }
        if !items.isEmpty {
            return .event(items.removeFirst())
        }
        return closed ? .ended : .wait
    }

    /// 登记等待者；登记前后再次核查队列（关闭前入队的最后一件不会丢）
    private func registerWaiter(_ cont: CheckedContinuation<InboundEvent?, Never>) {
        lock.lock()
        if !items.isEmpty {
            let event = items.removeFirst()
            lock.unlock()
            cont.resume(returning: event)
        } else if closed {
            lock.unlock()
            cont.resume(returning: nil)
        } else {
            waiter = cont
            lock.unlock()
        }
    }

    /// 重新开一场会话（仅 `StdioMCPClient.start()` 用）：清空上一场的残留并复位关闭位。
    /// 语义边界＝进程重启是会话边界，上一场未结算的事件属于已死的进程，保留它们只会污染新一场。
    func reopen() {
        lock.lock()
        items.removeAll()
        closed = false
        lock.unlock()
    }

    /// 关闭：消费者把剩余事件取空后收到 nil。⚠️ 不得清空 items（那会丢掉合法应答）。
    func close() {
        var pendingWaiter: CheckedContinuation<InboundEvent?, Never>?
        lock.lock()
        closed = true
        pendingWaiter = waiter
        waiter = nil
        lock.unlock()
        pendingWaiter?.resume(returning: nil)
    }
}
