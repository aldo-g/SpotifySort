import Foundation
import CryptoKit

/// Pure auth logic with no UI dependencies.
/// Handles PKCE, token exchange, token refresh, and secure persistence.
public actor AuthClient {
    // MARK: - Dependencies
    private let config: AuthConfig
    private let store: SecureStore

    // MARK: - OAuth endpoints
    private let authURL = URL(string: "https://accounts.spotify.com/authorize")!
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    // MARK: - State
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    // MARK: - Types
    public struct Token {
        public let access: String
        public let refresh: String?
        public let expiresAt: Date
    }

    public enum AuthError: Error {
        case httpError(Int)
        case decodingError
        case noRefreshToken
    }

    // MARK: - Keys
    private enum Keys {
        static let access = "oauth.accessToken"
        static let refresh = "oauth.refreshToken"
        static let expires = "oauth.expiresAt"
    }

    // MARK: - Init
    public init(config: AuthConfig, store: SecureStore) {
        self.config = config
        self.store = store
    }

    // MARK: - Public API

    /// Build the OAuth authorization URL with PKCE challenge.
    /// Returns (URL, verifier) - caller must store verifier for token exchange.
    public func buildAuthorizationURL() -> (url: URL, verifier: String) {
        let pkce = PKCE()

        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " "))
        ]

        return (comps.url!, pkce.verifier)
    }

    /// Exchange authorization code for tokens.
    public func exchangeCode(_ code: String, verifier: String) async throws -> Token {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(config.clientID)",
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(config.redirectURI)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }

        guard let tokenResp = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthError.decodingError
        }

        let token = Token(
            access: tokenResp.access_token,
            refresh: tokenResp.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResp.expires_in))
        )

        // Update state + persist
        write(token: token)
        return token
    }

    /// Refresh the access token using stored refresh token.
    public func refreshAccessToken() async throws -> Token {
        guard let refreshToken else { throw AuthError.noRefreshToken }

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id=\(config.clientID)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct RefreshResponse: Codable {
            let access_token: String
            let expires_in: Int
            let refresh_token: String?
        }

        guard let refreshResp = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw AuthError.decodingError
        }

        let token = Token(
            access: refreshResp.access_token,
            refresh: refreshResp.refresh_token ?? self.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(refreshResp.expires_in))
        )

        write(token: token)
        return token
    }

    /// Restore session from secure store; refresh if expiring.
    public func resumeSession() async throws -> Token? {
        guard let access = store.get(Keys.access) else { return nil }
        let refresh = store.get(Keys.refresh)
        let expiresAtSeconds = store.get(Keys.expires).flatMap(TimeInterval.init)
        let expiry = expiresAtSeconds.map { Date(timeIntervalSince1970: $0) }

        accessToken = access
        refreshToken = refresh
        expiresAt = expiry

        if isExpiringSoon() {
            return try await refreshAccessToken()
        }

        return Token(
            access: access,
            refresh: refresh,
            expiresAt: expiry ?? Date().addingTimeInterval(3600)
        )
    }

    public func getCurrentAccessToken() -> String? { accessToken }
    public func isLoggedIn() -> Bool { accessToken != nil }

    public func logout() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        store.remove(Keys.access)
        store.remove(Keys.refresh)
        store.remove(Keys.expires)
    }

    // MARK: - Private helpers

    private func isExpiringSoon(threshold: TimeInterval = 90) -> Bool {
        guard let expiresAt else { return true }
        return Date().addingTimeInterval(threshold) >= expiresAt
    }

    private func write(token: Token) {
        accessToken = token.access
        if let ref = token.refresh { refreshToken = ref }
        expiresAt = token.expiresAt

        store.set(token.access, for: Keys.access)
        if let ref = token.refresh { store.set(ref, for: Keys.refresh) }
        store.set(String(token.expiresAt.timeIntervalSince1970), for: Keys.expires)
    }
}

// MARK: - PKCE Helper
private struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        self.verifier = Data(bytes).base64URLEncodedString()
        let sha = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(sha).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
