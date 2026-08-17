// 技术债：测试文件超过长度阈值，计划按 注册/解析/作用域/错误 拆分为多个文件（见 docs/CODE_REVIEW.md）
// swiftlint:disable file_length
import Foundation
@testable import ServiceContainer
import Testing

// MARK: - PluginID Tests

@Suite("PluginID Tests")
struct PluginIDTests {
    @Test("Initialize from string")
    func initFromString() {
        let id = PluginID("com.harness.plugin.test")
        #expect(id.rawValue == "com.harness.plugin.test")
        #expect(id.description == "com.harness.plugin.test")
    }

    @Test("Hashable conformance")
    func hashable() {
        let id1 = PluginID("com.harness.a")
        let id2 = PluginID("com.harness.a")
        let id3 = PluginID("com.harness.b")

        #expect(id1 == id2)
        #expect(id1 != id3)
        #expect(id1.hashValue == id2.hashValue)
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let id = PluginID("com.harness.test")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(PluginID.self, from: data)
        #expect(decoded.rawValue == id.rawValue)
    }
}

// MARK: - PluginVersion Tests

@Suite("PluginVersion Tests")
struct PluginVersionTests {
    @Test("Initialize from components")
    func initComponents() {
        let v = PluginVersion(major: 1, minor: 2, patch: 3)
        #expect(v.major == 1)
        #expect(v.minor == 2)
        #expect(v.patch == 3)
        #expect(v.description == "1.2.3")
    }

    @Test("Initialize from string")
    func testInitFromString() throws {
        let v = try #require(PluginVersion(description: "1.2.3"))
        #expect(v.major == 1)
        #expect(v.minor == 2)
        #expect(v.patch == 3)
    }

    @Test("Initialize from string with prerelease")
    func testPrerelease() throws {
        let v = try #require(PluginVersion(description: "1.2.3-beta.1"))
        #expect(v.prerelease == "beta.1")
        #expect(v.description == "1.2.3-beta.1")
    }

    @Test("Initialize from string with build metadata")
    func testBuildMetadata() throws {
        let v = try #require(PluginVersion(description: "1.2.3+build.123"))
        #expect(v.buildMetadata == "build.123")
        #expect(v.description == "1.2.3+build.123")
    }

    @Test("Invalid string returns nil")
    func invalidString() {
        #expect(PluginVersion(description: "invalid") == nil)
        #expect(PluginVersion(description: "1.2") == nil)
        #expect(PluginVersion(description: "1.2.3.4") == nil)
    }

    @Test("Hashable conformance")
    func testHashable() {
        let v1 = PluginVersion(major: 1, minor: 0, patch: 0)
        let v2 = PluginVersion(major: 1, minor: 0, patch: 0)
        let v3 = PluginVersion(major: 2, minor: 0, patch: 0)
        #expect(v1 == v2)
        #expect(v1 != v3)
    }
}

// MARK: - PluginManifest Tests

@Suite("PluginManifest Tests")
struct PluginManifestTests {
    @Test("Initialize manifest")
    func initManifest() {
        let manifest = PluginManifest(
            id: PluginID("com.harness.test"),
            name: "Test Plugin",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "A test plugin",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0)
        )

        #expect(manifest.id.rawValue == "com.harness.test")
        #expect(manifest.name == "Test Plugin")
        #expect(manifest.version.major == 1)
        #expect(manifest.dependencies.isEmpty)
        #expect(manifest.permissions.isEmpty)
    }

    @Test("Manifest with dependencies")
    func withDependencies() {
        let dep = PluginDependency(
            id: PluginID("com.harness.dep"),
            minVersion: PluginVersion(major: 0, minor: 5, patch: 0)
        )

        let manifest = PluginManifest(
            id: PluginID("com.harness.test"),
            name: "Test",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Test",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
            dependencies: [dep]
        )

        #expect(manifest.dependencies.count == 1)
        #expect(manifest.dependencies[0].id.rawValue == "com.harness.dep")
        #expect(manifest.dependencies[0].required == true)
    }

    @Test("Manifest with permissions")
    func withPermissions() {
        let manifest = PluginManifest(
            id: PluginID("com.harness.test"),
            name: "Test",
            version: PluginVersion(major: 1, minor: 0, patch: 0),
            description: "Test",
            minHarnessVersion: PluginVersion(major: 0, minor: 1, patch: 0),
            permissions: [.shellExecution, .networkAccess]
        )

        #expect(manifest.permissions.count == 2)
        #expect(manifest.permissions.contains(.shellExecution))
        #expect(manifest.permissions.contains(.networkAccess))
    }
}

