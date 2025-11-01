import SwiftUI

@main
struct SpotifySortApp: App {
    @StateObject private var env: AppEnvironment
    
    init() {
        // Build Auth dependencies
        let secure = KeychainSecureStore(service: "spotifysort.oauth")
        let authClient = AuthClient(config: .spotifyDefault, store: secure)
        let auth = AuthManager(client: authClient)
        
        // Build Core dependencies
        let spotifyClient = SpotifyClient()
        let metadataCache = TrackMetadataCache()
        let spotifyDataProvider = SpotifyDataProvider(client: spotifyClient, auth: auth)
        let historyStore = HistoryStore.shared // Get the pure Core actor
        
        // Build App Services (coordinators)
        let spotifyService = SpotifyService(
            client: spotifyClient,
            cache: metadataCache,
            auth: auth
        )
        let router = Router()
        let previews = PreviewResolver(service: spotifyService, cache: metadataCache)
        let historyCoordinator = HistoryCoordinator(store: historyStore) // NEW: Coordinator wraps Core actor
        
        // Compose environment
        let env = AppEnvironment(
            auth: auth,
            service: spotifyService,
            router: router,
            previews: previews,
            dataProvider: spotifyDataProvider,
            history: historyCoordinator // ADDED
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
