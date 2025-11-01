import SwiftUI
import UIKit

enum SwipeDirection { case left, right }

// MARK: - Custom Shape with Bottom Notch
struct RoundedRectangleWithNotch: Shape {
    var cornerRadius: CGFloat
    var notchRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notchCenterX = rect.midX
        let notchBottomY = rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: notchCenterX + notchRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: notchCenterX, y: notchBottomY),
                    radius: notchRadius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct SwipeCard: View {
    let track: Track
    let addedAt: String?
    let addedBy: String?
    let isDuplicate: Bool
    let onSwipe: (SwipeDirection) -> Void
    var fixedSize: CGSize? = nil
    var onDragX: (CGFloat) -> Void = { _ in }

    // Unified environment (api/auth/previews inside)
    @EnvironmentObject var env: AppEnvironment

    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false

    // Playback
    @State private var previewURL: String?
    @State private var isResolvingPreview = false
    @State private var isPlaying = false
    @State private var waveform: [Float]? = nil
    
    // Metadata (now loaded asynchronously)
    @State private var popularity: Int?
    @State private var genreChips: [String] = []
    
    @ObservedObject private var player = PreviewPlayer.shared

    private var primaryArtistID: String? { track.artists.first?.id }
    
    private let reservedPlayerHeight: CGFloat = 44
    private let cardCornerRadius: CGFloat = 18
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
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1))
                    .overlay {
                        if isResolvingPreview && previewURL == nil {
                            ProgressView().padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                Button {
                    ShareService.share(track: track)
                } label: {
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
                        PopularityBar(value: Double(pop) / 100.0).frame(height: 6)
                        Text("\(pop)").font(.caption2).foregroundStyle(.white.opacity(0.7))
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
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .background(
            CardPatternBackground(artURL: track.album.images?.first?.url, cornerRadius: cardCornerRadius)
                .overlay(BrickOverlay().blendMode(.overlay))
                .clipShape(RoundedRectangleWithNotch(cornerRadius: cardCornerRadius, notchRadius: notchRadius))
        )
        .clipShape(RoundedRectangleWithNotch(cornerRadius: cardCornerRadius, notchRadius: notchRadius))
        .overlay(
            RoundedRectangleWithNotch(cornerRadius: cardCornerRadius, notchRadius: notchRadius)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .frame(width: targetWidth, height: targetHeight)
        .rotation3DEffect(.degrees(SwipeDynamics.tilt(forDragX: offset.width)), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.55), radius: SwipeDynamics.lift(forDragX: offset.width), y: 6)
        .offset(x: offset.width, y: offset.height)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture()
                .updating($isDragging) { _, s, _ in s = true }
                .onChanged { value in
                    offset = value.translation
                    onDragX(offset.width)
                }
                .onEnded { value in
                    onDragX(0)
                    if value.translation.width > SwipeDynamics.swipeThreshold { animateSwipe(.right) }
                    else if value.translation.width < -SwipeDynamics.swipeThreshold { animateSwipe(.left) }
                    else { withAnimation(.spring) { offset = .zero } }
                }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: offset)
        // Load metadata asynchronously
        .task(id: track.id) {
            // Load cached metadata
            if let id = track.id {
                popularity = await env.service.getTrackPopularity(id: id) ?? track.popularity
            } else {
                popularity = track.popularity
            }
            
            if let aid = primaryArtistID,
               let genres = await env.service.getArtistGenres(id: aid), !genres.isEmpty {
                genreChips = Array(genres.prefix(3))
            }
        }
        .task(id: track.id ?? track.uri ?? track.name) { await resolvePreview() }
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
        Haptics.impactMedium()
    }

    private func stopPlayback() {
        if isPlaying {
            PreviewPlayer.shared.stop()
            isPlaying = false
        }
    }

    private func resolvePreview() async {
        isResolvingPreview = true
        defer { isResolvingPreview = false }
        let (url, wf) = await env.previews.resolve(for: track)
        previewURL = url
        waveform = wf
    }
}
