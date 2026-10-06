import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// MARK: - Errors

public enum ThermostatCommandError: LocalizedError, Equatable {
    case missingConfiguration
    case signInRequired
    case invalidDatabaseURL
    case authorizationDenied
    case requestFailed(Int)
    case invalidResponse
    case networkUnavailable
    case timedOut
    case cancelled
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Termostat bağlantı yapılandırması bulunamadı."
        case .signInRequired:
            return "Önce Termostat uygulamasında giriş yapmalısınız."
        case .invalidDatabaseURL:
            return "Termostat bağlantı adresi geçersiz."
        case .authorizationDenied:
            return "Bu termostatı kontrol etme yetkiniz doğrulanamadı."
        case .requestFailed(let status):
            return "Komut gönderilemedi. HTTP hata kodu: \(status)."
        case .invalidResponse:
            return "Sunucudan geçerli bir yanıt alınamadı."
        case .networkUnavailable:
            return "İnternet bağlantısı kurulamadı."
        case .timedOut:
            return "Termostat komutu zaman aşımına uğradı."
        case .cancelled:
            return "İşlem kullanıcı veya sistem tarafından iptal edildi."
        case .internalError(let message):
            return "İç hata: \(message)"
        }
    }
}

// MARK: - Heating Commands

public enum ThermostatHeatingCommand: Equatable, Sendable {
    case turnOn
    case turnOff

    /// Payload sent to Firebase Realtime Database.
    ///
    /// - turnOn: Sets mode to "on" and targetTemperature to 25.0°C.
    ///   DOES NOT set isHeating=true directly; boiler relay decision is left to firmware/hysteresis.
    /// - turnOff: Sets mode to "off" and isHeating to false (preserving existing Flutter behavior).
    ///   DOES NOT alter targetTemperature.
    public var payload: [String: Any] {
        switch self {
        case .turnOn:
            return [
                "mode": "on",
                "targetTemperature": 25.0
            ]
        case .turnOff:
            return [
                "mode": "off",
                "isHeating": false
            ]
        }
    }
}

// MARK: - Protocols for Dependency Injection & Testability

public protocol HTTPRequestPerforming: Sendable {
    func performData(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPRequestPerforming {
    public func performData(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await self.data(for: request)
    }
}

public protocol ThermostatAuthSessionProviding: Sendable {
    /// Ensures user session is restored/ready. Throws if user is not signed in or times out.
    func ensureUserAuthenticated(timeout: TimeInterval) async throws
    /// Fetches a valid Firebase ID token.
    func getValidIDToken(forcingRefresh: Bool) async throws -> String
}

// MARK: - Firebase Configuration Helper

#if canImport(FirebaseCore)
public enum ThermostatFirebaseConfig {
    /// Safely returns existing FirebaseApp or configures it once from GoogleService-Info.plist.
    public static func configuredFirebaseApp() throws -> FirebaseApp {
        if let existing = FirebaseApp.app() {
            return existing
        }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            throw ThermostatCommandError.missingConfiguration
        }
        FirebaseApp.configure(options: options)
        guard let app = FirebaseApp.app() else {
            throw ThermostatCommandError.missingConfiguration
        }
        return app
    }

    /// Resolves the Realtime Database URL from the configured FirebaseApp.
    public static func databaseURL(from app: FirebaseApp? = FirebaseApp.app()) throws -> String {
        let activeApp: FirebaseApp
        if let app = app {
            activeApp = app
        } else {
            activeApp = try configuredFirebaseApp()
        }
        guard let url = activeApp.options.databaseURL, !url.isEmpty else {
            throw ThermostatCommandError.invalidDatabaseURL
        }
        return url
    }
}
#endif

// MARK: - Native Firebase Auth Provider

#if canImport(FirebaseAuth) && canImport(FirebaseCore)
/// Thread-safe coordinator for the initial Auth state listener.
private final class AuthStateListenerCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var isResolved = false
    private var listenerHandle: AuthStateDidChangeListenerHandle?
    private var timeoutTimer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<Void, Error>?
    private weak var auth: Auth?

