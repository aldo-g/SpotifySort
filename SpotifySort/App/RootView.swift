import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if auth.isLoggedIn() {
                NavigationStack {
                    content
                        .task {
                            if api.user == nil { try? await api.loadMe(auth: auth) }
                            if api.playlists.isEmpty { try? await api.loadPlaylists(auth: auth) }
                            if case .playlist = router.selection { /* keep current */ }
                            else { router.selectLiked() }
                        }
                }
            } else {
                LoginView()
            }
        }
        .onOpenURL { handleDeepLink($0) }
    }

    @ViewBuilder
    private var content: some View {
        switch router.selection {
        case .liked:
            // Give Liked Songs a stable but unique identity
            SortLikedView()
                .navigationTitle("Liked Songs")
                .id("route-liked") // <-- forces recreation when coming from a playlist

        case .playlist(let id):
            if let pl = api.playlists.first(where: { $0.id == id }) {
                // FORCE a new instance when the playlist id changes
                SortView(playlist: pl)
                    .id("route-playlist-\(pl.id)") // <-- key fix
            } else {
                ProgressView().task { try? await api.loadPlaylists(auth: auth) }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        switch host {
        case "liked":
            router.selectLiked()
        case "playlist":
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = comps.queryItems?.first(where: { $0.name == "id" })?.value {
                router.selectPlaylist(id)
            }
        default: break
        }
    }
}
