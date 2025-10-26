import SwiftUI

enum SwipeDirection { case left, right }

struct SwipeCard: View {
    let track: Track
    let addedAt: String?
    let addedBy: String?
    let isDuplicate: Bool
    let onSwipe: (SwipeDirection) -> Void

    // NEW: force a uniform size from parent
    var fixedSize: CGSize? = nil

    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var auth: AuthManager

    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false

    // Playback
    @State private var previewURL: String?
    @State private var isResolvingPreview = false
    @State private var isPlaying = false
    @State private var waveform: [Float]? = nil
    @ObservedObject private var player = PreviewPlayer.shared

    // Cached
    private var popularity: Int? {
        if let id = track.id, let cached = api.trackPopularity[id] { return cached }
        return track.popularity
    }
    private var primaryArtistID: String? { track.artists.first?.id }
    private var genreChips: [String] {
        guard let aid = primaryArtistID,
              let genres = api.artistGenres[aid], !genres.isEmpty
        else { return [] }
        return Array(genres.prefix(3))
    }

    private var previewKey: String {
        track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"
    }

    private var dragTilt: Double { Double(offset.width) / 22 }
    private var dragLift: CGFloat { 8 + min(18, abs(offset.width) / 12) }

    private let reservedPlayerHeight: CGFloat = 44

    var body: some View {
        // Compute consistent size (either provided or a sensible default)
        let targetWidth = fixedSize?.width ?? (UIScreen.main.bounds.width * 0.88)
        let targetHeight = fixedSize?.height ?? 640

        VStack(spacing: 12) {
            // === ART ===
            RemoteImage(url: track.album.images?.first?.url)
                .frame(height: 260)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .overlay {
                    if isResolvingPreview && previewURL == nil {
                        ProgressView().padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

            // === INFO ===
            BrickTile {
                InfoBlock(
                    track: track,
                    genreChips: genreChips,
                    addedInfoLine: addedInfoLine
                )
            }
            .frame(maxWidth: .infinity)

            // === POPULARITY ===
            if let pop = popularity {
                BrickTile {
                    VStack(alignment: .leading, spacing: 8) {
                        MetaRow(system: "chart.bar.fill", text: "Spotify popularity")
                        PopularityBar(value: Double(pop) / 100.0)
                            .frame(height: 6)
                        Text("\(pop)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
            BrickSeparator()

            // === PLAYER (reserved height even if no preview) ===
            Group {
                if let url = previewURL {
                    HStack(spacing: 12) {
                        Button {
                            if isPlaying { stopPlayback() }
                            else { PreviewPlayer.shared.play(url); isPlaying = true }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 32, height: 32)
                                .background(.white, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        if let wf = waveform {
                            ScrollingWaveform(samples: wf, progress: player.progress, height: 26)
                                .opacity(isPlaying ? 1 : 0.9)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.12))
                                .frame(height: 26)
                                .overlay(ProgressView().scaleEffect(0.7))
                        }
                    }
                } else {
                    Color.clear
                }
            }
            .frame(height: reservedPlayerHeight)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .background(
            CardChromeBW()
                .overlay(BrickOverlay().blendMode(.overlay))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(width: targetWidth, height: targetHeight)       // <- UNIFORM SIZE
        .rotation3DEffect(.degrees(dragTilt), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.55), radius: dragLift, y: 6)
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
        .task(id: track.id ?? track.uri ?? track.name) { await resolvePreviewIfNeeded() }
        .task(id: primaryArtistID) {
            if let aid = primaryArtistID { await api.ensureArtistGenres(for: [aid], auth: auth) }
        }
        .task(id: track.id) {
            if let id = track.id { await api.ensureTrackPopularity(for: [id], auth: auth) }
        }
        .onDisappear { stopPlayback() }
    }

    // MARK: - Helpers

    private var addedInfoLine: String? {
        let added = addedAt?.prefix(10) ?? ""
        if let by = addedBy, !by.isEmpty { return "Added by \(by)\(added.isEmpty ? "" : " • \(added)")" }
        if !added.isEmpty { return "Added \(added)" }
        return nil
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stopPlayback() {
        if isPlaying {
            PreviewPlayer.shared.stop()
            isPlaying = false
        }
    }

    private func resolvePreviewIfNeeded() async {
        let key = previewKey

        if let s = track.preview_url {
            previewURL = s
            Task { waveform = await WaveformStore.shared.waveform(for: key, previewURL: s) }
            return
        }
        if let cached = api.previewMap[key] {
            if let ok = await DeezerPreviewService.shared.validatePreview(urlString: cached, trackKey: key, track: track) {
                previewURL = ok
                _ = await MainActor.run { api.previewMap[key] = ok }
                Task { waveform = await WaveformStore.shared.waveform(for: key, previewURL: ok) }
                return
            } else {
                _ = await MainActor.run { api.previewMap.removeValue(forKey: key) }
            }
        }

        isResolvingPreview = true
        defer { isResolvingPreview = false }

        if let deezer = await DeezerPreviewService.shared.resolvePreview(for: track) {
            previewURL = deezer
            _ = await MainActor.run { api.previewMap[key] = deezer }
            Task { waveform = await WaveformStore.shared.waveform(for: key, previewURL: deezer) }
        }
    }
}

// MARK: - (rest of the helper views unchanged)
private struct InfoBlock: View {
    let track: Track
    let genreChips: [String]
    let addedInfoLine: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(track.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if track.explicit == true {
                    Image(systemName: "e.square.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Explicit")
                }
            }
            Text(track.artists.map { $0.name }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            let albumName = track.album.name
            if !albumName.isEmpty {
                Text(albumSubtitle(from: albumName, date: track.album.release_date))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            if !genreChips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(genreChips, id: \.self) { g in Pill(text: g.capitalized) }
                }
                .padding(.top, 2)
            }
            if let info = addedInfoLine { MetaRow(system: "clock", text: info) }
        }
    }
    private func albumSubtitle(from name: String, date: String?) -> String {
        let year = (date ?? "").prefix(4)
        return year.isEmpty ? name : "\(name) • \(year)"
    }
}

private struct BrickTile<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

private struct MetaRow: View {
    let system: String; let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: system).font(.caption2).foregroundStyle(.white)
            Text(text).font(.caption).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

private struct Pill: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

private struct CardChromeBW: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
    }
}

private struct PopularityBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: max(0, min(1, value)) * w)
            }
        }.frame(height: 6)
    }
}

private struct BrickSeparator: View {
    var height: CGFloat = 8
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: height)
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width, brick = 28.0, gap = 10.0
                    HStack(spacing: gap) {
                        ForEach(0..<Int(ceil(w / (brick + gap))), id: \.self) { _ in
                            Rectangle().fill(.white.opacity(0.22)).frame(width: brick, height: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: (height - 1) / 2)
                }
            )
            .accessibilityHidden(true)
    }
}

private struct BrickOverlay: View {
    var lineWidth: CGFloat = 1, rowHeight: CGFloat = 44, columnWidth: CGFloat = 88, opacity: CGFloat = 0.10
    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let hLines = stride(from: 0.0, through: size.height, by: rowHeight)
                for (i, y) in hLines.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
                    let offset = (i % 2 == 0) ? 0.0 : columnWidth/2
                    var x = -offset
                    while x <= size.width + columnWidth {
                        var v = Path()
                        v.move(to: CGPoint(x: x, y: y))
                        v.addLine(to: CGPoint(x: x, y: min(y + rowHeight, size.height)))
                        ctx.stroke(v, with: .color(.white.opacity(opacity * 0.9)), lineWidth: 0.8)
                        x += columnWidth
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
