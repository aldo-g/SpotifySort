import SwiftUI

@main
struct SpotifySortApp: App {
    @StateObject private var auth: AuthManager
    @StateObject private var api: SpotifyAPI
    @StateObject private var router: Router
    @StateObject private var previews: PreviewResolver
    @StateObject private var metadata: TrackMetadataService   // ← NEW

    init() {
        let auth = AuthManager()
        let api = SpotifyAPI()
        let router = Router()
        let previews = PreviewResolver(api: api)
        let metadata = TrackMetadataService()

        _auth = StateObject(wrappedValue: auth)
        _api = StateObject(wrappedValue: api)
        _router = StateObject(wrappedValue: router)
        _previews = StateObject(wrappedValue: previews)
        _metadata = StateObject(wrappedValue: metadata)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(api)
                .environmentObject(router)
                .environmentObject(previews)
                .environmentObject(metadata)      // ← expose service
                .task { await auth.resumeSession() }
                .onOpenURL { url in auth.handleRedirect(url: url) }
        }
    }
}
