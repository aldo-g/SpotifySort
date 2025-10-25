import SwiftUI

enum SwipeDirection { case left, right }

struct SwipeCard: View {
    let track: Track
    let addedAt: String?
    let addedBy: String?
    let isDuplicate: Bool
    let onSwipe: (SwipeDirection) -> Void

    @EnvironmentObject var api: SpotifyAPI

    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false

    // Preview / playback state
    @State private var previewURL: String?
    @State private var isResolvingPreview = false
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ARTWORK
            RemoteImage(url: track.album.images?.first?.url)
                .frame(height: 260)
                .clipped()
                .cornerRadius(14)
                .overlay {
                    // small spinner while we resolve a preview (optional)
                    if isResolvingPreview && previewURL == nil {
                        ProgressView()
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

            // TRACK INFO
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(track.name)
                        .font(.title3).bold().lineLimit(2)
                    if track.explicit == true {
                        Text("E")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(track.artists.map { $0.name }.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)

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

            // PLAYER STRIP — sits in the empty space at the BOTTOM of the card
            if let url = previewURL {
                HStack(spacing: 12) {
                    Button {
                        if isPlaying {
                            PreviewPlayer.shared.stop()
                            isPlaying = false
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

                    ScrollingWaveform()
                        .frame(height: 26)
                        .opacity(isPlaying ? 1 : 0.55)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
                .glassyPanel(corner: 14) // from Theme.swift – gives a nice “glass” dock
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
        .task(id: track.id ?? track.uri ?? track.name) { await resolvePreviewIfNeeded() }
        .onDisappear {
            if isPlaying {
                PreviewPlayer.shared.stop()
                isPlaying = false
            }
        }
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

    @ViewBuilder func label(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).bold()
            .padding(6)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)
    }

    private func animateSwipe(_ dir: SwipeDirection) {
        if isPlaying { PreviewPlayer.shared.stop(); isPlaying = false }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            offset = CGSize(width: dir == .right ? 800 : -800, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onSwipe(dir)
            offset = .zero
        }
    }

    // --- Resolve Spotify/Deezer preview -------------------------------------
    private func resolvePreviewIfNeeded() async {
        let key = track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"

        if let s = track.preview_url {
            previewURL = s
            return
        }
        if let cached = api.previewMap[key] {
            previewURL = cached
            return
        }

        isResolvingPreview = true
        defer { isResolvingPreview = false }

        if let deezer = await DeezerPreviewService.shared.resolvePreview(for: track) {
            previewURL = deezer
            await MainActor.run { api.previewMap[key] = deezer }
        }
    }
}
