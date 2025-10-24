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

    // Preview state
    @State private var previewURL: String?
    @State private var isResolvingPreview = false
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Artwork + floating play button (if preview exists)
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: track.album.images?.first?.url)
                    .frame(height: 260)
                    .clipped()
                    .cornerRadius(14)

                if isResolvingPreview && previewURL == nil {
                    ProgressView()
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(12)
                }

                if let url = previewURL {
                    Button {
                        if isPlaying {
                            PreviewPlayer.shared.stop()
                            isPlaying = false
                        } else {
                            PreviewPlayer.shared.play(url)
                            isPlaying = true
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .shadow(radius: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                // Title + explicit badge
                HStack {
                    Text(track.name)
                        .font(.title3)
                        .bold()
                        .lineLimit(2)
                    if track.explicit == true {
                        Text("E")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Artists
                Text(track.artists.map { $0.name }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Album + Year
                Text(albumLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Added By / Added At
                if let info = addedInfoLine {
                    Text(info)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Duplicate badge
                if isDuplicate {
                    Label("Duplicate in this playlist", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 6)
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

    // MARK: - Helpers

    private var albumLine: String {
        let year = (track.album.release_date ?? "").prefix(4)
        if year.isEmpty { return track.album.name }
        return "\(track.album.name) • \(year)"
    }

    private var addedInfoLine: String? {
        let added = addedAt?.prefix(10) ?? ""   // YYYY-MM-DD
        if let by = addedBy, !by.isEmpty {
            return "Added by \(by)\(added.isEmpty ? "" : " • \(added)")"
        } else if !added.isEmpty {
            return "Added \(added)"
        }
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

    // Resolve Spotify/Deezer preview and cache into API.previewMap
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
            await MainActor.run {
                api.previewMap[key] = deezer
            }
        }
    }
}