    init(auth: Auth, continuation: CheckedContinuation<Void, Error>) {
        self.auth = auth
        self.continuation = continuation
    }

    func start(timeout: TimeInterval) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }

        // Configure timeout timer on global queue
        let timer = DispatchSourceTimer.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            self?.handleTimeout()
        }
        self.timeoutTimer = timer
        timer.resume()

        // Register initial auth state listener
        self.listenerHandle = auth?.addStateDidChangeListener { [weak self] (_, user) in
            self?.handleAuthStateUpdate(user: user)
        }
        lock.unlock()
    }

    private func handleAuthStateUpdate(user: User?) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        cleanupResourcesLocked()
        let cont = continuation
        continuation = nil
        lock.unlock()

        if user != nil {
            cont?.resume()
        } else {
            cont?.resume(throwing: ThermostatCommandError.signInRequired)
        }
    }

    private func handleTimeout() {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let hasCurrentUser = (auth?.currentUser != nil)
        cleanupResourcesLocked()
        let cont = continuation
        continuation = nil
        lock.unlock()

        if hasCurrentUser {
            cont?.resume()
        } else {
            cont?.resume(throwing: ThermostatCommandError.timedOut)
        }
    }

    func cancel() {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        cleanupResourcesLocked()
        let cont = continuation
        continuation = nil
        lock.unlock()

        cont?.resume(throwing: ThermostatCommandError.cancelled)
    }

    private func cleanupResourcesLocked() {
        if let handle = listenerHandle, let auth = auth {
            auth.removeStateDidChangeListener(handle)
            self.listenerHandle = nil
        }
        timeoutTimer?.cancel()
        timeoutTimer = nil
    }
}

public final class FirebaseAuthSessionProvider: ThermostatAuthSessionProviding {
    private let appResolver: @Sendable () throws -> FirebaseApp

    public init(appResolver: @escaping @Sendable () throws -> FirebaseApp = { try ThermostatFirebaseConfig.configuredFirebaseApp() }) {
        self.appResolver = appResolver
    }

    public func ensureUserAuthenticated(timeout: TimeInterval = 5.0) async throws {
        let app = try appResolver()
        let auth = Auth.auth(app: app)

        // Fast path: User already restored and available in memory
        if auth.currentUser != nil {
            return
        }

        // Wait for SDK to restore session from Keychain asynchronously
        var coordinatorRef: AuthStateListenerCoordinator?
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let coordinator = AuthStateListenerCoordinator(auth: auth, continuation: continuation)
                coordinatorRef = coordinator
                coordinator.start(timeout: timeout)
            }
        } onCancel: {
            coordinatorRef?.cancel()
        }
    }

    public func getValidIDToken(forcingRefresh: Bool) async throws -> String {
        let app = try appResolver()
        let auth = Auth.auth(app: app)

        guard let user = auth.currentUser else {
            throw ThermostatCommandError.signInRequired
        }

        do {
            return try await user.getIDToken(forcingRefresh: forcingRefresh)
        } catch let err as NSError {
            if err.domain == NSURLErrorDomain {
                if err.code == NSURLErrorTimedOut {
                    throw ThermostatCommandError.timedOut
                } else {
                    throw ThermostatCommandError.networkUnavailable
                }
            }
            if err.domain == AuthErrorDomain {
                if let code = AuthErrorCode.Code(rawValue: err.code) {
                    switch code {
                    case .networkError:
                        throw ThermostatCommandError.networkUnavailable
                    case .userNotFound, .userTokenExpired, .invalidCredential:
                        throw ThermostatCommandError.signInRequired
                    default:
                        break
                    }
                }
            }
            throw err
        }
    }
}
#endif

// MARK: - Main Command Service

public enum ThermostatCommandService {
    public static let defaultDeviceID = "device1"

