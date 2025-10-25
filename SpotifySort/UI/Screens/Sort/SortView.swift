import SwiftUI

struct SortView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var router: Router
    let playlist: Playlist

    @State private var orderedAll: [PlaylistTrack] = []
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0

    @State private var removedURIs: [String] = []
    @State private var keepURIs: [String] = []
    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var showCommit = false
    @State private var showHistory = false

    @State private var duplicateIDs: Set<String> = []
    private let pageSize = 20

    private var listKey: String { "playlist:\(playlist.id)" }
    @State private var reviewedSet: Set<String> = []

    // Pending entries captured when you swipe left; saved on commit
    @State private var pendingRemoved: [RemovalEntry] = []

    private var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return api.playlists }
        return api.playlists.filter { $0.owner.id == me && $0.tracks.total > 0 }
    }

    var body: some View {
        SelectrBackground {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView().task { await loadAll() }
                } else if topIndex >= deck.count {
                    if nextCursor < orderedAll.count {
                        ProgressView("Loading more…").task { try? await loadNextPage() }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40)).foregroundStyle(.white)
                            Text("All done!").font(.title2).bold().foregroundStyle(.white)
                            Button("Commit \(removedURIs.count) removals") { showCommit = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(removedURIs.isEmpty)
                        }
                    }
                } else {
                    ZStack {
                        ForEach(Array(deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                            if idx >= topIndex, let tr = item.track {
                                SwipeCard(
                                    track: tr,
                                    addedAt: item.added_at,
                                    addedBy: item.added_by?.id,
                                    isDuplicate: isDuplicate(trackID: tr.id)
                                ) { dir in
                                    onSwipe(direction: dir, item: item)
                                }
                                .padding(.horizontal, 16)
                                .zIndex(item.id == deck[topIndex].id ? 1 : 0)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    HStack(spacing: 12) {
                        Button { undo() }  label: { Label("Undo",  systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.bordered).controlSize(.large)
                        Button { skip() }  label: { Label("Skip",  systemImage: "forward.frame") }
                            .buttonStyle(.bordered).controlSize(.large)
                        Button { showCommit = true } label: { Label("Commit", systemImage: "tray.and.arrow.down.fill") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(removedURIs.isEmpty)
                    }
                    .tint(.white)
                    .glassyPanel()
                }
            }
            .padding(.top, 8)
        }
        .selectrToolbar()
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .toolbar {
            // Title dropdown
            ToolbarItem(placement: .principal) {
                Menu {
                    Button { router.selectLiked() } label: {
                        Label("Liked Songs", systemImage: "heart.fill")
                    }
                    ForEach(ownedPlaylists, id: \.id) { pl in
                        Button { router.selectPlaylist(pl.id) } label: {
                            Text(pl.name).lineLimit(1)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(playlist.name).font(.headline).foregroundStyle(.white)
                        Image(systemName: "chevron.down").font(.subheadline).foregroundStyle(.white)
                    }
                }
            }
            // History button (top-right)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("History")
            }
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .onChange(of: topIndex) { Task { await topUpIfNeeded() } }
        .confirmationDialog("Apply removals to Spotify?",
                            isPresented: $showCommit, titleVisibility: .visible) {
            Button("Remove \(removedURIs.count) tracks", role: .destructive) {
                Task { await commitRemovals() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func loadAll() async {
        if api.user == nil { try? await api.loadMe(auth: auth) }
        if api.playlists.isEmpty { try? await api.loadPlaylists(auth: auth) }

        reviewedSet = ReviewStore.shared.loadReviewed(for: listKey)
        do {
            orderedAll = try await api.loadAllPlaylistTracksOrdered(
                playlistID: playlist.id, auth: auth, reviewedURIs: reviewedSet
            )
            recomputeDuplicates()
            deck.removeAll()
            nextCursor = 0
            try? await loadNextPage()
            isLoading = false
        } catch {
            print(error)
            isLoading = false
        }
    }

    private func recomputeDuplicates() {
        var counts: [String: Int] = [:]
        for it in orderedAll {
            if let id = it.track?.id { counts[id, default: 0] += 1 }
        }
        duplicateIDs = Set(counts.filter { $0.value > 1 }.map { $0.key })
    }

    private func isDuplicate(trackID: String?) -> Bool {
        guard let id = trackID else { return false }
        return duplicateIDs.contains(id)
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
            if direction == .left {
                removedURIs.append(uri)
                if let tr = item.track {
                    pendingRemoved.append(
                        RemovalEntry(
                            source: .playlist,
                            playlistID: playlist.id,
                            playlistName: playlist.name,
                            trackID: tr.id,
                            trackURI: tr.uri,
                            trackName: tr.name,
                            artists: tr.artists.map { $0.name },
                            album: tr.album.name,
                            artworkURL: tr.album.images?.first?.url
                        )
                    )
                }
            } else {
                keepURIs.append(uri)
            }
        }
        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func undo() {
        guard topIndex > 0 else { return }
        topIndex -= 1
        if let uri = deck[topIndex].track?.uri {
            if let i = removedURIs.lastIndex(of: uri) { removedURIs.remove(at: i) }
            if let j = pendingRemoved.lastIndex(where: { $0.trackURI == uri }) {
                pendingRemoved.remove(at: j)
            }
            if let i = keepURIs.lastIndex(of: uri) { keepURIs.remove(at: i) }
        }
    }

    private func skip() { topIndex += 1 }

    private func commitRemovals() async {
        do {
            try await api.batchRemoveTracks(playlistID: playlist.id, uris: removedURIs, auth: auth)
            // Persist only entries that correspond to the committed URIs
            let toPersist = pendingRemoved.filter { e in
                if let u = e.trackURI { return removedURIs.contains(u) }
                return false
            }
            HistoryStore.shared.add(toPersist)
            pendingRemoved.removeAll()
            removedURIs.removeAll()
        } catch { print(error) }
    }
}
