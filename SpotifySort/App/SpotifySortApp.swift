import SwiftUI

@main
struct SpotifySortApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var api = SpotifyAPI()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(api)
                .environmentObject(router)
                .onOpenURL { url in
                    // keep OAuth callback
                    auth.handleRedirect(url: url)
                }
        }
    }
}
