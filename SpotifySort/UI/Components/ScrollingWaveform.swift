import SwiftUI

/// A simple scrolling waveform that shifts left as new samples arrive.
/// It consumes PreviewPlayer.shared.levels, compresses each update into one value,
/// and keeps a fixed-size ring buffer to render as vertical capsules.
struct ScrollingWaveform: View {
    @ObservedObject var player = PreviewPlayer.shared

    private let maxSamples = 140
    @State private var buffer: [Float] = Array(repeating: 0, count: 140)

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, min(buffer.count, maxSamples))
            let step = size.width / CGFloat(n)
            let capW = max(2, step * 0.75)

            for (i, amp) in buffer.suffix(n).enumerated() {
                let x = CGFloat(i) * step
                // scale & clamp to look good at ~20–30px height
                let h = max(2, CGFloat(min(max(amp * 3.5, 0), 1)) * size.height)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: capW, height: h)
                ctx.fill(Path(roundedRect: rect, cornerSize: CGSize(width: capW/2, height: capW/2)),
                         with: .color(.white))
            }
        }
        .animation(.linear(duration: 0.06), value: buffer) // subtle glide
        .onChange(of: player.levels) { lvls in
            // compress the current 20-band snapshot to a single sample
            let mean = (lvls.reduce(0, +) / Float(max(lvls.count, 1)))
            var b = buffer
            b.append(mean)
            if b.count > maxSamples { b.removeFirst(b.count - maxSamples) }
            buffer = b
        }
        .accessibilityLabel("Audio visualization")
    }
}
