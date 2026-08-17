import Foundation
@testable import ServiceContainer
import Testing

private final class TestService: Sendable { let id = UUID() }

@Suite("ServiceContainer Tests")
struct ServiceContainerTests {
    @Test("Register and resolve instance")
    func registerInstance() async throws {
        let container = ServiceContainer()
        let service = TestService()
        await container.register(service, for: TestService.self)
        let resolved = try await container.resolve(TestService.self)
        #expect(resolved === service)
    }

    @Test("Single scope caches")
    func singleScope() async throws {
        let container = ServiceContainer()
        await container.register(TestService(), for: TestService.self)
        let r1 = try await container.resolve(TestService.self)
        let r2 = try await container.resolve(TestService.self)
        #expect(r1 === r2)
    }

    @Test("Throws when not found")
    func notFound() async {
        let container = ServiceContainer()
        do {
            _ = try await container.resolve(TestService.self)
            Issue.record("Expected error")
        } catch {}
    }

    @Test("tryResolve returns nil for missing")
    func tryResolveNil() async {
        let container = ServiceContainer()
        let result: TestService? = await container.tryResolve(TestService.self)
        #expect(result == nil)
    }

    @Test("isRegistered checks registration")
    func testIsRegistered() async {
        let container = ServiceContainer()
        #expect(await container.isRegistered(TestService.self) == false)
        await container.register(TestService(), for: TestService.self)
        #expect(await container.isRegistered(TestService.self) == true)
    }

    @Test("Clear removes service")
    func testClear() async {
        let container = ServiceContainer()
        await container.register(TestService(), for: TestService.self)
        await container.clear(TestService.self)
        #expect(await container.isRegistered(TestService.self) == false)
    }

    @Test("Reset clears all")
    func testReset() async {
        let container = ServiceContainer()
        await container.register(TestService(), for: TestService.self)
        await container.reset()
        #expect(await container.isRegistered(TestService.self) == false)
    }
}
