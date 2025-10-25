import SwiftUI

struct SoundBars: View {
    @ObservedObject var player = PreviewPlayer.shared

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(player.levels.indices, id: \.self) { i in
                Capsule()
                    .fill(barColor(for: player.levels[i]))
                    .frame(width: 3, height: CGFloat(max(3, player.levels[i] * 120)))
            }
        }
        .animation(.linear(duration: 0.05), value: player.levels)
    }

    private func barColor(for level: Float) -> Color {
        switch level {
        case 0.0..<0.2: return .green
        case 0.2..<0.4: return .yellow
        default: return .red
        }
    }
}

#Preview {
    SoundBars()
        .frame(height: 40)
        .padding()
        .background(.black)
}
