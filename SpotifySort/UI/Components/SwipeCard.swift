import SwiftUI
import UIKit

enum SwipeDirection { case left, right }

struct SwipeCard: View {
    let track: Track
    let addedAt: String?
    let addedBy: String?
    let isDuplicate: Bool
    let onSwipe: (SwipeDirection) -> Void
    var fixedSize: CGSize? = nil
    var onDragX: (CGFloat) -> Void = { _ in }

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
    private let cornerRadius: CGFloat = 18
    private let notchRadius: CGFloat = 26

    var body: some View {
        let targetWidth = fixedSize?.width ?? (UIScreen.main.bounds.width * 0.88)
        let targetHeight = fixedSize?.height ?? 640

        VStack(spacing: 12) {
            // === ART ===
            ZStack(alignment: .bottomTrailing) {
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

                // === SHARE ICON (no container) ===
                Button(action: shareTrack) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share track")
            }

            // === INFO ===
            BrickTile {
                InfoBlock(track: track, genreChips: genreChips, addedInfoLine: addedInfoLine)
            }

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
            }

            Spacer(minLength: 0)

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
            NotchedCardShape(cornerRadius: cornerRadius, notchRadius: notchRadius)
                .fill(Color.clear)  // Invisible fill for the shape
                .background(
                    CardPatternBackground(artURL: track.album.images?.first?.url, cornerRadius: cornerRadius)
                        .overlay(BrickOverlay().blendMode(.overlay))
                )
                .clipShape(NotchedCardShape(cornerRadius: cornerRadius, notchRadius: notchRadius))
        )
        .clipShape(NotchedCardShape(cornerRadius: cornerRadius, notchRadius: notchRadius))
        .overlay(
            NotchedCardShape(cornerRadius: cornerRadius, notchRadius: notchRadius)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .frame(width: targetWidth, height: targetHeight)
        .rotation3DEffect(.degrees(dragTilt), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.55), radius: dragLift, y: 6)
        .offset(x: offset.width, y: offset.height)
        .contentShape(NotchedCardShape(cornerRadius: cornerRadius, notchRadius: notchRadius))
        .simultaneousGesture(
            DragGesture()
                .updating($isDragging) { _, s, _ in s = true }
                .onChanged { value in
                    offset = value.translation
                    onDragX(offset.width)
                }
                .onEnded { value in
                    onDragX(0)
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

    // MARK: - Share action
    private func shareTrack() {
        if let id = track.id, let url = URL(string: "https://open.spotify.com/track/\(id)") {
            presentShare(items: [url])
        } else {
            presentShare(items: [track.name])
        }
    }

    private func presentShare(items: [Any]) {
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(av, animated: true)
        }
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

// MARK: - (helper subviews)
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

/// Simple left→right fill bar used for popularity.
private struct PopularityBar: View {
    let value: Double   // 0...1
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 3).fill(.white)
                    .frame(width: max(0, min(1, value)) * w)
            }
        }
        .frame(height: 6)
    }
}

/// Custom shape with rounded corners and a semicircular notch at the bottom center
private struct NotchedCardShape: Shape {
    var cornerRadius: CGFloat = 18
    var notchRadius: CGFloat = 20
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let notchCenter = CGPoint(x: rect.midX, y: rect.maxY)
        
        // Start from top-left, just after the corner
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        
        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        
        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        // Bottom edge to notch (right side)
        path.addLine(to: CGPoint(x: notchCenter.x + notchRadius, y: rect.maxY))
        
        // Semicircular notch (going inward/upward)
        path.addArc(
            center: notchCenter,
            radius: notchRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true  // clockwise creates the inward notch
        )
        
        // Continue bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        
        // Left edge back to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        
        path.closeSubpath()
        return path
    }
}