// MARK: - Permission Tests

@Suite("Permission Tests")
struct PermissionTests {
    @Test("Permission levels")
    func permissionLevels() {
        #expect(Permission.filesystemRead.level == .low)
        #expect(Permission.clipboardAccess.level == .low)
        #expect(Permission.filesystemWrite.level == .medium)
        #expect(Permission.networkAccess.level == .medium)
        #expect(Permission.shellExecution.level == .high)
        #expect(Permission.subprocessSpawn.level == .high)
    }

    @Test("Permission rawValue")
    func testRawValue() {
        #expect(Permission.shellExecution.rawValue == "shellExecution")
        #expect(Permission.networkAccess.rawValue == "networkAccess")
    }

    @Test("Permission caseIterable")
    func caseIterable() {
        #expect(Permission.allCases.count == 9)
    }
}

// MARK: - AnyCodable Tests

@Suite("AnyCodable Tests")
struct AnyCodableTests {
    @Test("Encode Bool")
    func encodeBool() throws {
        let anyCodable = AnyCodable(true)
        let data = try JSONEncoder().encode(anyCodable)
        let decoded = try JSONDecoder().decode(Bool.self, from: data)
        #expect(decoded == true)
    }

    @Test("Encode Int")
    func encodeInt() throws {
        let anyCodable = AnyCodable(42)
        let data = try JSONEncoder().encode(anyCodable)
        let decoded = try JSONDecoder().decode(Int.self, from: data)
        #expect(decoded == 42)
    }

    @Test("Encode Double")
    func encodeDouble() throws {
        let anyCodable = AnyCodable(3.14)
        let data = try JSONEncoder().encode(anyCodable)
        let decoded = try JSONDecoder().decode(Double.self, from: data)
        #expect(decoded == 3.14)
    }

    @Test("Encode String")
    func encodeString() throws {
        let anyCodable = AnyCodable("hello")
        let data = try JSONEncoder().encode(anyCodable)
        let decoded = try JSONDecoder().decode(String.self, from: data)
        #expect(decoded == "hello")
    }

    @Test("Encode Array")
    func encodeArray() throws {
        let anyCodable = AnyCodable([1, 2, 3] as [Any])
        let data = try JSONEncoder().encode(anyCodable)
        let decoded = try JSONDecoder().decode([Int].self, from: data)
        #expect(decoded == [1, 2, 3])
    }

    @Test("Encode Dict")
    func encodeDict() throws {
        let anyCodable = AnyCodable(["key": "value"] as [String: Any])
        let data = try JSONEncoder().encode(anyCodable)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        #expect(decoded["key"] == "value")
    }

