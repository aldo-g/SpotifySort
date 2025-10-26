import Foundation
import AuthenticationServices
import Combine
import CryptoKit
import Security

@MainActor
final class AuthManager: NSObject, ObservableObject {
    // MARK: - Spotify OAuth (PKCE)
    private let CLIENT_ID = "0473bcc9a68e491e9b5882ec8ec335ac"   // your real ID
    private let REDIRECT_URI = "spotifysort://callback"
    private let AUTH_URL = URL(string: "https://accounts.spotify.com/authorize")!
    private let TOKEN_URL = URL(string: "https://accounts.spotify.com/api/token")!

    // MARK: - Published session state
    @Published var accessToken: String? {
        didSet {
            if accessToken == nil {
                refreshToken = nil
                expiresAt = nil
            }
        }
    }

    // MARK: - Private state
    private var refreshToken: String?
    private var expiresAt: Date?
    private var codeVerifier: String?
    private var authSession: ASWebAuthenticationSession?
    private var refreshTimer: Timer?

    // MARK: - Public API
    func isLoggedIn() -> Bool { accessToken != nil }

    /// Attempt to restore a previous session (call at app launch).
    func resumeSession() async {
        // Load from Keychain
        self.accessToken = Keychain.load(.accessToken)
        self.refreshToken = Keychain.load(.refreshToken)
        if let ts = Keychain.load(.expiresAt), let seconds = TimeInterval(ts) {
            self.expiresAt = Date(timeIntervalSince1970: seconds)
        }

        // No refresh token → nothing to restore
        guard refreshToken != nil else { return }

        // If missing/near expiry, refresh now
        if accessToken == nil || isExpiringSoon() {
            await refreshAccessToken()
            if accessToken == nil {
                // still no valid token → force logout (UI falls back to LoginView)
                logout()
            }
        } else {
            scheduleAutoRefresh()
        }
    }

    func login() {
        let pkce = PKCE()
        codeVerifier = pkce.verifier
        let codeChallenge = pkce.challenge

        var comps = URLComponents(url: AUTH_URL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: CLIENT_ID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: REDIRECT_URI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(
                name: "scope",
                value: """
                playlist-read-private playlist-modify-public playlist-modify-private user-read-email user-library-read user-library-modify
                """
            )
        ]

        guard let url = comps.url else { return }

        authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "spotifysort") { [weak self] callbackURL, error in
            guard let self else { return }
            if let url = callbackURL {
                self.handleRedirect(url: url)
            } else if let error = error {
                print("Auth error:", error)
            }
        }
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.presentationContextProvider = self
        _ = authSession?.start()
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        invalidateRefreshTimer()
        Keychain.delete(.accessToken)
        Keychain.delete(.refreshToken)
        Keychain.delete(.expiresAt)
    }

    // MARK: - Redirect → token exchange

    func handleRedirect(url: URL) {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else { return }

        var req = URLRequest(url: TOKEN_URL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(CLIENT_ID)",
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(REDIRECT_URI)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self, let data else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("Token exchange HTTP error:", (response as? HTTPURLResponse)?.statusCode ?? -1)
                Task { @MainActor in self.logout() }
                return
            }
            struct TokenResp: Codable { let access_token: String; let refresh_token: String?; let expires_in: Int }
            if let token = try? JSONDecoder().decode(TokenResp.self, from: data) {
                Task { @MainActor in
                    let expiry = Date().addingTimeInterval(TimeInterval(token.expires_in))
                    self.setSession(access: token.access_token, refresh: token.refresh_token, expiresAt: expiry)
                }
            } else {
                print("Token decode error:", String(data: data, encoding: .utf8) ?? "")
                Task { @MainActor in self.logout() }
            }
        }.resume()
    }

    // MARK: - Refresh

    /// Refresh the access token using the stored refresh token.
    func refreshAccessToken() async {
        guard let refreshToken else { return }

        var req = URLRequest(url: TOKEN_URL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(CLIENT_ID)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("⚠️ Refresh HTTP error:", (response as? HTTPURLResponse)?.statusCode ?? -1)
                logout()
                return
            }

            struct RefreshResp: Codable {
                let access_token: String
                let token_type: String?
                let scope: String?
                let expires_in: Int
                let refresh_token: String? // Spotify may rotate this
            }

            let token = try JSONDecoder().decode(RefreshResp.self, from: data)
            let expiry = Date().addingTimeInterval(TimeInterval(token.expires_in))
            setSession(access: token.access_token, refresh: token.refresh_token, expiresAt: expiry)
        } catch {
            print("⚠️ Token refresh failed:", error.localizedDescription)
            logout()
        }
    }

    // MARK: - Internals

    private func setSession(access: String, refresh: String?, expiresAt: Date) {
        self.accessToken = access
        if let r = refresh { self.refreshToken = r }
        self.expiresAt = expiresAt

        // Persist securely
        Keychain.save(.accessToken, value: access)
        if let r = refresh ?? self.refreshToken { Keychain.save(.refreshToken, value: r) }
        Keychain.save(.expiresAt, value: String(expiresAt.timeIntervalSince1970))

        scheduleAutoRefresh()
    }

    private func isExpiringSoon(threshold: TimeInterval = 90) -> Bool {
        guard let expiresAt else { return true }
        return Date().addingTimeInterval(threshold) >= expiresAt
    }

    private func scheduleAutoRefresh() {
        invalidateRefreshTimer()
        guard let expiresAt else { return }
        let interval = max(10, expiresAt.timeIntervalSinceNow - 60) // refresh ~1 min before expiry
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { await self?.refreshAccessToken() }
        }
    }

    private func invalidateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { .init() }
}

// MARK: - PKCE helper
struct PKCE {
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

// MARK: - Minimal Keychain helper
private enum KCKey: String {
    case accessToken = "spotifysort.accessToken"
    case refreshToken = "spotifysort.refreshToken"
    case expiresAt   = "spotifysort.expiresAt"
}

private enum Keychain {
    static func save(_ key: KCKey, value: String) {
        let data = Data(value.utf8)

        // Delete any existing
        delete(key)

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
