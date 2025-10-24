import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    var body: some View {
        Group {
            if auth.isLoggedIn() {
                PlaylistPickerView()
            } else {
                LoginView()
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    var body: some View {
        VStack(spacing: 24) {
            Text("Spotify Sort").font(.largeTitle).bold()
            Text("Swipe left to remove, right to keep. Clean your playlists fast.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: { auth.login() }) {
                HStack { Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill"); Text("Sign in with Spotify") }
                    .padding().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
    }
}

struct PlaylistPickerView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List(api.playlists) { pl in
                NavigationLink(value: pl) {
                    HStack(spacing: 12) {
                        RemoteImage(url: pl.images?.first?.url)
                            .frame(width: 48, height: 48)
                            .cornerRadius(6)
                        VStack(alignment: .leading) {
                            Text(pl.name).fontWeight(.semibold)
                            Text("\(pl.tracks.total) items").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationDestination(for: Playlist.self) { pl in
                SortView(playlist: pl)
            }
            .navigationTitle("Your Playlists")
            .overlay { if isLoading { ProgressView() } }
            .task {
                guard api.playlists.isEmpty, !isLoading else { return }
                isLoading = true
                try? await api.loadMe(auth: auth)
                try? await api.loadPlaylists(auth: auth)
                isLoading = false
            }
        }
    }
}

struct SortView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    let playlist: Playlist

    @State private var deck: [PlaylistTrack] = []
    @State private var removedURIs: [String] = []
    @State private var keepURIs: [String] = []
    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var showCommit = false

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView().task { await load() }
            } else if topIndex >= deck.count {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 40))
                    Text("All done!").font(.title2).bold()
                    Button("Commit \(removedURIs.count) removals") { showCommit = true }
                        .buttonStyle(.borderedProminent).disabled(removedURIs.isEmpty)
                }
            } else {
                ZStack {
                    ForEach(Array(deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                        if idx >= topIndex {
                            SwipeCard(track: item.track!) { dir in
                                onSwipe(direction: dir, item: item)
                            }
                            .padding(.horizontal, 16)
                            .zIndex(item.id == deck[topIndex].id ? 1 : 0)
                        }
                    }
                }.frame(maxHeight: .infinity)

                HStack(spacing: 20) {
                    Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .disabled(topIndex == 0)
                    Button { skip() } label: { Label("Skip", systemImage: "forward.frame") }
                        .buttonStyle(.bordered)
                    Button { showCommit = true } label: { Label("Commit", systemImage: "tray.and.arrow.down.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(removedURIs.isEmpty)
                }.padding(.bottom)
            }
        }
        .navigationTitle(playlist.name)
        .confirmationDialog("Apply removals to Spotify?", isPresented: $showCommit, titleVisibility: .visible) {
            Button("Remove \(removedURIs.count) tracks", role: .destructive) { Task { await commitRemovals() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    func load() async {
        do {
            let items = try await api.loadTracks(playlistID: playlist.id, auth: auth)
            deck = items
            isLoading = false
        } catch { print(error) }
    }

    func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        guard let uri = item.track?.uri else { return }
        if direction == .left { removedURIs.append(uri) } else { keepURIs.append(uri) }
        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func undo() {
        guard topIndex > 0 else { return }
        topIndex -= 1
        if let uri = deck[topIndex].track?.uri {
            if let idx = removedURIs.lastIndex(of: uri) { removedURIs.remove(at: idx) }
            if let idx = keepURIs.lastIndex(of: uri) { keepURIs.remove(at: idx) }
        }
    }

    func skip() { topIndex += 1 }

    func commitRemovals() async {
        do {
            try await api.batchRemoveTracks(playlistID: playlist.id, uris: removedURIs, auth: auth)
            removedURIs.removeAll()
        } catch { print(error) }
    }
}
