import SwiftUI

enum SwipeDirection { case left, right }

struct SwipeCard: View {
    let track: Track
    let onSwipe: (SwipeDirection) -> Void

    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: track.album.images?.first?.url)
                .frame(height: 260)
                .clipped()
                .cornerRadius(14)
            Text(track.name).font(.title3).bold()
            Text(track.artists.map { $0.name }.joined(separator: ", "))
                .foregroundStyle(.secondary)
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
    }

    @ViewBuilder func label(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).bold()
            .padding(6)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)
    }

    func animateSwipe(_ dir: SwipeDirection) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            offset = CGSize(width: dir == .right ? 800 : -800, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onSwipe(dir)
            offset = .zero
        }
    }
}
