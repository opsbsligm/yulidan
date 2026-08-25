import Foundation
@testable import LLM
import Testing

private final class MockProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock"
    var supportedModels: [String] = ["mock-model"]
    var mockChunks: [StreamChunk] = []
    var requestCount: Int = 0

    func request(_ request: LLMRequest) async throws -> LLMResponse {
        requestCount += 1
        return LLMResponse(
            id: "mock-1", model: request.model,
            content: [.text("Hello from mock")],
            usage: nil, toolCalls: nil,
            finishReason: .stop
        )
    }

    func stream(_: LLMRequest) async throws -> AsyncThrowingStream<StreamChunk, Error> {
        requestCount += 1
        return AsyncThrowingStream { continuation in
            for chunk in self.mockChunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

@Suite("LLM Tests")
struct LLMTests {
    @Test("Request with model")
    func testRequest() {
        let req = LLMRequest(model: "gpt-4o", messages: [])
        #expect(req.model == "gpt-4o")
        #expect(req.messages.isEmpty)
    }

    @Test("Request with all fields")
    func fullRequest() {
        let req = LLMRequest(
            model: "gpt-4o", messages: [],
            systemPrompt: "You are helpful",
            tools: [ToolSchema(name: "test", description: "A")],
            maxTokens: 100, temperature: 0.7
        )
        #expect(req.maxTokens == 100)
        #expect(req.temperature == 0.7)
    }

    @Test("Mock provider returns response")
    func testProvider() async throws {
        let provider = MockProvider()
        let req = LLMRequest(model: "mock-model", messages: [])
        let response = try await provider.request(req)
        #expect(response.model == "mock-model")
        #expect(response.finishReason == .stop)
    }

    @Test("Mock provider streams")
    func testStream() async throws {
        let provider = MockProvider()
        provider.mockChunks = [
            StreamChunk(type: "text", data: Data("Hello".utf8), index: 0),
            StreamChunk(type: "text", data: Data(" world".utf8), index: 1),
        ]
        let req = LLMRequest(model: "mock-model", messages: [])
        var received = 0
        for try await _ in try await provider.stream(req) {
            received += 1
        }
        #expect(received == 2)
    }

    @Test("Token usage")
    func tokenUsage() {
        let u = TokenUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        #expect(u.promptTokens == 100)
    }
}

@Suite("LLM content blocks")
struct LLMContentBlockTests {
    @Test("ImageBlock codable roundtrip inside Message")
    func imageBlockRoundtrip() throws {
        let image = ImageBlock(mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]),
                               width: 10, height: 20)
        let message = Message(id: "m-img", role: .user, content: [.text("看图"), .image(image)])
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.content.count == 2)
        guard case let .image(block) = decoded.content[1] else {
            Issue.record("second block should decode as image")
            return
        }
        #expect(block.mimeType == "image/png")
        #expect(block.data == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(block.width == 10)
        #expect(block.height == 20)
    }
}
