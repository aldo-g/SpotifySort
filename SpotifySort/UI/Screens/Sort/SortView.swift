import SwiftUI

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

    @State private var duplicateIDs: Set<String> = []
    private let pageSize = 20

    private var listKey: String { "playlist:\(playlist.id)" }
    @State private var reviewedSet: Set<String> = []

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
        .navigationTitle(playlist.name)
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