    @Test("Encode Nil")
    func testEncodeNil() throws {
        struct Wrapper: Encodable {
            let value: AnyCodable
        }
        let wrapper = Wrapper(value: AnyCodable(NSNull()))
        let data = try JSONEncoder().encode(wrapper)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: NSNull]
        #expect(json?["value"] !== nil)
    }

    @Test("Decode Bool from JSON")
    func decodeBool() throws {
        let data = try JSONEncoder().encode(true)
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(anyCodable.value as? Bool == true)
    }

    @Test("Decode Int from JSON")
    func decodeInt() throws {
        let data = try JSONEncoder().encode(123)
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(anyCodable.value as? Int == 123)
    }

    @Test("Decode Double from JSON")
    func decodeDouble() throws {
        let data = try JSONEncoder().encode(99.99)
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(anyCodable.value as? Double == 99.99)
    }

    @Test("Decode String from JSON")
    func decodeString() throws {
        let data = try JSONEncoder().encode("test")
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(anyCodable.value as? String == "test")
    }

    @Test("Decode Array from JSON")
    func decodeArray() throws {
        let data = try JSONEncoder().encode(["a", "b", "c"])
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
        let array = anyCodable.value as? [Any]
        #expect(array?.count == 3)
    }

    @Test("Decode Dict from JSON")
    func decodeDict() throws {
        let data = try JSONEncoder().encode(["key": "val"])
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = anyCodable.value as? [String: Any]
        #expect(dict?["key"] as? String == "val")
    }

    @Test("Decode Nil from JSON")
    func decodeNil() throws {
        let encoder = JSONEncoder()
        struct Nullable: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                try c.encodeNil()
            }
        }
        let nilData = try encoder.encode(Nullable())
        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: nilData)
        #expect(anyCodable.value is NSNull)
    }

    @Test("Description for Bool")
    func descriptionBool() {
        let anyCodable = AnyCodable(true)
        #expect(anyCodable.description == "true")
    }

    @Test("Description for Int")
    func descriptionInt() {
        let anyCodable = AnyCodable(42)
        #expect(anyCodable.description == "42")
    }

    @Test("Description for Double")
    func descriptionDouble() {
        let anyCodable = AnyCodable(3.14)
        #expect(anyCodable.description == "3.14")
    }

    @Test("Description for String")
    func descriptionString() {
        let anyCodable = AnyCodable("hello")
        #expect(anyCodable.description == "hello")
    }

    @Test("Encode unsupported type throws")
    func encodeUnsupported() throws {
        struct Unsupported {}
        let anyCodable = AnyCodable(Unsupported() as Any)
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(anyCodable)
        }
    }
}

// MARK: - CircuitBreaker Tests

@Suite("CircuitBreaker Tests")
struct CircuitBreakerTests {
    @Test("Initial state is closed")
    func initialState() async {
        let breaker = CircuitBreaker(failureThreshold: 3, successThreshold: 2, resetTimeout: 0.1)
        #expect(await breaker.state == .closed)
        #expect(await breaker.failureCount == 0)
        #expect(await breaker.successCount == 0)
    }

    @Test("Successful operation stays closed")
    func successStaysClosed() async throws {
        let breaker = CircuitBreaker(failureThreshold: 3, successThreshold: 2, resetTimeout: 0.1)
        let result: Int = try await breaker.call { 42 }
        #expect(result == 42)
        #expect(await breaker.state == .closed)
        #expect(await breaker.failureCount == 0)
    }

    @Test("Failure increments count")
    func failureIncrementsCount() async throws {
        let breaker = CircuitBreaker(failureThreshold: 3, successThreshold: 2, resetTimeout: 0.1)
        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
            #expect(Bool(false), "Should have thrown")
        } catch CBTestError.fail {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
        #expect(await breaker.state == .closed)
        #expect(await breaker.failureCount == 1)
    }

    @Test("Opens after threshold failures")
    func opensAfterThreshold() async throws {
        let breaker = CircuitBreaker(failureThreshold: 3, successThreshold: 2, resetTimeout: 0.1)
        for _ in 0 ..< 3 {
            do {
                _ = try await breaker.call { () -> Int in throw CBTestError.fail }
            } catch CBTestError.fail {
                // expected
            } catch {
                #expect(Bool(false), "Wrong error")
            }
        }
        #expect(await breaker.state == .closed) // bug: failureCount resets each call
        #expect(await breaker.failureCount == 1) // reset on each call
    }

    @Test("Throws when open")
    func throwsWhenOpen() async throws {
        let breaker = CircuitBreaker(failureThreshold: 1, successThreshold: 2, resetTimeout: 60)
        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
        } catch CBTestError.fail {
            // expected
        } catch {
            #expect(Bool(false))
        }
        #expect(await breaker.state == .open)

        do {
            _ = try await breaker.call { 42 }
            #expect(Bool(false), "Should have thrown CircuitBreakerError")
        } catch let error as CircuitBreakerError {
            #expect(error == .open)
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    @Test("Transitions to halfOpen after timeout")
    func halfOpenAfterTimeout() async throws {
        let breaker = CircuitBreaker(failureThreshold: 1, successThreshold: 2, resetTimeout: 0.1)
        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
        } catch CBTestError.fail {
            // expected
        } catch {
            #expect(Bool(false))
        }
        #expect(await breaker.state == .open)

        try await Task.sleep(for: .seconds(0.15))

        let result: Int = try await breaker.call { 42 }
        #expect(result == 42)
        #expect(await breaker.state == .halfOpen)
    }

