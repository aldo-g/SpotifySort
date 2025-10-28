import SwiftUI

/// A tiny overlay button you can drop on any screen.
/// Place with `.overlay(MenuIconOverlay(isOpen: $showMenu), alignment: .topLeading)`
struct MenuIconOverlay: View {
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation { isOpen.toggle() }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.1), in: Circle())
                .padding(.leading, 14)
                .padding(.top, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open menu")
    }
}
