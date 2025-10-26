import SwiftUI

/// Renders a precomputed waveform (0...1) and fills it left→right using playback progress.
/// If `preRollPhase` is provided (0...1), shows a sweep cursor moving RIGHT→LEFT
/// to indicate imminent autoplay. When playback starts, pass nil.
struct ScrollingWaveform: View {
    let samples: [Float]     // fixed per track
    let progress: Double     // 0...1 from PreviewPlayer.shared.progress
    var height: CGFloat = 26
    var preRollPhase: Double? = nil   // 0...1; nil = no pre-roll indicator

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

                // Pre-roll sweep cursor (RIGHT → LEFT over 1s)
                if let p = preRollPhase {
                    let clamped = min(max(p, 0), 1)
                    let x = (1.0 - clamped) * geo.size.width
                    Rectangle()
                        .fill(.white.opacity(0.9))
                        .frame(width: max(2, capW * 0.4))
                        .offset(x: x - geo.size.width/2)
                        .shadow(radius: 3, y: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Waveform")
    }
}