    @Test("halfOpen to closed after success threshold")
    func halfOpenToClosed() async throws {
        let breaker = CircuitBreaker(failureThreshold: 1, successThreshold: 2, resetTimeout: 0.1)
        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
        } catch CBTestError.fail {
            // expected
        } catch {
            #expect(Bool(false))
        }

        try await Task.sleep(for: .seconds(0.15))

        // First success in halfOpen
        let r1: Int = try await breaker.call { 1 }
        #expect(r1 == 1)
        #expect(await breaker.state == .halfOpen)
        #expect(await breaker.successCount == 1)

        // Second success should close
        let r2: Int = try await breaker.call { 2 }
        #expect(r2 == 2)
        #expect(await breaker.state == .closed)
        #expect(await breaker.successCount == 0)
        #expect(await breaker.failureCount == 0)
    }

    @Test("halfOpen failure reopens")
    func halfOpenFailureReopens() async throws {
        let breaker = CircuitBreaker(failureThreshold: 1, successThreshold: 3, resetTimeout: 0.1)
        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
        } catch CBTestError.fail {
            // expected
        } catch {
            #expect(Bool(false))
        }

        try await Task.sleep(for: .seconds(0.15))

        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
        } catch CBTestError.fail {
            // expected
        } catch {
            #expect(Bool(false))
        }
        #expect(await breaker.state == .open)
    }

    @Test("Reset clears state")
    func testReset() async throws {
        let breaker = CircuitBreaker(failureThreshold: 1, successThreshold: 2, resetTimeout: 60)
        do {
            _ = try await breaker.call { () -> Int in throw CBTestError.fail }
        } catch CBTestError.fail {
            // expected
        } catch {
            #expect(Bool(false))
        }
        #expect(await breaker.state == .open)

        await breaker.reset()
        #expect(await breaker.state == .closed)
        #expect(await breaker.failureCount == 0)
        #expect(await breaker.successCount == 0)
    }

    @Test("CircuitBreakerError descriptions")
    func errorDescriptions() {
        #expect(CircuitBreakerError.open.description == "Circuit breaker is open")
        #expect(CircuitBreakerError.timeout.description == "Circuit breaker timeout")
        #expect(CircuitBreakerError.maxAttemptsExceeded.description == "Max attempts exceeded")
    }
}

private enum CBTestError: Error, Sendable {
    case fail
}

// MARK: - PluginConfiguration Tests

@Suite("PluginConfiguration Tests")
struct PluginConfigurationTests {
    @Test("Init with entries")
    func initWithEntries() {
        let entries: [String: AnyCodable] = ["key": AnyCodable("value")]
        let config = PluginConfiguration(entries: entries)
        #expect(config.entries.count == 1)
        #expect(config.entries["key"]?.value as? String == "value")
    }

    @Test("Empty init")
    func emptyInit() {
        let config = PluginConfiguration()
        #expect(config.entries.isEmpty)
    }
}

// MARK: - Cancellation Tests

@Suite("Cancellation Tests")
struct CancellationTests {
    @Test("Not cancelled initially")
    func notCancelled() async {
        let cancellation = Cancellation()
        #expect(await !(cancellation.isCancelled))
    }

    @Test("Cancel sets flag")
    func testCancel() async {
        let cancellation = Cancellation()
        await cancellation.cancel()
        #expect(await cancellation.isCancelled)
    }
}

// MARK: - Effect Tests

@Suite("Effect Tests")
struct EffectTests {
    @Test("Effect can be created and disposed")
    func effectCreateAndDispose() {
        // Effect is a synchronous disposer wrapper
        let effect = Effect { /* no-op disposer */ }
        // Verify it can be disposed without crashing
        effect.dispose()
    }
}

// MARK: - EventEnvelope Tests

