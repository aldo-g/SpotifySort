import SwiftUI

@main
struct SpotifySortApp: App {
    // We need to ensure PreviewResolver shares the same SpotifyAPI instance.
    @StateObject private var auth: AuthManager
    @StateObject private var api: SpotifyAPI
    @StateObject private var router: Router
    @StateObject private var previews: PreviewResolver

    init() {
        let auth = AuthManager()
        let api = SpotifyAPI()
        let router = Router()
        let previews = PreviewResolver(api: api)

        _auth = StateObject(wrappedValue: auth)
        _api = StateObject(wrappedValue: api)
        _router = StateObject(wrappedValue: router)
        _previews = StateObject(wrappedValue: previews)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(api)
                .environmentObject(router)
                .environmentObject(previews)   // ← expose preview resolver to UI
                .task {
                    // 🔁 Attempt to restore a previous session on launch
                    await auth.resumeSession()
                }
                .onOpenURL { url in
                    // keep OAuth callback
                    auth.handleRedirect(url: url)
                }
        }
    }
}
