import SwiftUI

struct SortView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var router: Router
    let playlist: Playlist

    @State private var orderedAll: [PlaylistTrack] = []
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0

    @State private var topIndex: Int = 0
    @State private var isLoading = true
    @State private var showHistory = false

    @State private var duplicateIDs: Set<String> = []
    private let pageSize = 20

    private var listKey: String { "playlist:\(playlist.id)" }
    @State private var reviewedSet: Set<String> = []

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
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40)).foregroundStyle(.white)
                            Text("All done!").font(.title2).bold().foregroundStyle(.white)
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
                                    isDuplicate: isDuplicate(trackID: tr.id),
                                    onSwipe: { dir in onSwipe(direction: dir, item: item) }
                                )
                                .padding(.horizontal, 16)
                                .zIndex(item.id == deck[topIndex].id ? 1 : 0)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 8)
        }
        .selectrToolbar()
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)   // 👈 hides the default blur/material
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
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
            // History button
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("History")
            }
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .onChange(of: topIndex) { Task { await topUpIfNeeded() } }
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

    // MARK: Actions (auto-commit)

    private func onSwipe(direction: SwipeDirection, item: PlaylistTrack) {
        // record reviewed locally
        if let uri = item.track?.uri {
            ReviewStore.shared.addReviewed(uri, for: listKey)
        }

        if direction == .left, let tr = item.track, let uri = tr.uri {
            Task {
                await removeFromPlaylist(uri: uri, track: tr)
            }
        }

        topIndex += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func removeFromPlaylist(uri: String, track: Track) async {
        do {
            try await api.batchRemoveTracks(playlistID: playlist.id, uris: [uri], auth: auth)
            let entry = RemovalEntry(
                source: .playlist,
                playlistID: playlist.id,
                playlistName: playlist.name,
                trackID: track.id,
                trackURI: track.uri,
                trackName: track.name,
                artists: track.artists.map { $0.name },
                album: track.album.name,
                artworkURL: track.album.images?.first?.url
            )
            await MainActor.run { HistoryStore.shared.add([entry]) }
        } catch {
            print("Remove from playlist failed:", error)
        }
    }
}