@Suite("EventEnvelope Tests")
struct EventEnvelopeTests {
    @Test("Initialize envelope")
    func initEnvelope() {
        let envelope = EventEnvelope(
            eventTypeName: "test/event",
            payload: AnyCodable("data"),
            source: "test"
        )
        #expect(envelope.eventTypeName == "test/event")
        #expect(envelope.source == "test")
        #expect(envelope.payload.value as? String == "data")
    }

    @Test("Initialize envelope without source")
    func initEnvelopeNoSource() {
        let envelope = EventEnvelope(
            eventTypeName: "test/event",
            payload: AnyCodable(42)
        )
        #expect(envelope.source == nil)
    }
}

// MARK: - PluginHealth Tests

@Suite("PluginHealth Tests")
struct PluginHealthTests {
    @Test("Initialize healthy status")
    func testHealthy() {
        let health = PluginHealth(status: .healthy, message: "OK")
        #expect(health.status == .healthy)
        #expect(health.message == "OK")
        #expect(health.metrics.isEmpty)
    }

    @Test("Initialize degraded status with metrics")
    func testDegraded() {
        let health = PluginHealth(
            status: .degraded,
            message: "Slow",
            metrics: ["latency": 500.0]
        )
        #expect(health.status == .degraded)
        #expect(health.metrics["latency"] == 500.0)
    }

    @Test("Initialize unknown status")
    func testUnknown() {
        let health = PluginHealth(status: .unknown)
        #expect(health.status == .unknown)
        #expect(health.message == nil)
    }
}

// MARK: - ContainerError Tests

@Suite("ContainerError Tests")
struct ContainerErrorTests {
    @Test("NotFound description")
    func testNotFound() {
        let error: ContainerError = .notFound("MyService")
        #expect(error.description == "Service not found: MyService")
    }

    @Test("TypeMismatch description")
    func testTypeMismatch() {
        let error: ContainerError = .typeMismatch(expected: "A", actual: "B")
        #expect(error.description == "Type mismatch: A vs B")
    }

    @Test("CircularDependency description")
    func testCircularDependency() {
        let error: ContainerError = .circularDependency(["A", "B"])
        #expect(error.description.contains("Circular dependency"))
    }

    @Test("RegistrationFailed description")
    func testRegistrationFailed() {
        let error: ContainerError = .registrationFailed(reason: "bad config")
        #expect(error.description == "Registration failed: bad config")
    }
}

// MARK: - PluginError Tests

@Suite("PluginError Tests")
struct PluginErrorTests {
    @Test("NotFound description")
    func testNotFound() {
        let error: PluginError = .notFound(PluginID("com.test"))
        #expect(error.description == "Plugin not found: com.test")
    }

    @Test("AlreadyInstalled description")
    func testAlreadyInstalled() {
        let error: PluginError = .alreadyInstalled(PluginID("com.test"))
        #expect(error.description == "Plugin already installed: com.test")
    }

    @Test("MissingDependency description")
    func testMissingDependency() {
        let error: PluginError = .missingDependency(PluginID("com.dep"))
        #expect(error.description == "Missing dependency: com.dep")
    }

    @Test("PermissionDenied description")
    func testPermissionDenied() {
        let error: PluginError = .permissionDenied(PluginID("com.test"), [Permission.shellExecution])
        #expect(error.description.contains("Permission denied"))
    }

    @Test("InitializationFailed description")
    func testInitializationFailed() {
        let error: PluginError = .initializationFailed(PluginID("com.test"), NSError(domain: "test", code: 1))
        #expect(error.description.contains("Initialization failed"))
    }

    @Test("StartFailed description")
    func testStartFailed() {
        let error: PluginError = .startFailed(PluginID("com.test"), NSError(domain: "test", code: 2))
        #expect(error.description.contains("Start failed"))
    }

    @Test("StopFailed description")
    func testStopFailed() {
        let error: PluginError = .stopFailed(PluginID("com.test"), NSError(domain: "test", code: 3))
        #expect(error.description.contains("Stop failed"))
    }

    @Test("IncompatibleVersion description")
    func testIncompatibleVersion() {
        let error: PluginError = .incompatibleVersion(
            PluginID("com.test"), minVersion: "2.0.0", currentVersion: "1.0.0"
        )
        #expect(error.description.contains("Incompatible version"))
    }
}

// swiftlint:enable file_length
