import SwiftUI

/// Renders a precomputed waveform (0...1) and fills it left→right using playback progress.
struct ScrollingWaveform: View {
    let samples: [Float]
    let progress: Double
    var height: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let n = max(samples.count, 1)
            let step = geo.size.width / CGFloat(n)
            let capW = max(2, step * 0.75)

            ZStack {
                // Full waveform (dim)
                Canvas { ctx, size in
                    for (i, amp) in samples.enumerated() {
                        let x = CGFloat(i) * step
                        let h = max(2, CGFloat(amp) * size.height)
                        let rect = CGRect(x: x, y: (size.height - h) / 2, width: capW, height: h)
                        ctx.fill(
                            Path(roundedRect: rect, cornerSize: CGSize(width: capW/2, height: capW/2)),
                            with: .color(.white.opacity(0.35))
                        )
                    }
                }

                // Played overlay (left→right)
                let played = Int(Double(n) * progress)
                Canvas { ctx, size in
                    guard played > 0 else { return }
                    for i in 0..<min(played, n) {
                        let amp = samples[i]
                        let x = CGFloat(i) * step
                        let h = max(2, CGFloat(amp) * size.height)
                        let rect = CGRect(x: x, y: (size.height - h) / 2, width: capW, height: h)
                        ctx.fill(
                            Path(roundedRect: rect, cornerSize: CGSize(width: capW/2, height: capW/2)),
                            with: .color(.white)
                        )
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Waveform")
    }
}
