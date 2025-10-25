import SwiftUI

struct SortLikedView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI

    @State private var orderedAll: [PlaylistTrack] = []
    @State private var deck: [PlaylistTrack] = []
    @State private var nextCursor: Int = 0

    @State private var toUnsaveIDs: [String] = []
    @State private var keepIDs: [String] = []
    @State private var topIndex: Int = 0

    @State private var isLoading = true
    @State private var showCommit = false

    @State private var nextURL: String? = nil
    @State private var isFetching = false
    @State private var allDone = false

    private let sessionSeed = UUID().uuidString
    private let pageSize = 20
    private let warmStartTarget = 100

    private let listKey = "liked"
    @State private var reviewedSet: Set<String> = []

    var body: some View {
        SelectrBackground {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView("Preparing deck…").task { await initialFastStart() }
                } else if topIndex >= deck.count {
                    if !allDone || nextCursor < orderedAll.count {
                        ProgressView("Loading more…").task { await topUpIfNeeded(force: true) }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "heart.slash.fill")
                                .font(.system(size: 40)).foregroundStyle(.white)
                            Text("All liked tracks reviewed")
                                .font(.title3).bold().foregroundStyle(.white)
                            Button("Unsave \(toUnsaveIDs.count) tracks") { showCommit = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(toUnsaveIDs.isEmpty)
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
                                    isDuplicate: false
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
                            .disabled(toUnsaveIDs.isEmpty)
                    }
                    .tint(.white)
                    .glassyPanel()
                }
            }
            .padding(.top, 8)
        }
        .selectrToolbar()
        .navigationTitle("Liked Songs")
        .onChange(of: topIndex) { Task { await topUpIfNeeded() } }
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
        while orderedAll.count < warmStartTarget, !allDone {
            await fetchNextPageAndMerge()
        }
        nextCursor = 0
        deck.removeAll()
        try? await loadNextPage()
        isLoading = false
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
                allDone = (nextURL == nil); return
            }
            orderedAll.append(contentsOf: result.items)
            orderedAll.sort { a, b in rankKey(a) < rankKey(b) }
            if nextURL == nil { allDone = true }
        } catch {
            allDone = true
            print("SavedTracks paging error: \(error)")
        }
    }

    // MARK: Deterministic shuffle with reviewed-last bias

    private func rankKey(_ item: PlaylistTrack) -> (Int, UInt64) {
        let reviewed = isReviewed(item) ? 1 : 0
        let id = item.track?.id ?? item.track?.uri ?? UUID().uuidString
        return (reviewed, fnv1a64(sessionSeed + "|" + id))
    }

    private func isReviewed(_ item: PlaylistTrack) -> Bool {
        if let id = item.track?.id { return reviewedSet.contains(id) }
        if let uri = item.track?.uri { return reviewedSet.contains(uri) }
        return false
    }

    // MARK: Deck paging

    private func loadNextPage() async throws {
        let end = min(nextCursor + pageSize, orderedAll.count)
        guard nextCursor < end else { return }
        deck = Array(orderedAll.prefix(end))
        nextCursor = end
    }

    private func topUpIfNeeded(force: Bool = false) async {
        let remaining = deck.count - topIndex
        guard force || remaining <= 5 else { return }
        try? await loadNextPage()
    }

    // MARK: Actions

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

// Tiny hash (FNV-1a 64-bit) for deterministic shuffle
private func fnv1a64(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash &*= prime
    }
    return hash
}
