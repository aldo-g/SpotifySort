import Foundation
import AuthenticationServices

/// App-layer auth coordinator that handles UI presentation and state observation.
/// Uses AuthClient (Core) for all business logic.
@MainActor
final class AuthManager: NSObject, ObservableObject {
    // MARK: - Published State (for UI binding)
    @Published var accessToken: String? {
        didSet {
            if accessToken == nil {
                Task { await client.logout() }
            }
        }
    }

    // MARK: - Dependencies
    private let client: AuthClient

    // MARK: - Private State
    private var currentVerifier: String?
    private var authSession: ASWebAuthenticationSession?
    private var refreshTimer: Timer?

    // MARK: - Init
    init(client: AuthClient) {
        self.client = client
        super.init()
    }

    // MARK: - Public API

    func isLoggedIn() -> Bool {
        accessToken != nil
    }

    /// Restore session on app launch.
    func resumeSession() async {
        do {
            if let token = try await client.resumeSession() {
                accessToken = token.access
                scheduleAutoRefresh(expiresAt: token.expiresAt)
            } else {
                accessToken = nil
            }
        } catch {
            print("⚠️ Session resume failed:", error)
            logout()
        }
    }

    /// Start OAuth login flow.
    func login() {
        Task { @MainActor in
            let (url, verifier) = await client.buildAuthorizationURL()
            currentVerifier = verifier

            authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "spotifysort"
            ) { [weak self] callbackURL, error in
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
    }

    /// Clear session.
    func logout() {
        accessToken = nil
        invalidateRefreshTimer()
        Task { await client.logout() }
    }

    // MARK: - Redirect Handling

    func handleRedirect(url: URL) {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = currentVerifier else { return }

        Task {
            do {
                let token = try await client.exchangeCode(code, verifier: verifier)
                accessToken = token.access
                scheduleAutoRefresh(expiresAt: token.expiresAt)
            } catch {
                print("⚠️ Token exchange failed:", error)
                logout()
            }
        }
    }

    // MARK: - Auto-Refresh

    private func scheduleAutoRefresh(expiresAt: Date) {
        invalidateRefreshTimer()

        let interval = max(10, expiresAt.timeIntervalSinceNow - 60) // refresh 1 min before expiry
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor [weak self] in
                await self?.refreshAccessToken()
            }
        }
    }

    private func refreshAccessToken() async {
        do {
            let token = try await client.refreshAccessToken()
            accessToken = token.access
            scheduleAutoRefresh(expiresAt: token.expiresAt)
        } catch {
            print("⚠️ Token refresh failed:", error)
            logout()
        }
    }

    private func invalidateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
