import SwiftUI

// MARK: - Theme

enum SelectrTheme {
    static let accent = Color(hex: 0xA78BFA)      // soft purple
    static let gradient: [Color] = [
        Color(hex: 0x111827), // near-black blue
        Color(hex: 0x1F2937), // slate
        Color(hex: 0x6D28D9)  // purple pop
    ]
}

// Small Color convenience
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Shared backgrounds & modifiers

struct SelectrBackground<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            LinearGradient(colors: SelectrTheme.gradient,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
            content
        }
    }
}

extension View {
    /// Applies Selectr nav/toolbar styling (white titles/icons) over a transparent bar.
    func selectrToolbar() -> some View {
        self
            .tint(.white)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }

    /// A light “glass” look for control bars/buttons on dark gradient.
    func glassyPanel(corner: CGFloat = 16) -> some View {
        self
            .padding(.horizontal)
            .padding(.bottom)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }
}
