import SwiftUI

enum SwipeDirection { case left, right }

struct SwipeCard: View {
    let track: Track
    let addedAt: String?
    let addedBy: String?
    let isDuplicate: Bool
    let onSwipe: (SwipeDirection) -> Void

    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var auth: AuthManager

    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false

    // Preview / playback state
    @State private var previewURL: String?
    @State private var isResolvingPreview = false
    @State private var isPlaying = false

    // Waveform state
    @State private var waveform: [Float]? = nil
    @ObservedObject private var player = PreviewPlayer.shared

    // Popularity from cache or inline field
    private var popularity: Int? {
        if let id = track.id, let cached = api.trackPopularity[id] { return cached }
        return track.popularity
    }

    private var previewKey: String {
        track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"
    }

    private var primaryArtistID: String? { track.artists.first?.id }

    private var genreChips: [String] {
        guard let aid = primaryArtistID,
              let genres = api.artistGenres[aid], !genres.isEmpty
        else { return [] }
        return Array(genres.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ARTWORK
            RemoteImage(url: track.album.images?.first?.url)
                .frame(height: 260)
                .clipped()
                .cornerRadius(14)
                .overlay {
                    if isResolvingPreview && previewURL == nil {
                        ProgressView()
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

            // TRACK INFO + Share
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(track.name)
                        .font(.title3).bold().lineLimit(2)

                    if let shareURL = shareURL {
                        Spacer(minLength: 6)
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(6)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share")
                    }
                }

                Text(track.artists.map { $0.name }.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)

                // Genres chips
                let chips = genreChips
                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { g in
                            Text(g.capitalized)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }

                // Popularity badge + tiny meter
                if let pop = popularity {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption2)
                            Text("Popularity \(pop)")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.9))

                        PopularityBar(value: Double(pop) / 100.0)
                            .frame(height: 6)
                    }
                    .padding(.top, 2)
                }

                Text(albumLine)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)

                if let info = addedInfoLine {
                    Text(info).font(.caption2).foregroundStyle(.secondary)
                }

                if isDuplicate {
                    Label("Duplicate in this playlist", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.yellow).padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            // PLAYER STRIP — only shown when a preview is available
            if let url = previewURL {
                HStack(spacing: 12) {
                    Button {
                        if isPlaying {
                            stopPlayback()
                        } else {
                            PreviewPlayer.shared.play(url)
                            isPlaying = true
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(.white, in: Circle())
                            .shadow(radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)

                    if let wf = waveform {
                        ScrollingWaveform(
                            samples: wf,
                            progress: player.progress,
                            height: 26
                        )
                        .opacity(isPlaying ? 1 : 0.9)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.25))
                            .frame(height: 26)
                            .overlay(ProgressView().scaleEffect(0.8))
                    }
                }
                .padding(.vertical, 10)
                .glassyPanel(corner: 14)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 6)

        // swipe affordances
        .overlay(alignment: .topLeading) { label("KEEP", .green).opacity(offset.width > 60 ? 1 : 0) }
        .overlay(alignment: .topTrailing) { label("REMOVE", .red).opacity(offset.width < -60 ? 1 : 0) }
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .offset(x: offset.width, y: offset.height)
        .gesture(
            DragGesture()
                .updating($isDragging) { _, s, _ in s = true }
                .onChanged { value in offset = value.translation }
                .onEnded { value in
                    if value.translation.width > 120 { animateSwipe(.right) }
                    else if value.translation.width < -120 { animateSwipe(.left) }
                    else { withAnimation(.spring) { offset = .zero } }
                }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: offset)

        // Load preview + waveform (silent if missing)
        .task(id: track.id ?? track.uri ?? track.name) { await resolvePreviewIfNeeded() }

        // Ensure artist genres (by ID)
        .task(id: primaryArtistID) {
            if let aid = primaryArtistID {
                await api.ensureArtistGenres(for: [aid], auth: auth)
            }
        }

        // Ensure popularity for this track (lazy)
        .task(id: track.id) {
            if let id = track.id {
                await api.ensureTrackPopularity(for: [id], auth: auth)
            }
        }

        .onDisappear { stopPlayback() }
    }

    // MARK: Helpers -----------------------------------------------------------

    private var albumLine: String {
        let year = (track.album.release_date ?? "").prefix(4)
        return year.isEmpty ? track.album.name : "\(track.album.name) • \(year)"
    }

    private var addedInfoLine: String? {
        let added = addedAt?.prefix(10) ?? ""
        if let by = addedBy, !by.isEmpty { return "Added by \(by)\(added.isEmpty ? "" : " • \(added)")" }
        if !added.isEmpty { return "Added \(added)" }
        return nil
    }

    private var shareURL: URL? {
        guard let s = track.spotifyURLString, let u = URL(string: s) else { return nil }
        return u
    }

    @ViewBuilder func label(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).bold()
            .padding(6)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)
    }

    private func animateSwipe(_ dir: SwipeDirection) {
        stopPlayback()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            offset = CGSize(width: dir == .right ? 800 : -800, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onSwipe(dir)
            offset = .zero
        }
    }

    private func stopPlayback() {
        if isPlaying {
            PreviewPlayer.shared.stop()
            isPlaying = false
        }
    }

    // --- Resolve Spotify/Deezer preview + waveform (no toast) ---------------
    private func resolvePreviewIfNeeded() async {
        let key = previewKey

        // 0) Spotify preview if present
        if let s = track.preview_url {
            previewURL = s
            Task { waveform = await WaveformStore.shared.waveform(for: key, previewURL: s) }
            return
        }

        // 1) App-level cache (validate before use)
        if let cached = api.previewMap[key] {
            if let ok = await DeezerPreviewService.shared.validatePreview(urlString: cached, trackKey: key, track: track) {
                previewURL = ok
                await MainActor.run { api.previewMap[key] = ok }
                Task { waveform = await WaveformStore.shared.waveform(for: key, previewURL: ok) }
                return
            } else {
                await MainActor.run { api.previewMap.removeValue(forKey: key) }
            }
        }

        isResolvingPreview = true
        defer { isResolvingPreview = false }

        // 2) Deezer resolve
        if let deezer = await DeezerPreviewService.shared.resolvePreview(for: track) {
            previewURL = deezer
            await MainActor.run { api.previewMap[key] = deezer }
            Task { waveform = await WaveformStore.shared.waveform(for: key, previewURL: deezer) }
        }
    }
}

// Tiny meter view (inline for convenience)
private struct PopularityBar: View {
    let value: Double // 0...1
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white)
                    .frame(width: max(0, min(1, value)) * w)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Popularity")
    }
}
