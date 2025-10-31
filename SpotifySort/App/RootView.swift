import SwiftUI

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Group {
            if env.auth.isLoggedIn() {
                NavigationStack {
                    content
                        .task {
                            if env.api.user == nil { try? await env.api.loadMe(auth: env.auth) }
                            if env.api.playlists.isEmpty { try? await env.api.loadPlaylists(auth: env.auth) }
                            if case .playlist = env.router.selection { /* keep current */ }
                            else { env.router.selectLiked() }
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
        switch env.router.selection {
        case .liked:
            // Give Liked Songs a stable but unique identity
            SortLikedView()
                .navigationTitle("Liked Songs")
                .id("route-liked") // <-- forces recreation when coming from a playlist

        case .playlist(let id):
            if let pl = env.api.playlists.first(where: { $0.id == id }) {
                // FORCE a new instance when the playlist id changes
                SortView(playlist: pl)
                    .id("route-playlist-\(pl.id)") // <-- key fix
            } else {
                ProgressView().task { try? await env.api.loadPlaylists(auth: env.auth) }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        switch host {
        case "liked":
            env.router.selectLiked()
        case "playlist":
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = comps.queryItems?.first(where: { $0.name == "id" })?.value {
                env.router.selectPlaylist(id)
            }
        default: break
        }
    }
}
