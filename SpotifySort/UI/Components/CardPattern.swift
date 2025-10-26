import SwiftUI
import UIKit

/// Generative, album-aware pattern with contrast safety:
/// - filters near-white colors
/// - darkens palette if still bright
/// - adds dynamic scrim for text legibility
struct CardPatternBackground: View {
    let artURL: String?
    var cornerRadius: CGFloat = 18

    @State private var colors: [Color]? = nil
    @State private var avgLuma: CGFloat = 0
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let palette = colors, palette.count >= 2 {
                // Base gradient using two strongest post-processed colors
                let base = Array(palette.prefix(2))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: base, startPoint: .topLeading, endPoint: .bottomTrailing))

                // Angular accent if we have a 3rd color
                if palette.count >= 3 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AngularGradient(gradient: Gradient(colors: [
                            palette[2].opacity(0.28),
                            base[0].opacity(0.14),
                            base[1].opacity(0.18),
                            palette[2].opacity(0.28)
                        ]), center: .center))
                        .blendMode(.overlay)
                }

                // Wavy stripes
                PatternStripes(color: (palette.last ?? .white).opacity(0.9), radius: cornerRadius)
                    .blendMode(.softLight)
                    .opacity(0.55)

                // Dynamic scrim: stronger if the palette is bright
                let scrim = scrimOpacity(forAvgLuma: avgLuma)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(scrim))
            } else {
                // Fallback
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black)
            }

            // Subtle border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .task(id: artURL) {
            guard !isLoading else { return }
            isLoading = true
            defer { isLoading = false }

            // Pull raw palette
            guard let ui = await PaletteExtractor.palette(fromURL: artURL) else {
                self.colors = nil
                return
            }

            // 1) drop near-white swatches
            let filtered = ui.filter { $0.relativeLuminance < 0.86 }

            // 2) ensure we have at least 2 colors
            var safe = filtered
            if safe.count < 2 {
                // darken originals to guarantee contrast
                safe = ui.map { $0.darkened(0.4) }
            }

            // 3) if still bright overall, globally darken a bit
            let avg = safe.map(\.relativeLuminance).reduce(0, +) / CGFloat(max(safe.count, 1))
            var finalUI = safe
            if avg > 0.72 {
                finalUI = safe.map { $0.darkened(0.25) }
            }

            await MainActor.run {
                self.avgLuma = finalUI.map(\.relativeLuminance).reduce(0, +) / CGFloat(max(finalUI.count, 1))
                self.colors = finalUI.map { Color($0) }
            }
        }
    }

    private func scrimOpacity(forAvgLuma l: CGFloat) -> Double {
        // Map luminance → scrim opacity. Brighter palettes get more scrim.
        // Typical range: 0.18 (dark) → 0.42 (bright)
        let clamped = min(max(l, 0), 1)
        return Double(0.18 + (clamped * 0.24))
    }
}

private struct PatternStripes: View {
    var color: Color
    var radius: CGFloat

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let stripeW: CGFloat = 28
                let gap: CGFloat = 18
                let slope: CGFloat = 0.45
                let total = Int(ceil((size.width + size.height) / (stripeW + gap))) + 2

                for i in 0..<total {
                    let x = CGFloat(i) * (stripeW + gap) - size.height * slope * 0.5
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: -size.height))
                    path.addLine(to: CGPoint(x: x + stripeW, y: -size.height))
                    path.addLine(to: CGPoint(x: x + stripeW + slope*size.height, y: size.height*2))
                    path.addLine(to: CGPoint(x: x + slope*size.height, y: size.height*2))
                    path.closeSubpath()

                    ctx.fill(path, with: .color(color.opacity(0.14)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - UIColor helpers

private extension UIColor {
    /// WCAG relative luminance (0=black, 1=white)
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat {
            return c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
        }
        let R = lin(r), G = lin(g), B = lin(b)
        return 0.2126 * R + 0.7152 * G + 0.0722 * B
    }

    /// Darkens color by mixing toward black by `amount` (0..1).
    func darkened(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = max(0, min(1, amount))
        return UIColor(red: r * (1 - k), green: g * (1 - k), blue: b * (1 - k), alpha: a)
    }
}

// MARK: - Shared grid overlay (exported for app-wide use)
public struct BrickOverlay: View {
    var lineWidth: CGFloat = 1
    var rowHeight: CGFloat = 44
    var columnWidth: CGFloat = 88
    var opacity: CGFloat = 0.10

    public init(
        lineWidth: CGFloat = 1,
        rowHeight: CGFloat = 44,
        columnWidth: CGFloat = 88,
        opacity: CGFloat = 0.10
    ) {
        self.lineWidth = lineWidth
        self.rowHeight = rowHeight
        self.columnWidth = columnWidth
        self.opacity = opacity
    }

    public var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let hLines = stride(from: 0.0, through: size.height, by: rowHeight)
                for (i, y) in hLines.enumerated() {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)

                    let offset = (i % 2 == 0) ? 0.0 : columnWidth / 2
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
