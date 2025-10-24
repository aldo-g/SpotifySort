import SwiftUI

// MARK: - Root

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

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    var body: some View {
        VStack(spacing: 24) {
            Text("Spotify Sort").font(.largeTitle).bold()
            Text("Swipe left to remove, right to keep. Clean your playlists fast.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button(action: { auth.login() }) {
                HStack {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill")
                    Text("Sign in with Spotify")
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
    }
}

// MARK: - Picker (Owned + Liked pinned at top)

struct PlaylistPickerView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    @State private var isLoading = false
    @State private var likedCount: Int? = nil
    @State private var isLoadingLiked = false

    // Only playlists owned by the current user
    var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return [] }
        return api.playlists.filter { $0.owner.id == me }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your Playlists") {

                    // Liked Songs row (styled like others)
                    NavigationLink(value: "liked-songs") {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.purple.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "heart.fill")
                                    .imageScale(.medium)
                                    .foregroundStyle(.purple)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Liked Songs").fontWeight(.semibold)
                                Text(likedSubtitleText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Owned playlists
                    ForEach(ownedPlaylists) { pl in
                        NavigationLink(value: pl) {
                            HStack(spacing: 12) {
                                RemoteImage(url: pl.images?.first?.url)
                                    .frame(width: 48, height: 48)
                                    .cornerRadius(6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pl.name).fontWeight(.semibold)
                                    Text("\(pl.tracks.total) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { key in
                if key == "liked-songs" { SortLikedView() }
            }
            .navigationDestination(for: Playlist.self) { pl in
                SortView(playlist: pl)
            }
            .navigationTitle("Your Playlists")
            .overlay { if isLoading { ProgressView() } }
            .task { await loadData() }
        }
    }

    // MARK: Helpers

    private var likedSubtitleText: String {
        if isLoadingLiked { return "Loading…" }
        if let c = likedCount { return "\(c) items" }
        return "Saved tracks"
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        try? await api.loadMe(auth: auth)
        try? await api.loadPlaylists(auth: auth)
        await fetchLikedCount()
    }

    /// Lightweight: hits /v1/me/tracks?limit=1 and reads "total"
    private func fetchLikedCount() async {
        guard !isLoadingLiked else { return }
        isLoadingLiked = true
        defer { isLoadingLiked = false }

        guard
            let token = auth.accessToken,
            var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")
        else { return }

        comps.queryItems = [URLQueryItem(name: "limit", value: "1")]

        guard let url = comps.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let total = obj["total"] as? Int {
                likedCount = total
            }
        } catch {
            likedCount = nil
            print("Failed to fetch liked count: \(error)")
        }
    }
}

// MARK: - Sort a Playlist

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
                        .buttonStyle(.borderedProminent)
                        .disabled(removedURIs.isEmpty)
                }
            } else {
                ZStack {
                    ForEach(Array(deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                        if idx >= topIndex, let tr = item.track {
                            SwipeCard(track: tr) { dir in
                                onSwipe(direction: dir, item: item)
                            }
                            .padding(.horizontal, 16)
                            .zIndex(item.id == deck[topIndex].id ? 1 : 0)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 20) {
                    Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .disabled(topIndex == 0)
                    Button { skip() } label: { Label("Skip", systemImage: "forward.frame") }
                        .buttonStyle(.bordered)
                    Button { showCommit = true } label: { Label("Commit", systemImage: "tray.and.arrow.down.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(removedURIs.isEmpty)
                }
                .padding(.bottom)
            }
        }
        .navigationTitle(playlist.name)
        .confirmationDialog("Apply removals to Spotify?",
                            isPresented: $showCommit, titleVisibility: .visible) {
            Button("Remove \(removedURIs.count) tracks", role: .destructive) {
                Task { await commitRemovals() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        do {
            try await api.loadTracksPaged(playlistID: playlist.id, auth: auth) { newItems in
                if isLoading { isLoading = false }   // drop spinner on first page
                deck.append(contentsOf: newItems)
            }
        } catch {
            print(error)
            isLoading = false
        }
    }

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        guard let uri = item.track?.uri else { return }
        if direction == .left { removedURIs.append(uri) } else { keepURIs.append(uri) }
        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func undo() {
        guard topIndex > 0 else { return }
        topIndex -= 1
        if let uri = deck[topIndex].track?.uri {
            if let i = removedURIs.lastIndex(of: uri) { removedURIs.remove(at: i) }
            if let i = keepURIs.lastIndex(of: uri) { keepURIs.remove(at: i) }
        }
    }

    private func skip() { topIndex += 1 }

    private func commitRemovals() async {
        do {
            try await api.batchRemoveTracks(playlistID: playlist.id, uris: removedURIs, auth: auth)
            removedURIs.removeAll()
        } catch { print(error) }
    }
}

// MARK: - Sort Liked Songs (Saved Tracks, infinite paging @ 20)

struct SortLikedView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    @State private var deck: [PlaylistTrack] = []
    @State private var toUnsaveIDs: [String] = []
    @State private var keepIDs: [String] = []
    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var showCommit = false

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView().task { await initialLoad() }
            } else if topIndex >= deck.count {
                if api.hasMoreSaved {
                    ProgressView("Loading more…").task { await loadMoreIfNeeded(force: true) }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash.fill").font(.system(size: 40))
                        Text("All liked tracks reviewed").font(.title3).bold()
                        Button("Unsave \(toUnsaveIDs.count) tracks") { showCommit = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(toUnsaveIDs.isEmpty)
                    }
                }
            } else {
                ZStack {
                    ForEach(Array(deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                        if idx >= topIndex, let tr = item.track {
                            SwipeCard(track: tr) { dir in
                                onSwipe(direction: dir, item: item)
                            }
                            .padding(.horizontal, 16)
                            .zIndex(item.id == deck[topIndex].id ? 1 : 0)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 20) {
                    Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .disabled(topIndex == 0)
                    Button { skip() } label: { Label("Skip", systemImage: "forward.frame") }
                        .buttonStyle(.bordered)
                    Button { showCommit = true } label: { Label("Commit", systemImage: "tray.and.arrow.down.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(toUnsaveIDs.isEmpty)
                }
                .padding(.bottom)
            }
        }
        .navigationTitle("Liked Songs")
        .confirmationDialog("Remove from Liked Songs?",
                            isPresented: $showCommit, titleVisibility: .visible) {
            Button("Unsave \(toUnsaveIDs.count) tracks", role: .destructive) {
                Task { await commit() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Loading

    private func initialLoad() async {
        api.resetSavedPager(limit: 20)               // page size here
        await loadMoreIfNeeded(force: true)
        isLoading = false
    }

    private func loadMoreIfNeeded(force: Bool = false) async {
        guard !isLoadingMore else { return }
        let remaining = deck.count - topIndex
        guard force || remaining <= 5 else { return }   // prefetch threshold

        isLoadingMore = true
        if let newItems = try? await api.fetchNextSavedPage(auth: auth), !newItems.isEmpty {
            deck.append(contentsOf: newItems)
        }
        isLoadingMore = false
    }

    // MARK: Swipe actions

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        if let id = item.track?.id {
            if direction == .left { toUnsaveIDs.append(id) } else { keepIDs.append(id) }
        }
        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await loadMoreIfNeeded() } // top-up when running low
    }

    private func undo() {
        guard topIndex > 0 else { return }
        topIndex -= 1
        if let id = deck[topIndex].track?.id {
            if let i = toUnsaveIDs.lastIndex(of: id) { toUnsaveIDs.remove(at: i) }
            if let i = keepIDs.lastIndex(of: id) { keepIDs.remove(at: i) }
        }
    }

    private func skip() {
        topIndex += 1
        Task { await loadMoreIfNeeded() }
    }

    // MARK: Mutations

    private func commit() async {
        do {
            try await api.batchUnsaveTracks(trackIDs: toUnsaveIDs, auth: auth)
            toUnsaveIDs.removeAll()
        } catch { print(error) }
    }
}
