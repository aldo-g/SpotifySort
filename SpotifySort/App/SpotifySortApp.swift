import SwiftUI

@main
struct SpotifySortApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var api = SpotifyAPI()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(api)
                .onOpenURL { url in
                    auth.handleRedirect(url: url)
                }
        }
    }
}
