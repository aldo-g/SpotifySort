import SwiftUI

@main
struct SpotifySortApp: App {
    // Core singletons
    @StateObject private var auth: AuthManager
    @StateObject private var api: SpotifyAPI
    @StateObject private var router: Router
    @StateObject private var previews: PreviewResolver
    @StateObject private var metadata: TrackMetadataService

    // New unified environment
    @StateObject private var env: AppEnvironment

    init() {
        let auth = AuthManager()
        let api = SpotifyAPI()
        let router = Router()
        let previews = PreviewResolver(api: api)
        let metadata = TrackMetadataService()
        let env = AppEnvironment(auth: auth, api: api, router: router, previews: previews, metadata: metadata)

        _auth = StateObject(wrappedValue: auth)
        _api = StateObject(wrappedValue: api)
        _router = StateObject(wrappedValue: router)
        _previews = StateObject(wrappedValue: previews)
        _metadata = StateObject(wrappedValue: metadata)
        _env = StateObject(wrappedValue: env)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .task { await auth.resumeSession() }
                .onOpenURL { url in auth.handleRedirect(url: url) }
        }
    }
}
