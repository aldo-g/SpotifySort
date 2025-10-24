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

// MARK: - Picker

struct PlaylistPickerView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    @State private var isLoading = false
    @State private var likedCount: Int? = nil
    @State private var isLoadingLiked = false

    var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return [] }
        return api.playlists.filter { $0.owner.id == me && $0.tracks.total > 0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your Playlists") {
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

// MARK: - Sort a Playlist (global order; client-side pages of 20)

struct SortView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    let playlist: Playlist

    @State private var orderedAll: [PlaylistTrack] = []
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0

    @State private var removedURIs: [String] = []
    @State private var keepURIs: [String] = []
    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var showCommit = false

    private let pageSize = 20

    private var listKey: String { "playlist:\(playlist.id)" }
    @State private var reviewedSet: Set<String> = []

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView().task { await loadAll() }
            } else if topIndex >= deck.count {
                if nextCursor < orderedAll.count {
                    ProgressView("Loading more…").task { try? await loadNextPage() }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 40))
                        Text("All done!").font(.title2).bold()
                        Button("Commit \(removedURIs.count) removals") { showCommit = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(removedURIs.isEmpty)
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
                        .disabled(removedURIs.isEmpty)
                }
                .padding(.bottom)
            }
        }
        .navigationTitle(playlist.name)
        .onChange(of: topIndex) { _ in Task { await topUpIfNeeded() } }
        .confirmationDialog("Apply removals to Spotify?",
                            isPresented: $showCommit, titleVisibility: .visible) {
            Button("Remove \(removedURIs.count) tracks", role: .destructive) {
                Task { await commitRemovals() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func loadAll() async {
        reviewedSet = ReviewStore.shared.loadReviewed(for: listKey)
        do {
            orderedAll = try await api.loadAllPlaylistTracksOrdered(
                playlistID: playlist.id,
                auth: auth,
                reviewedURIs: reviewedSet
            )
            deck.removeAll()
            nextCursor = 0
            try? await loadNextPage()
            isLoading = false
        } catch {
            print(error)
            isLoading = false
        }
    }

    private func loadNextPage() async throws {
        let end = min(nextCursor + pageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck.append(contentsOf: orderedAll[nextCursor..<end])
        nextCursor = end
    }

    private func topUpIfNeeded() async {
        let remaining = deck.count - topIndex
        if remaining <= 5 { try? await loadNextPage() }
    }

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        if let uri = item.track?.uri {
            ReviewStore.shared.addReviewed(uri, for: listKey)
            if direction == .left { removedURIs.append(uri) } else { keepURIs.append(uri) }
        }
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

// MARK: - Sort Liked Songs (FAST-START + background paging)

struct SortLikedView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    // Fully ordered list we’re building incrementally
    @State private var orderedAll: [PlaylistTrack] = []
    // What’s currently loaded to swipe
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0

    @State private var toUnsaveIDs: [String] = []
    @State private var keepIDs: [String] = []
    @State private var topIndex: Int = 0

    @State private var isLoading = true
    @State private var showCommit = false

    // Pager state
    @State private var nextURL: String? = nil
    @State private var isFetching = false
    @State private var allDone = false

    // Deterministic session shuffle
    private let sessionSeed = UUID().uuidString
    private let pageSize = 20
    private let warmStartTarget = 100  // start once ~100 are ready

    private let listKey = "liked"
    @State private var reviewedSet: Set<String> = []

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView("Preparing deck…").task { await initialFastStart() }
            } else if topIndex >= deck.count {
                if !allDone || nextCursor < orderedAll.count {
                    ProgressView("Loading more…").task { await topUpIfNeeded(force: true) }
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
        .onChange(of: topIndex) { _ in Task { await topUpIfNeeded() } }
        .confirmationDialog("Remove from Liked Songs?",
                            isPresented: $showCommit, titleVisibility: .visible) {
            Button("Unsave \(toUnsaveIDs.count) tracks", role: .destructive) {
                Task { await commit() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Fast-start pipeline

    private func initialFastStart() async {
        reviewedSet = ReviewStore.shared.loadReviewed(for: listKey)
        // Fetch pages until we have ~warmStartTarget items or we run out
        while orderedAll.count < warmStartTarget, !allDone {
            await fetchNextPageAndMerge()
        }
        // Start swiping immediately
        nextCursor = 0
        deck.removeAll()
        try? await loadNextPage()
        isLoading = false

        // Keep fetching remaining pages in the background
        Task.detached { await backgroundFetchRemaining() }
    }

    private func backgroundFetchRemaining() async {
        while !allDone {
            await fetchNextPageAndMerge()
            await topUpIfNeeded()
        }
    }

    private func fetchNextPageAndMerge() async {
        guard !isFetching, !allDone else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let result = try await api.fetchSavedTracksPage(auth: auth, nextURL: nextURL)
            nextURL = result.next
            if result.items.isEmpty {
                allDone = (nextURL == nil)
                return
            }
            // Merge into global ordered list using deterministic rank
            orderedAll.append(contentsOf: result.items)
            orderedAll.sort { a, b in rankKey(a) < rankKey(b) }
            if nextURL == nil { allDone = true }
        } catch {
            allDone = true
            print("SavedTracks paging error: \(error)")
        }
    }

    // MARK: Deterministic session shuffle with reviewed-last bias

    private func rankKey(_ item: PlaylistTrack) -> (Int, UInt64) {
        // reviewed == 1 sorts AFTER unreviewed == 0
        let reviewed = isReviewed(item) ? 1 : 0
        let id = item.track?.id ?? item.track?.uri ?? UUID().uuidString
        return (reviewed, fnv1a64(sessionSeed + "|" + id))
    }

    private func isReviewed(_ item: PlaylistTrack) -> Bool {
        if let id = item.track?.id { return reviewedSet.contains(id) }
        if let uri = item.track?.uri { return reviewedSet.contains(uri) }
        return false
    }

    // MARK: Deck paging from orderedAll

    private func loadNextPage() async throws {
        let end = min(nextCursor + pageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck = Array(orderedAll.prefix(end))  // keep deck as prefix; preserves swiped indices
        nextCursor = end
    }

    private func topUpIfNeeded(force: Bool = false) async {
        let remaining = deck.count - topIndex
        guard force || remaining <= 5 else { return }
        try? await loadNextPage()
    }

    // MARK: Swipe actions

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        if let id = item.track?.id {
            ReviewStore.shared.addReviewed(id, for: listKey)
            reviewedSet.insert(id)
            if direction == .left { toUnsaveIDs.append(id) } else { keepIDs.append(id) }
        } else if let uri = item.track?.uri {
            ReviewStore.shared.addReviewed(uri, for: listKey)
        }
        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func undo() {
        guard topIndex > 0 else { return }
        topIndex -= 1
        if let id = deck[topIndex].track?.id {
            if let i = toUnsaveIDs.lastIndex(of: id) { toUnsaveIDs.remove(at: i) }
            if let i = keepIDs.lastIndex(of: id) { keepIDs.remove(at: i) }
        }
    }

    private func skip() { topIndex += 1 }

    private func commit() async {
        do {
            try await api.batchUnsaveTracks(trackIDs: toUnsaveIDs, auth: auth)
            toUnsaveIDs.removeAll()
        } catch { print(error) }
    }
}

// MARK: - Tiny hash (FNV-1a 64-bit) for deterministic shuffle

private func fnv1a64(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash &*= prime
    }
    return hash
}
