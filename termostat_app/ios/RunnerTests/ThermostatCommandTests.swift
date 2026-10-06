import XCTest
import Foundation
@testable import Runner

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
    var tokenRequests: [(forcingRefresh: Bool)] = []
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
        tokenRequests.append((forcingRefresh: forcingRefresh))
        if tokensToReturn.isEmpty {
            return "mock-token-fallback"
        }
        return tokensToReturn.removeFirst()
    }
}

final class ThermostatCommandTests: XCTestCase {
    private let validDatabaseURL = "https://termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app"

    // MARK: - Payload Tests

    func testHeatingOnPayload_containsModeOnAndTargetTemp25_doesNotContainIsHeating() {
        let command = ThermostatHeatingCommand.turnOn
        let payload = command.payload

        XCTAssertEqual(payload["mode"] as? String, "on")
        XCTAssertEqual(payload["targetTemperature"] as? Double, 25.0)
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
        XCTAssertEqual(json["targetTemperature"] as? Double, 25.0)
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
}
