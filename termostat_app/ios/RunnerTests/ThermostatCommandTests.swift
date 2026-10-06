import XCTest
import Foundation
@testable import Runner

// MARK: - Mocks

public struct TokenRequest: Equatable, Sendable {
    public let forcingRefresh: Bool

    public init(forcingRefresh: Bool) {
        self.forcingRefresh = forcingRefresh
    }
}

final class MockHTTPRequestPerformer: HTTPRequestPerforming, @unchecked Sendable {
    private let lock = NSLock()
    var requests: [URLRequest] = []
    var responseQueue: [(statusCode: Int, data: Data?, error: Error?)] = []

    func enqueueResponse(statusCode: Int, data: Data? = "{}".data(using: .utf8), error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }
        responseQueue.append((statusCode, data, error))
    }

    func performData(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        guard !responseQueue.isEmpty else {
            lock.unlock()
            let dummyResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return ("{}".data(using: .utf8)!, dummyResponse)
        }
        let next = responseQueue.removeFirst()
        lock.unlock()

        if let error = next.error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (next.data ?? Data(), response)
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }
}

final class MockAuthSessionProvider: ThermostatAuthSessionProviding, @unchecked Sendable {
    private let lock = NSLock()
    var shouldFailAuthWait: Error?
    var authWaitDelayNanoseconds: UInt64 = 0
    var tokensToReturn: [String] = ["mock-token-1", "mock-token-refreshed"]
    var tokenRequests: [TokenRequest] = []
    var ensureAuthCalled = false

    func ensureUserAuthenticated(timeout: TimeInterval) async throws {
        lock.lock()
        ensureAuthCalled = true
        let failError = shouldFailAuthWait
        let delay = authWaitDelayNanoseconds
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }

        if let error = failError {
            throw error
        }
    }

    func getValidIDToken(forcingRefresh: Bool) async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        tokenRequests.append(TokenRequest(forcingRefresh: forcingRefresh))
        if tokensToReturn.isEmpty {
            return "mock-token-fallback"
        }
        return tokensToReturn.removeFirst()
    }
}

final class MockAuthSessionListener: AuthSessionListenerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    var isListenerRegistered = false
    var unregisterCallCount = 0
    var listenerCallback: (@Sendable (Bool) -> Void)?
    var onRegistration: (@Sendable () -> Void)?
    var hasCurrentUserValue = false

    func registerAuthStateListener(_ listener: @escaping @Sendable (Bool) -> Void) -> AnyObject {
        lock.lock()
        isListenerRegistered = true
        self.listenerCallback = listener
        let regCallback = onRegistration
        lock.unlock()

        regCallback?()
        return "mock-auth-handle" as AnyObject
    }

    func unregisterAuthStateListener(_ handle: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        isListenerRegistered = false
        unregisterCallCount += 1
        self.listenerCallback = nil
    }

    var hasCurrentUser: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasCurrentUserValue
    }

    func setHasCurrentUser(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        hasCurrentUserValue = value
    }

    func triggerCallback(hasUser: Bool) {
        let cb: (@Sendable (Bool) -> Void)?
        lock.lock()
        cb = listenerCallback
        lock.unlock()
        cb?(hasUser)
    }
}

/// A mock auth session listener that fires its callback SYNCHRONOUSLY during registration
final class SynchronousMockAuthSessionListener: AuthSessionListenerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    var unregisterCallCount = 0
    let userResultToReturn: Bool

    init(userResultToReturn: Bool) {
        self.userResultToReturn = userResultToReturn
    }

    func registerAuthStateListener(_ listener: @escaping @Sendable (Bool) -> Void) -> AnyObject {
        // Synchronously invoke callback during registration to test deadlock-free execution
        listener(userResultToReturn)
        return "sync-handle" as AnyObject
    }

    func unregisterAuthStateListener(_ handle: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        unregisterCallCount += 1
    }

    var hasCurrentUser: Bool {
        return userResultToReturn
    }
}

// MARK: - Unit Tests

final class ThermostatCommandTests: XCTestCase {
    private let validDatabaseURL = "https://termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app"

    // MARK: - Payload Tests

    func testHeatingOnPayload_containsOnlyModeOn_preservesTargetTemperatureAndRelay() {
        let command = ThermostatHeatingCommand.turnOn
        let payload = command.payload

        XCTAssertEqual(payload["mode"] as? String, "on")
        XCTAssertNil(payload["targetTemperature"], "turnOn must preserve the saved target temperature")
        XCTAssertEqual(payload.count, 1)
        XCTAssertNil(payload["isHeating"], "turnOn payload must not set isHeating; relay decision belongs to firmware")
    }

