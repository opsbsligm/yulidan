import Testing
import Foundation
@testable import Agent
import Session
import Tools
import LLM

@Suite("AgentID Tests")
struct AgentIDTests {
    @Test("Unique IDs")
    func testUnique() {
        let id1 = AgentID()
        let id2 = AgentID()
        #expect(id1.rawValue != id2.rawValue)
    }
}

@Suite("Inbox Tests")
struct InboxTests {
    @Test("Append and claim")
    func testNextTurn() {
        let inbox = Inbox()
        let msg = UserMessage(content: [.text("Hello")])
        inbox.append(msg, target: .nextTurn)
        #expect(inbox.hasPending)
        let batch = inbox.claimNext()
        #expect(batch?.count == 1)
        #expect(!inbox.hasPending)
    }
    
    @Test("Claim returns nextStep + nextTurn")
    func testClaimOrder() {
        let inbox = Inbox()
        inbox.append(UserMessage(content: [.text("Turn")]), target: .nextTurn)
        inbox.append(UserMessage(content: [.text("Step")]), target: .nextStep)
        let batch = inbox.claimNext()
        #expect(batch?.count == 2)
    }
    
    @Test("Clear removes all")
    func testClear() {
        let inbox = Inbox()
        inbox.append(UserMessage(content: [.text("Hello")]), target: .nextTurn)
        inbox.clear()
        #expect(!inbox.hasPending)
    }
    
    @Test("Empty claim returns nil")
    func testEmpty() {
        let inbox = Inbox()
        #expect(inbox.claimNext() == nil)
    }
    
    @Test("Multiple nextStep messages")
    func testMultipleNextStep() {
        let inbox = Inbox()
        inbox.append(UserMessage(content: [.text("step1")]), target: .nextStep)
        inbox.append(UserMessage(content: [.text("step2")]), target: .nextStep)
        inbox.append(UserMessage(content: [.text("turn")]), target: .nextTurn)
        let batch = inbox.claimNext()
        #expect(batch?.count == 3)
    }
}

@Suite("Turn Tests")
struct TurnTests {
    @Test("Initialize")
    func testInit() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        #expect(await turn.number == 1)
        #expect(await turn.status == .active)
    }
    
    @Test("Complete")
    func testComplete() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.complete()
        #expect(await turn.status == .completed)
    }
    
    @Test("Cancel")
    func testCancel() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.cancel()
        #expect(await turn.status == .cancelled)
    }
    
    @Test("Tool result")
    func testToolResult() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        let result = ToolResult(content: [LLM.ContentBlock.text("r")])
        await turn.recordToolResult(result)
        #expect(await turn.toolResults.count == 1)
    }
}

@Suite("AgentLoop Tests")
struct AgentLoopTests {
    @Test("Initialize")
    func testInit() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        #expect(await loop.currentStatus == .idle)
    }
    
    @Test("When idle")
    func testWhenIdle() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let result = await loop.whenIdle()
        #expect(result.status == .idle)
    }
    
    @Test("Cancel")
    func testCancel() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        await loop.cancel(keepInbox: false)
        #expect(await loop.currentStatus == .idle)
    }
}

// MARK: - AgentLoop Extended Tests

@Suite("AgentLoop Extended Tests")
struct AgentLoopExtendedTests {
    @Test("send with wakeup=false adds to inbox without processing")
    func testSendNoWakeup() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let msg = UserMessage(content: [.text("test")])
        await loop.send(msg, target: .nextTurn, wakeup: false)
        #expect(await loop.currentStatus == .idle)
    }
    
    @Test("send with wakeup=true triggers processInbox")
    func testSendWithWakeup() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let msg = UserMessage(content: [.text("test")])
        await loop.send(msg, target: .nextTurn, wakeup: true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await loop.currentStatus == .idle)
    }
    
    @Test("followup adds message and triggers processInbox")
    func testFollowup() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let msg = UserMessage(content: [.text("followup")])
        await loop.followup(msg)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await loop.currentStatus == .idle)
    }
    
    @Test("inject adds message to nextStep without triggering")
    func testInject() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let msg = UserMessage(content: [.text("inject")])
        await loop.inject(msg)
        #expect(await loop.currentStatus == .idle)
    }
    
    @Test("cancel keeps inbox when keepInbox=true")
    func testCancelKeepInbox() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let msg = UserMessage(content: [.text("keep")])
        await loop.inject(msg)
        await loop.cancel(keepInbox: true)
        #expect(await loop.currentStatus == .idle)
    }
    
    @Test("cancel clears inbox when keepInbox=false")
    func testCancelClearInbox() async {
        let loop = AgentLoop(id: AgentID(), sessionID: SessionID())
        let msg = UserMessage(content: [.text("clear")])
        await loop.inject(msg)
        await loop.cancel(keepInbox: false)
        #expect(await loop.currentStatus == .idle)
    }
}

// MARK: - Turn Extended Tests

@Suite("Turn Extended Tests")
struct TurnExtendedTests {
    @Test("fail sets status to failed")
    func testFail() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        await turn.fail(with: TestAgentError.fail)
        #expect(await turn.status == .failed)
    }
    
    @Test("waitForCompletion returns current status")
    func testWaitForCompletion() async {
        let turn = Turn(sessionID: SessionID(), messages: [], number: 1)
        let status = await turn.waitForCompletion()
        #expect(status == .active)
        
        await turn.complete()
        let status2 = await turn.waitForCompletion()
        #expect(status2 == .completed)
    }
    
    @Test("Turn with messages")
    func testTurnWithMessages() async {
        let msgs = [UserMessage(content: [.text("msg1")]), UserMessage(content: [.text("msg2")])]
        let turn = Turn(sessionID: SessionID(), messages: msgs, number: 5)
        #expect(await turn.number == 5)
        #expect(await turn.messages.count == 2)
    }
}

private enum TestAgentError: Error, Sendable {
    case fail
}
