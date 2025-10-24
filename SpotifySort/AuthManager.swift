import Foundation
import AuthenticationServices
import Combine
import CryptoKit

final class AuthManager: NSObject, ObservableObject {
    private let CLIENT_ID = "0473bcc9a68e491e9b5882ec8ec335ac"   // your real ID
    private let REDIRECT_URI = "spotifysort://callback"
    private let AUTH_URL = URL(string: "https://accounts.spotify.com/authorize")!
    private let TOKEN_URL = URL(string: "https://accounts.spotify.com/api/token")!

    @Published var accessToken: String? { didSet { if accessToken == nil { refreshToken = nil } } }
    private var refreshToken: String?
    private var codeVerifier: String?
    private var authSession: ASWebAuthenticationSession?

    func isLoggedIn() -> Bool { accessToken != nil }

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
                print("Auth error: \(error)")
            }
        }
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.presentationContextProvider = self
        _ = authSession?.start()
    }

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

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            struct TokenResp: Codable { let access_token: String; let refresh_token: String?; let expires_in: Int }
            if let token = try? JSONDecoder().decode(TokenResp.self, from: data) {
                DispatchQueue.main.async {
                    self.accessToken = token.access_token
                    self.refreshToken = token.refresh_token
                }
            } else {
                print(String(data: data, encoding: .utf8) ?? "")
            }
        }.resume()
    }
}

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