    func testHeatingOffPayload_containsModeOffAndIsHeatingFalse_doesNotModifyTargetTemp() {
        let command = ThermostatHeatingCommand.turnOff
        let payload = command.payload

        XCTAssertEqual(payload["mode"] as? String, "off")
        XCTAssertEqual(payload["isHeating"] as? Bool, false)
        XCTAssertNil(payload["targetTemperature"], "turnOff payload must not alter target temperature")
    }

    // MARK: - URL and Request Construction Tests

    func testBuildRequest_constructsValidHttpsPatchRequestWithAuthQuery() throws {
        let request = try ThermostatCommandService.buildRequest(
            databaseURL: validDatabaseURL,
            deviceID: "device1",
            token: "secret-test-token",
            command: .turnOn
        )

        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid request URL")
            return
        }

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app")
        XCTAssertEqual(components.path, "/devices/device1.json")

        let authQuery = components.queryItems?.first(where: { $0.name == "auth" })?.value
        XCTAssertEqual(authQuery, "secret-test-token")

        guard let bodyData = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            XCTFail("Invalid body json")
            return
        }

        XCTAssertEqual(json["mode"] as? String, "on")
        XCTAssertNil(json["targetTemperature"], "turnOn PATCH must not change target temperature")
        XCTAssertNil(json["isHeating"])
        XCTAssertEqual(json.count, 1)
    }

    func testBuildRequest_rejectsInvalidOrInsecureDatabaseURL() {
        XCTAssertThrowsError(
            try ThermostatCommandService.buildRequest(
                databaseURL: "http://insecure.firebasedatabase.app",
                deviceID: "device1",
                token: "token",
                command: .turnOn
            )
        ) { error in
            XCTAssertEqual(error as? ThermostatCommandError, .invalidDatabaseURL)
        }

        XCTAssertThrowsError(
            try ThermostatCommandService.buildRequest(
                databaseURL: "https://user:pass@evil.com",
                deviceID: "device1",
                token: "token",
                command: .turnOn
            )
        ) { error in
            XCTAssertEqual(error as? ThermostatCommandError, .invalidDatabaseURL)
        }
    }

    // MARK: - Authentication Readiness & Waiting

    func testSend_whenUserNotSignedIn_throwsSignInRequiredWithoutNetworkRequest() async {
        let mockTransport = MockHTTPRequestPerformer()
        let mockAuth = MockAuthSessionProvider()
        mockAuth.shouldFailAuthWait = ThermostatCommandError.signInRequired

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected signInRequired error")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .signInRequired)
            XCTAssertEqual(mockTransport.requestCount, 0, "No network request should be sent when auth is missing")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_whenAuthInitialWaitSucceedsAfterDelay_sendsCommandSuccessfully() async throws {
        let mockTransport = MockHTTPRequestPerformer()
        mockTransport.enqueueResponse(statusCode: 200)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.authWaitDelayNanoseconds = 10_000_000 // 10ms delay simulating Keychain restore
        mockAuth.tokensToReturn = ["valid-restored-token"]

        try await ThermostatCommandService.send(
            .turnOn,
            databaseURL: validDatabaseURL,
            authProvider: mockAuth,
            networkSession: mockTransport
        )

        XCTAssertTrue(mockAuth.ensureAuthCalled)
        XCTAssertEqual(mockTransport.requestCount, 1)
    }

    func testSend_whenAuthTimesOut_throwsTimedOutErrorWithoutNetworkRequest() async {
        let mockTransport = MockHTTPRequestPerformer()
        let mockAuth = MockAuthSessionProvider()
        mockAuth.shouldFailAuthWait = ThermostatCommandError.timedOut

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected timedOut error")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .timedOut)
            XCTAssertEqual(mockTransport.requestCount, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Coordinator Lifetime, Concurrency & Deadlock Tests

    func testAuthCoordinatorHolder_preCancellation_immediatelyCancelsCoordinator() async {
        let holder = AuthCoordinatorHolder()
        let mockSource = MockAuthSessionListener()
        defer { holder.clearCoordinator() }

        // Cancel holder BEFORE coordinator is assigned
        holder.cancel()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource, continuation: continuation)
                holder.setCoordinator(coordinator)
                coordinator.start(timeout: 5.0)
            }
            XCTFail("Expected cancelled error")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(mockSource.unregisterCallCount, 0, "Listener should not remain registered")
    }

    func testAuthCoordinatorHolder_delayedCallbackAfterContinuationSetupReturns_retainsAndCompletes() async throws {
        let holder = AuthCoordinatorHolder()
        let mockSource = MockAuthSessionListener()
        defer { holder.clearCoordinator() }

        // Trigger delayed callback strictly after listener registration has completed
        mockSource.onRegistration = { [weak mockSource] in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak mockSource] in
                mockSource?.triggerCallback(hasUser: true)
            }
        }

        // Holder retains coordinator strongly so continuation completion succeeds after setup scope exits
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource, continuation: continuation)
            holder.setCoordinator(coordinator)
            coordinator.start(timeout: 5.0)
        }

        XCTAssertEqual(mockSource.unregisterCallCount, 1)
        XCTAssertFalse(mockSource.isListenerRegistered)
    }

    func testAuthStateListenerCoordinator_synchronousCallback_doesNotDeadlockAndCleansUpHandle() async throws {
        let syncSource = SynchronousMockAuthSessionListener(userResultToReturn: true)
        let holder = AuthCoordinatorHolder()
        defer { holder.clearCoordinator() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = AuthStateListenerCoordinator(authListenerSource: syncSource, continuation: continuation)
            holder.setCoordinator(coordinator)
            coordinator.start(timeout: 5.0)
        }

        XCTAssertEqual(syncSource.unregisterCallCount, 1, "Synchronous callback must trigger handle cleanup without deadlock")
    }

    func testAuthStateListenerCoordinator_timeoutActuallyCompletes() async {
        let mockSource = MockAuthSessionListener()
        let holder = AuthCoordinatorHolder()
        defer { holder.clearCoordinator() }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource, continuation: continuation)
                holder.setCoordinator(coordinator)
                // Use a short 0.05s timeout
                coordinator.start(timeout: 0.05)
            }
            XCTFail("Expected timedOut error")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .timedOut)
            XCTAssertEqual(mockSource.unregisterCallCount, 1)
            XCTAssertFalse(mockSource.isListenerRegistered)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthStateListenerCoordinator_doubleCallback_resumesOnceAndUnregistersOnce() async throws {
        let mockSource = MockAuthSessionListener()
        let holder = AuthCoordinatorHolder()
        defer { holder.clearCoordinator() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource, continuation: continuation)
            holder.setCoordinator(coordinator)
            coordinator.start(timeout: 5.0)

            // Trigger callback twice
            mockSource.triggerCallback(hasUser: true)
            mockSource.triggerCallback(hasUser: true)
        }

        XCTAssertEqual(mockSource.unregisterCallCount, 1, "Unregister must be called exactly once")
        XCTAssertFalse(mockSource.isListenerRegistered)
    }

    func testAuthStateListenerCoordinator_timeoutVsCallbackRace_deterministicSingleResolution() async {
        let mockSource = MockAuthSessionListener()
        let holder = AuthCoordinatorHolder()
        defer { holder.clearCoordinator() }

        var didComplete = false
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource, continuation: continuation)
                holder.setCoordinator(coordinator)
                coordinator.start(timeout: 5.0)

                // Race: fire callback and timeout concurrently on two queues
                DispatchQueue.global().async {
                    coordinator.handleAuthStateUpdate(hasUser: true)
                }
                DispatchQueue.global().async {
                    coordinator.handleTimeout()
                }
            }
            didComplete = true
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .timedOut)
            didComplete = true
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(didComplete, "Continuation must resume exactly once")
        XCTAssertEqual(mockSource.unregisterCallCount, 1, "Listener must be unregistered exactly once")
        XCTAssertFalse(mockSource.isListenerRegistered)
    }

    func testAuthStateListenerCoordinator_listenerCleanup_onFailureAndCancellation() async {
        // Test failure path
        let mockSource1 = MockAuthSessionListener()
        let holder1 = AuthCoordinatorHolder()
        defer { holder1.clearCoordinator() }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource1, continuation: continuation)
                holder1.setCoordinator(coordinator)
                coordinator.start(timeout: 5.0)
                mockSource1.triggerCallback(hasUser: false)
            }
            XCTFail("Expected signInRequired")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .signInRequired)
            XCTAssertEqual(mockSource1.unregisterCallCount, 1)
            XCTAssertFalse(mockSource1.isListenerRegistered)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Test cancel path
        let mockSource2 = MockAuthSessionListener()
        let holder2 = AuthCoordinatorHolder()
        defer { holder2.clearCoordinator() }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = AuthStateListenerCoordinator(authListenerSource: mockSource2, continuation: continuation)
                holder2.setCoordinator(coordinator)
                coordinator.start(timeout: 5.0)
                coordinator.cancel()
            }
            XCTFail("Expected cancelled")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .cancelled)
            XCTAssertEqual(mockSource2.unregisterCallCount, 1)
            XCTAssertFalse(mockSource2.isListenerRegistered)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - HTTP Status Codes & Retry Semantics

    func testSend_http200_succeeds() async throws {
        let mockTransport = MockHTTPRequestPerformer()
        mockTransport.enqueueResponse(statusCode: 200)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["token-1"]

        try await ThermostatCommandService.send(
            .turnOn,
            databaseURL: validDatabaseURL,
            authProvider: mockAuth,
            networkSession: mockTransport
        )

        XCTAssertEqual(mockTransport.requestCount, 1)
        XCTAssertEqual(mockAuth.tokenRequests.count, 1)
        XCTAssertFalse(mockAuth.tokenRequests[0].forcingRefresh)
    }

    func testSend_http401_retriesWithRefreshedTokenOnceAndSucceeds() async throws {
        let mockTransport = MockHTTPRequestPerformer()
        mockTransport.enqueueResponse(statusCode: 401)
        mockTransport.enqueueResponse(statusCode: 200)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["stale-token", "fresh-token"]

        try await ThermostatCommandService.send(
            .turnOff,
            databaseURL: validDatabaseURL,
            authProvider: mockAuth,
            networkSession: mockTransport
        )

        XCTAssertEqual(mockTransport.requestCount, 2)
        XCTAssertEqual(mockAuth.tokenRequests.count, 2)
        XCTAssertFalse(mockAuth.tokenRequests[0].forcingRefresh)
        XCTAssertTrue(mockAuth.tokenRequests[1].forcingRefresh)
    }

    func testSend_repeated401_throwsAuthorizationDeniedWithoutInfiniteLoop() async {
        let mockTransport = MockHTTPRequestPerformer()
        mockTransport.enqueueResponse(statusCode: 401)
        mockTransport.enqueueResponse(statusCode: 401)
        mockTransport.enqueueResponse(statusCode: 200) // extra response that must NOT be reached

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["stale-token", "fresh-token"]

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected authorizationDenied")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .authorizationDenied)
            XCTAssertEqual(mockTransport.requestCount, 2, "Must stop after exactly 1 refresh retry")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_http403_throwsAuthorizationDeniedImmediatelyWithoutRetry() async {
        let mockTransport = MockHTTPRequestPerformer()
        mockTransport.enqueueResponse(statusCode: 403)
        mockTransport.enqueueResponse(statusCode: 200)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["token-1", "token-2"]

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected authorizationDenied")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .authorizationDenied)
            XCTAssertEqual(mockTransport.requestCount, 1, "403 must not trigger a token refresh or retry")
            XCTAssertEqual(mockAuth.tokenRequests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_http500_throwsRequestFailed() async {
        let mockTransport = MockHTTPRequestPerformer()
        mockTransport.enqueueResponse(statusCode: 500)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["token-1"]

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected requestFailed")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .requestFailed(500))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_networkUnavailable_mapsURLErrorCorrectly() async {
        let mockTransport = MockHTTPRequestPerformer()
        let networkError = URLError(.notConnectedToInternet)
        mockTransport.enqueueResponse(statusCode: 0, error: networkError)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["token-1"]

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected networkUnavailable")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .networkUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSend_requestTimedOut_mapsURLErrorCorrectly() async {
        let mockTransport = MockHTTPRequestPerformer()
        let timeoutError = URLError(.timedOut)
        mockTransport.enqueueResponse(statusCode: 0, error: timeoutError)

        let mockAuth = MockAuthSessionProvider()
        mockAuth.tokensToReturn = ["token-1"]

        do {
            try await ThermostatCommandService.send(
                .turnOn,
                databaseURL: validDatabaseURL,
                authProvider: mockAuth,
                networkSession: mockTransport
            )
            XCTFail("Expected timedOut")
        } catch let error as ThermostatCommandError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    // MARK: - Variable Temperature Commands

    func testSetTemperaturePayload_setsTargetAndMode_withoutForcingRelay() throws {
        let command = ThermostatHeatingCommand.setTemperature(23.0)
        try command.validate()
        XCTAssertEqual(command.payload["mode"] as? String, "on")
        XCTAssertEqual(command.payload["targetTemperature"] as? Double, 23.0)
        XCTAssertNil(command.payload["isHeating"])
    }

    func testSetTemperatureValidation_acceptsBoundariesAndDecimals() throws {
        for value in [10.0, 22.5, 30.0] {
            try ThermostatHeatingCommand.setTemperature(value).validate()
        }
    }

    func testSetTemperatureInvalidValues_doNotAuthenticateOrSend() async {
        for value in [9.0, 31.0, Double.nan, Double.infinity, -Double.infinity] {
            let auth = MockAuthSessionProvider()
            let transport = MockHTTPRequestPerformer()
            do {
                try await ThermostatCommandService.send(
                    .setTemperature(value),
                    databaseURL: validDatabaseURL,
                    authProvider: auth,
                    networkSession: transport
                )
                XCTFail("Expected invalidTemperature")
            } catch {
                XCTAssertEqual(error as? ThermostatCommandError, .invalidTemperature)
            }
            XCTAssertFalse(auth.ensureAuthCalled)
            XCTAssertEqual(transport.requestCount, 0)
        }
    }

    func testSetTemperatureRequest_containsAtomicModeAndTarget() throws {
        let request = try ThermostatCommandService.buildRequest(
            databaseURL: validDatabaseURL,
            deviceID: "device1",
            token: "test-token",
            command: .setTemperature(22.5)
        )
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(payload["mode"] as? String, "on")
        XCTAssertEqual(payload["targetTemperature"] as? Double, 22.5)
        XCTAssertNil(payload["isHeating"])
    }
    // MARK: - Widget Snapshot Parsing

    func testWidgetSnapshot_parsesRealTelemetryAndRelayState() throws {
        let json = #"{"currentTemperature":22.4,"currentHumidity":48,"targetTemperature":23,"mode":"on","isHeating":false}"#
        let snapshot = try WidgetSnapshot.fromDeviceJSON(Data(json.utf8))
        XCTAssertEqual(snapshot.temperature, 22.4)
        XCTAssertEqual(snapshot.humidity, 48)
        XCTAssertEqual(snapshot.targetTemperature, 23)
        XCTAssertEqual(snapshot.isHeating, false)
        XCTAssertEqual(snapshot.mode, "on")
    }

    func testWidgetSnapshot_missingReadings_areNotInvented() throws {
        let json = #"{"mode":"on","targetTemperature":23}"#
        let snapshot = try WidgetSnapshot.fromDeviceJSON(Data(json.utf8))
        XCTAssertNil(snapshot.temperature)
        XCTAssertNil(snapshot.humidity)
        XCTAssertNil(snapshot.isHeating)
    }

    func testWidgetSnapshot_rejectsBooleanNumbersAndInvalidRanges() throws {
        let json = #"{"currentTemperature":true,"currentHumidity":110,"targetTemperature":31,"mode":"invalid","isHeating":1}"#
        let snapshot = try WidgetSnapshot.fromDeviceJSON(Data(json.utf8))
        XCTAssertNil(snapshot.temperature)
        XCTAssertNil(snapshot.humidity)
        XCTAssertNil(snapshot.targetTemperature)
        XCTAssertNil(snapshot.mode)
        XCTAssertNil(snapshot.isHeating)
    }

    func testWidgetSnapshot_commandAck_doesNotMakeOldSensorDataFresh() {
        let snapshot = WidgetSnapshot(
            temperature: 22.4, targetTemperature: 23, mode: "on",
            observedAtMilliseconds: Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000,
            commandAtMilliseconds: Date().timeIntervalSince1970 * 1000
        )
        XCTAssertTrue(snapshot.isStale)
        XCTAssertTrue(snapshot.hasPendingCommand)
    }

    func testWidgetSnapshot_codablesMatchSharedJSONSchema() throws {
        let json = #"{"temperature":22.4,"humidity":48,"targetTemperature":23,"mode":"on","isHeating":false,"observedAtMilliseconds":1800000000000,"commandAtMilliseconds":null}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.temperature, 22.4)
        XCTAssertFalse(snapshot.hasPendingCommand)
        XCTAssertEqual(snapshot.observedDate?.timeIntervalSince1970, 1800000000)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }
}
