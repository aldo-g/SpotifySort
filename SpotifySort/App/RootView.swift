import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if auth.isLoggedIn() {
                NavigationStack(path: $path) {
                    PlaylistPickerView()
                        .navigationTitle("Your Playlists")
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .liked(let provider):
                                SortLikedView()
                                    .navigationTitle("\(provider.displayName) Liked Songs")
                            case .playlists(let provider):
                                PlaylistPickerView()
                                    .navigationTitle("\(provider.displayName) Playlists")
                            }
                        }
                        .navigationDestination(for: Playlist.self) { pl in
                            SortView(playlist: pl)
                        }
                        .navigationDestination(for: String.self) { key in
                            if key == "liked-songs" { SortLikedView().navigationTitle("Liked Songs") }
                        }
                        .task {
                            if path.isEmpty { path.append(AppRoute.liked(provider: .spotify)) }
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button("Liked Songs") {
                                        path = NavigationPath()
                                        path.append(AppRoute.liked(provider: .spotify))
                                    }
                                    Button("Playlists") {
                                        path = NavigationPath()
                                        path.append(AppRoute.playlists(provider: .spotify))
                                    }
                                } label: {
                                    Label("Navigate", systemImage: "ellipsis.circle")
                                }
                            }
                        }
                }
            } else {
                LoginView()
            }
        }
        .onOpenURL { url in handleDeepLink(url) }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        switch host {
        case "liked":
            path = NavigationPath(); path.append(AppRoute.liked(provider: .spotify))
        case "playlists":
            path = NavigationPath(); path.append(AppRoute.playlists(provider: .spotify))
        default: break
        }
    }
}
