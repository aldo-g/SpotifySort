import SwiftUI

@main
struct SpotifySortApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        // Build Auth dependencies
        let secure = KeychainSecureStore(service: "spotifysort.oauth")
        let authClient = AuthClient(config: .spotifyDefault, store: secure)
        let auth = AuthManager(client: authClient)

        // Existing singletons
        let api = SpotifyAPI()
        let router = Router()
        let previews = PreviewResolver(api: api)
        let metadata = TrackMetadataService()
        let env = AppEnvironment(auth: auth, api: api, router: router, previews: previews, metadata: metadata)

        _env = StateObject(wrappedValue: env)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .task { await env.auth.resumeSession() }
                .onOpenURL { url in env.auth.handleRedirect(url: url) }
        }
    }
}
