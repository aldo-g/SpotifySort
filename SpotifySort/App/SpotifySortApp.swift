import SwiftUI

@main
struct SpotifySortApp: App {
    @StateObject private var env: AppEnvironment
    
    init() {
        // Build Auth dependencies
        let secure = KeychainSecureStore(service: "spotifysort.oauth")
        let authClient = AuthClient(config: .spotifyDefault, store: secure)
        let auth = AuthManager(client: authClient)
        
        // Build Spotify dependencies (three-layer architecture)
        let spotifyClient = SpotifyClient()
        let metadataCache = TrackMetadataCache()
        let spotifyService = SpotifyService(
            client: spotifyClient,
            cache: metadataCache,
            auth: auth
        )
        
        // Other singletons
        let router = Router()
        let previews = PreviewResolver(service: spotifyService, cache: metadataCache)
        let metadata = TrackMetadataService()
        
        // Compose environment
        let env = AppEnvironment(
            auth: auth,
            service: spotifyService,
            router: router,
            previews: previews,
            metadata: metadata
        )
        
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