    /// Builds a secure REST PATCH request for Firebase Realtime Database.
    /// Ensures HTTPS, validated host, valid device JSON path, and query auth token.
    public static func buildRequest(
        databaseURL: String,
        deviceID: String,
        token: String,
        command: ThermostatHeatingCommand
    ) throws -> URLRequest {
        guard var components = URLComponents(string: databaseURL),
              components.scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil else {
            throw ThermostatCommandError.invalidDatabaseURL
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        path += "/devices/\(deviceID).json"
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "auth", value: token)
        ]
        components.fragment = nil

        guard let url = components.url else {
            throw ThermostatCommandError.invalidDatabaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 15.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: command.payload)
        return request
    }

    /// Sends a heating command to the thermostat via Firebase Realtime Database REST API.
    ///
    /// - Parameters:
    ///   - command: `.turnOn` or `.turnOff`
    ///   - deviceID: Target thermostat device ID (default: "device1")
    ///   - databaseURL: Optional explicit database URL (if nil, resolved from FirebaseApp)
    ///   - authProvider: Optional auth provider for dependency injection / testing
    ///   - networkSession: Optional HTTP transport for dependency injection / testing
    public static func send(
        _ command: ThermostatHeatingCommand,
        deviceID: String = defaultDeviceID,
        databaseURL: String? = nil,
        authProvider: ThermostatAuthSessionProviding? = nil,
        networkSession: HTTPRequestPerforming = URLSession.shared
    ) async throws {
        try Task.checkCancellation()

        let auth: ThermostatAuthSessionProviding
        let dbURL: String

        #if canImport(FirebaseCore) && canImport(FirebaseAuth)
        auth = authProvider ?? FirebaseAuthSessionProvider()
        if let databaseURL = databaseURL {
            dbURL = databaseURL
        } else {
            dbURL = try ThermostatFirebaseConfig.databaseURL()
        }
        #else
        guard let resolvedAuth = authProvider, let resolvedURL = databaseURL else {
            throw ThermostatCommandError.missingConfiguration
        }
        auth = resolvedAuth
        dbURL = resolvedURL
        #endif

        // Step 1: Ensure user session is restored (with 5-second initial wait timeout)
        try await auth.ensureUserAuthenticated(timeout: 5.0)
        try Task.checkCancellation()

        // Step 2: Retrieve current user ID token (unforced)
        var token = try await auth.getValidIDToken(forcingRefresh: false)
        try Task.checkCancellation()

        // Step 3: Send initial PATCH request
        var status = try await executePatch(
            command: command,
            deviceID: deviceID,
            databaseURL: dbURL,
            token: token,
            networkSession: networkSession
        )

        // Step 4: Handle 401 with a single token refresh attempt (no infinite retry loop)
        if status == 401 {
            try Task.checkCancellation()
            token = try await auth.getValidIDToken(forcingRefresh: true)
            status = try await executePatch(
                command: command,
                deviceID: deviceID,
                databaseURL: dbURL,
                token: token,
                networkSession: networkSession
            )
        }

        // Step 5: Check response status
        switch status {
        case 200..<300:
            return
        case 401, 403:
            throw ThermostatCommandError.authorizationDenied
        default:
            throw ThermostatCommandError.requestFailed(status)
        }
    }

    private static func executePatch(
        command: ThermostatHeatingCommand,
        deviceID: String,
        databaseURL: String,
        token: String,
        networkSession: HTTPRequestPerforming
    ) async throws -> Int {
        let request = try buildRequest(
            databaseURL: databaseURL,
            deviceID: deviceID,
            token: token,
            command: command
        )

        do {
            let (_, response) = try await networkSession.performData(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ThermostatCommandError.invalidResponse
            }
            return httpResponse.statusCode
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw ThermostatCommandError.timedOut
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed:
                throw ThermostatCommandError.networkUnavailable
            case .cancelled:
                throw ThermostatCommandError.cancelled
            default:
                throw error
            }
        } catch is CancellationError {
            throw ThermostatCommandError.cancelled
        }
    }
}
