import SwiftUI

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Group {
            if env.auth.isLoggedIn() {
                NavigationStack {
                    content
                        .task {
                            if env.service.user == nil { try? await env.service.loadMe() }
                            if env.service.playlists.isEmpty { try? await env.service.loadPlaylists() }
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
            SortLikedView()
                .navigationTitle("Liked Songs")
                .id("route-liked")

        case .playlist(let id):
            if let pl = env.service.playlists.first(where: { $0.id == id }) {
                SortView(playlist: pl)
                    .id("route-playlist-\(pl.id)")
            } else {
                ProgressView().task { try? await env.service.loadPlaylists() }
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
