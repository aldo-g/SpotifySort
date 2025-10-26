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
