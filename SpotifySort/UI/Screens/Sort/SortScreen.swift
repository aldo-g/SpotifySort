import SwiftUI

enum SortMode { case liked, playlist(Playlist) }

struct SortScreen: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var router: Router
    @EnvironmentObject var metadata: TrackMetadataService  // ← NEW

    let mode: SortMode
    
    // ✅ REFACTOR: Use ViewModel with proper dependency injection
    @StateObject private var viewModel: DeckViewModel
    
    // UI-only state (not business logic)
    @State private var showHistory = false
    @State private var isDropdownOpen = false
    @State private var showMenu = false
    
    // MARK: - Initialization
    
    init(mode: SortMode, api: SpotifyAPI, auth: AuthManager) {
        self.mode = mode
        // Create ViewModel with proper dependencies
        _viewModel = StateObject(wrappedValue: DeckViewModel(
            mode: mode,
            api: api,
            auth: auth
        ))
    }

    // MARK: - Computed Properties
    
    private var ownedPlaylists: [Playlist] {
        guard let me = api.user?.id else { return api.playlists }
        return api.playlists.filter { $0.owner.id == me && $0.tracks.total > 0 }
    }
    
    /// Signature to trigger tasks when deck content changes
    private var deckSignature: String {
        viewModel.deck.map { $0.track?.id ?? $0.track?.uri ?? $0.track?.name ?? "?" }.joined(separator: "|")
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            SelectrBackground {
                VStack(spacing: 12) {
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.isComplete {
                        completionView
                    } else {
                        deckView
                            .padding(.top, -50)
                            .allowsHitTesting(!isDropdownOpen)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(.top, 8)
            }

            EdgeGlows(
                intensityLeft: viewModel.leftIntensity,
                intensityRight: viewModel.rightIntensity
            )
            .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .tint(.white)
        
        // Top bar with playlist selector
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }

        // Dropdown overlay
        .overlayPreferenceValue(ChipBoundsKey.self) { anchor in
            dropdownOverlay(anchor: anchor)
        }
        
        // Sheets & overlays
        .sheet(isPresented: $showHistory) { HistoryView() }
        .overlay(appMenuOverlay, alignment: .topLeading)
        
        // Load data when view appears
        .task {
            await viewModel.load()
        }
        
        // 🔁 NEW: Prefetch track metadata (popularity + genres) whenever the visible deck changes
        .task(id: deckSignature) {
            let visibleTracks = viewModel.deck.compactMap { $0.track }
            await metadata.prefetch(for: visibleTracks, api: api, auth: auth)
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        ProgressView(mode.isLiked ? "Preparing deck…" : "Loading…")
    }
    
    private var completionView: some View {
        Group {
            switch mode {
            case .liked:
                VStack(spacing: 10) {
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 40)).foregroundStyle(.white)
                    Text("All liked tracks reviewed")
                        .font(.title3).bold().foregroundStyle(.white)
                }
            case .playlist:
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40)).foregroundStyle(.white)
                    Text("All done!").font(.title2).bold().foregroundStyle(.white)
                }
            }
        }
    }
    
    private var deckView: some View {
        ZStack {
            ForEach(Array(viewModel.deck.enumerated()).reversed(), id: \.element.id) { idx, item in
                if idx >= viewModel.topIndex, let tr = item.track {
                    let isTop = (item.id == viewModel.deck[viewModel.topIndex].id)
                    SwipeCard(
                        track: tr,
                        addedAt: item.added_at,
                        addedBy: item.added_by?.id,
                        isDuplicate: viewModel.isDuplicate(trackID: tr.id),
                        onSwipe: { dir in
                            Task { await viewModel.swipe(direction: dir, item: item) }
                        },
                        onDragX: isTop ? { viewModel.updateDragX($0) } : { _ in }
                    )
                    .padding(.horizontal, 16)
                    .zIndex(isTop ? 1 : 0)
                }
            }
        }
    }
    
    private var topBar: some View {
        ZStack {
            // Centered dropdown chip
            PlaylistSelector(
                title: viewModel.chipTitle,
                playlists: ownedPlaylists,
                currentID: viewModel.currentPlaylistID,
                includeLikedRow: true,
                onSelectLiked: { router.selectLiked() },
                onSelectPlaylist: { id in router.selectPlaylist(id) },
                isOpen: $isDropdownOpen
            )

            // Left menu & right history
            HStack {
                GlassIconButton(system: "line.3.horizontal") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        showMenu.toggle()
                    }
                }

                Spacer()

                GlassIconButton(system: "clock.arrow.circlepath") {
                    showHistory = true
                }
                .accessibilityLabel("History")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.clear)
        .zIndex(2001)
    }
    
    private func dropdownOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if isDropdownOpen, let a = anchor {
                let rect = proxy[a]
                let width = max(rect.width, 260)
                DropdownPanel(
                    width: width,
                    origin: CGPoint(x: rect.midX - width/2, y: rect.maxY + 8),
                    playlists: ownedPlaylists,
                    currentID: viewModel.currentPlaylistID,
                    includeLikedRow: true,
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            isDropdownOpen = false
                        }
                    },
                    onSelectLiked: { router.selectLiked() },
                    onSelectPlaylist: { id in router.selectPlaylist(id) }
                )
            }
        }
    }
    
    private var appMenuOverlay: some View {
        AppMenu(isOpen: $showMenu) { action in
            switch action {
            case .liked: router.selectLiked()
            case .history: showHistory = true
            case .settings, .about: break
            }
        }
        .environmentObject(auth)
    }
}

// MARK: - Edge Glows

private struct EdgeGlows: View {
    var intensityLeft: CGFloat
    var intensityRight: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color.red.opacity(0.55 * intensityLeft),
                             Color.red.opacity(0.28 * intensityLeft),
                             .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.42)
                .blur(radius: 22)
                .blendMode(.screen)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, alignment: .leading)

                LinearGradient(
                    colors: [Color.green.opacity(0.55 * intensityRight),
                             Color.green.opacity(0.28 * intensityRight),
                             .clear],
                    startPoint: .trailing, endPoint: .leading
                )
                .frame(width: geo.size.width * 0.42)
                .blur(radius: 22)
                .blendMode(.screen)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Glass Icon Button

private struct GlassIconButton: View {
    let system: String
    let action: () -> Void
    private let size: CGFloat = 34
    private let radius: CGFloat = 10

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color.black.opacity(0.30))
                            .blendMode(.multiply)
                    )
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .overlay(
                        BrickOverlay(opacity: 0.12)
                            .blendMode(.overlay)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .inset(by: 0.5)
                            .stroke(.black.opacity(0.22), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)

                Image(systemName: system)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Extensions

private extension SortMode {
    var isLiked: Bool {
        if case .liked = self { return true }
        else { return false }
    }
}
