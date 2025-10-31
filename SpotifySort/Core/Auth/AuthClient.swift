import Foundation
import CryptoKit

/// Pure auth logic with no UIKit dependencies.
/// Handles PKCE, token exchange, token refresh, and keychain persistence.
actor AuthClient {
    // MARK: - Configuration
    private let clientID = "0473bcc9a68e491e9b5882ec8ec335ac"
    private let redirectURI = "spotifysort://callback"
    private let authURL = URL(string: "https://accounts.spotify.com/authorize")!
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    
    // MARK: - State
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    
    // MARK: - Types
    struct Token {
        let access: String
        let refresh: String?
        let expiresAt: Date
    }
    
    enum AuthError: Error {
        case missingCode
        case missingVerifier
        case httpError(Int)
        case decodingError
        case noRefreshToken
    }
    
    // MARK: - Public API
    
    /// Build the OAuth authorization URL with PKCE challenge.
    /// Returns (URL, verifier) - caller must store verifier for token exchange.
    func buildAuthorizationURL() -> (url: URL, verifier: String) {
        let pkce = PKCE()
        
        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(
                name: "scope",
                value: "playlist-read-private playlist-modify-public playlist-modify-private user-read-email user-library-read user-library-modify"
            )
        ]
        
        return (comps.url!, pkce.verifier)
    }
    
    /// Exchange authorization code for tokens.
    func exchangeCode(_ code: String, verifier: String) async throws -> Token {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id=\(clientID)",
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
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
        
        // Store in actor state
        accessToken = token.access
        if let ref = token.refresh { refreshToken = ref }
        expiresAt = token.expiresAt
        
        // Persist to keychain
        saveToKeychain(token)
        
        return token
    }
    
    /// Refresh the access token using stored refresh token.
    func refreshAccessToken() async throws -> Token {
        guard let refreshToken else { throw AuthError.noRefreshToken }
        
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id=\(clientID)",
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
            let token_type: String?
            let scope: String?
            let expires_in: Int
            let refresh_token: String? // Spotify may rotate this
        }
        
        guard let refreshResp = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw AuthError.decodingError
        }
        
        let token = Token(
            access: refreshResp.access_token,
            refresh: refreshResp.refresh_token ?? self.refreshToken, // use new or keep old
            expiresAt: Date().addingTimeInterval(TimeInterval(refreshResp.expires_in))
        )
        
        // Store in actor state
        accessToken = token.access
        if let ref = token.refresh { self.refreshToken = ref }
        expiresAt = token.expiresAt
        
        // Persist to keychain
        saveToKeychain(token)
        
        return token
    }
    
    /// Restore session from keychain.
    /// Returns current token if valid, or refreshes if needed.
    func resumeSession() async throws -> Token? {
        // Load from keychain
        guard let access = Keychain.load(.accessToken) else { return nil }
        let refresh = Keychain.load(.refreshToken)
        let expiresAtSeconds = Keychain.load(.expiresAt).flatMap(TimeInterval.init)
        let expiry = expiresAtSeconds.map { Date(timeIntervalSince1970: $0) }
        
        // Update actor state
        accessToken = access
        refreshToken = refresh
        expiresAt = expiry
        
        // Check if needs refresh
        if isExpiringSoon() {
            return try await refreshAccessToken()
        }
        
        // Return current token
        return Token(
            access: access,
            refresh: refresh,
            expiresAt: expiry ?? Date().addingTimeInterval(3600)
        )
    }
    
    /// Get current access token (for making API calls).
    func getCurrentAccessToken() -> String? {
        accessToken
    }
    
    /// Check if logged in.
    func isLoggedIn() -> Bool {
        accessToken != nil
    }
    
    /// Clear all tokens.
    func logout() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        Keychain.delete(.accessToken)
        Keychain.delete(.refreshToken)
        Keychain.delete(.expiresAt)
    }
    
    // MARK: - Private Helpers
    
    private func isExpiringSoon(threshold: TimeInterval = 90) -> Bool {
        guard let expiresAt else { return true }
        return Date().addingTimeInterval(threshold) >= expiresAt
    }
    
    private func saveToKeychain(_ token: Token) {
        Keychain.save(.accessToken, value: token.access)
        if let ref = token.refresh { Keychain.save(.refreshToken, value: ref) }
        Keychain.save(.expiresAt, value: String(token.expiresAt.timeIntervalSince1970))
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

// MARK: - Keychain Helper
private enum KCKey: String {
    case accessToken = "spotifysort.accessToken"
    case refreshToken = "spotifysort.refreshToken"
    case expiresAt = "spotifysort.expiresAt"
}

private enum Keychain {
    static func save(_ key: KCKey, value: String) {
        let data = Data(value.utf8)
        delete(key) // Remove existing
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "spotifysort.oauth",
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(_ key: KCKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "spotifysort.oauth",
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func delete(_ key: KCKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "spotifysort.oauth",
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
