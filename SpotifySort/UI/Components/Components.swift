import SwiftUI

// ──────────────────────────────────────────────────────────────────────────────
// Provider card (unchanged)
// ──────────────────────────────────────────────────────────────────────────────
struct ProviderCard: View {
    let title: String
    let subtitle: String
    let assetName: String
    let accent: Color
    let actionTitle: String
    let isLoading: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button(action: action) {
                HStack {
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(actionTitle).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(accent.opacity(isDisabled ? 0.25 : 1))
                .foregroundStyle(isDisabled ? .secondary : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isDisabled || isLoading)
        }
        .padding(14)
        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Chip
// ──────────────────────────────────────────────────────────────────────────────
struct ToolbarMenuChip: View {
    var title: String
    var isActive: Bool = false

    init(title: String, isActive: Bool = false) {
        self.title = title
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            LinearGradient(
                colors: isActive
                    ? [.white.opacity(0.18), .white.opacity(0.08)]
                    : [.white.opacity(0.06), .white.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(.white.opacity(isActive ? 0.35 : 0.15), lineWidth: 1))
        .overlay(BrickOverlay().blendMode(.overlay))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }
}

// Preference key used to expose the chip’s rect up to the screen
struct ChipBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Playlist Selector (toolbar chip only; screen renders the dropdown overlay)
// ──────────────────────────────────────────────────────────────────────────────
struct PlaylistSelector: View {
    var title: String
    var playlists: [Playlist]
    var currentID: String?
    var includeLikedRow: Bool = true
    var onSelectLiked: () -> Void
    var onSelectPlaylist: (String) -> Void

    /// Externally controlled open/close state (screen owns overlay)
    var isOpenExternal: Binding<Bool>? = nil

    init(
        title: String,
        playlists: [Playlist],
        currentID: String?,
        includeLikedRow: Bool = true,
        onSelectLiked: @escaping () -> Void,
        onSelectPlaylist: @escaping (String) -> Void,
        isOpen: Binding<Bool>? = nil
    ) {
        self.title = title
        self.playlists = playlists
        self.currentID = currentID
        self.includeLikedRow = includeLikedRow
        self.onSelectLiked = onSelectLiked
        self.onSelectPlaylist = onSelectPlaylist
        self.isOpenExternal = isOpen
    }

    var body: some View {
        Button {
            let new = !(isOpenExternal?.wrappedValue ?? false)
            isOpenExternal?.wrappedValue = new
            print("[DEBUG][Dropdown] Toggle → \(new ? "OPEN" : "CLOSED")")
        } label: {
            ToolbarMenuChip(title: title, isActive: isOpenExternal?.wrappedValue ?? false)
        }
        // Expose our bounds so the screen can anchor the panel under the chip.
        .anchorPreference(key: ChipBoundsKey.self, value: .bounds) { $0 }
        .accessibilityIdentifier("PlaylistSelectorChip")
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Dropdown panel view (rendered by the screen, not by the toolbar).
// ──────────────────────────────────────────────────────────────────────────────
struct DropdownPanel: View {
    var width: CGFloat
    var origin: CGPoint
    var playlists: [Playlist]
    var currentID: String?
    var includeLikedRow: Bool
    var onDismiss: () -> Void
    var onSelectLiked: () -> Void
    var onSelectPlaylist: (String) -> Void

    @State private var appear = false

    var body: some View {
        let baseIndex = includeLikedRow ? 1 : 0

        ZStack(alignment: .topLeading) {
            // Backdrop: captures taps and closes
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    print("[DEBUG][Dropdown] Backdrop received tap")
                    onDismiss()
                }

            // ROWS ONLY — no outer rounded rectangle "box"
            VStack(spacing: 8) {
                if includeLikedRow {
                    AnimatedSelectorRow(
                        title: "Liked Songs",
                        isSelected: currentID == nil,
                        index: 0,
                        appear: appear,
                        action: {
                            print("[DEBUG][Dropdown] Row tapped → Liked Songs")
                            onSelectLiked()
                            onDismiss()
                        }
                    )
                }

                ForEach(Array(playlists.enumerated()), id: \.element.id) { (i, pl) in
                    AnimatedSelectorRow(
                        title: pl.name,
                        isSelected: pl.id == currentID,
                        index: i + baseIndex,
                        appear: appear,
                        action: {
                            print("[DEBUG][Dropdown] Row tapped → Playlist id=\(pl.id)")
                            onSelectPlaylist(pl.id)
                            onDismiss()
                        }
                    )
                }
            }
            .padding(12)
            .frame(width: width)
            .contentShape(Rectangle())
            .offset(x: origin.x, y: origin.y)
            .onAppear {
                print("[DEBUG][Dropdown] Panel appeared @ (\(origin.x.rounded()), \(origin.y.rounded())) width=\(Int(width))")
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { appear = true }
            }
        }
        .zIndex(2000)
        .allowsHitTesting(true)
    }
}

private struct AnimatedSelectorRow: View {
    var title: String
    var isSelected: Bool
    var index: Int
    var appear: Bool
    var action: () -> Void

    var body: some View {
        Button(action: {
            print("[DEBUG][Dropdown] Row button tap → \"\(title)\" (selected=\(isSelected))")
            action()
        }) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(.white)          // full white
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // -- BACKGROUNDS (behind the text) --
            .background(
                ZStack {
                    // blur material
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // gradient tint (now under the text)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.purple.opacity(0.55), Color.indigo.opacity(0.65)]
                                    : [Color.black.opacity(0.50), Color.black.opacity(0.32)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )

                    // texture (still under text)
                    BrickOverlay()
                        .blendMode(.overlay)
                        .opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            )

            // -- ONLY THE STROKE OVER THE TOP --
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(isSelected ? 0.32 : 0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            .compositingGroup() // ensure all layers clip/blend together cleanly
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -8)
        .animation(.spring(response: 0.4, dampingFraction: 0.95).delay(0.03 * Double(index)), value: appear)
        .accessibilityIdentifier("DropdownRow_\(title)")
    }
}
