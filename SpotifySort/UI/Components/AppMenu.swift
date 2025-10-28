import SwiftUI

/// Full-screen overlay menu styled for Spotify.
///
/// Usage in a screen:
/// .overlay(
///   AppMenu(isOpen: $showMenu, spotifyUserName: auth.user?.display_name) { action in /* ... */ }
/// )
struct AppMenu: View {
    @Binding var isOpen: Bool
    var spotifyUserName: String? = nil
    var onSelect: (MenuAction) -> Void = { _ in }

    // Your glyph asset; change if you renamed it.
    private let spotifyAssetName = "Image"

    var body: some View {
        ZStack {
            if isOpen {
                // Dimmer behind the panel
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 12) {
                        Image(spotifyAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spotify")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(spotifyUserName ?? "Connected")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: { close() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(10)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Close menu")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 54)
                    .padding(.bottom, 16)

                    Divider().overlay(Color.white.opacity(0.08))

                    // Items
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            AppMenuRow(icon: "heart.fill", title: "Liked Songs") { act(.liked) }
                            AppMenuRow(icon: "clock", title: "History") { act(.history) }
                            AppMenuRow(icon: "gearshape.fill", title: "Settings") { act(.settings) }
                            AppMenuRow(icon: "info.circle.fill", title: "About") { act(.about) }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 8)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.black)               // full opaque overlay
                .ignoresSafeArea()
                .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isOpen)
    }

    private func act(_ a: MenuAction) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onSelect(a) }
    }

    private func close() { withAnimation { isOpen = false } }
}

/// Actions emitted by the menu.
enum MenuAction { case liked, history, settings, about }

private struct AppMenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 26)
                    .foregroundColor(.white.opacity(0.92))

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
