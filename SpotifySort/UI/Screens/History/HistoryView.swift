import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var store = HistoryStore.shared

    @State private var restoring: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                // match app background treatment
                LinearGradient(colors: SelectrTheme.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                    .overlay(BrickOverlay().blendMode(.overlay).opacity(0.35))

                if store.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("No history yet").font(.headline).foregroundStyle(.white.opacity(0.9))
                        Text("Removed songs will appear here after you swipe left.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.entries) { e in
                                HistoryRow(entry: e,
                                           isRestoring: restoring.contains(e.id),
                                           onRevert: { Task { await revert(e) } })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { store.clear() } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
            .tint(.white)
        }
        .presentationDetents([.medium, .large])
    }

    private func canRevert(_ e: RemovalEntry) -> Bool {
        switch e.source {
        case .liked: return e.trackID != nil
        case .playlist: return e.playlistID != nil && e.trackURI != nil
        }
    }

    private func revert(_ e: RemovalEntry) async {
        guard canRevert(e), !restoring.contains(e.id) else { return }
        restoring.insert(e.id)
        defer { restoring.remove(e.id) }

        do {
            switch e.source {
            case .liked:
                try await env.service.batchSaveTracks(trackIDs: [e.trackID!])
            case .playlist:
                try await env.service.batchAddTracks(playlistID: e.playlistID!, uris: [e.trackURI!])
            }
            await MainActor.run { store.remove(id: e.id) }
            ToastCenter.shared.show("Restored")
        } catch {
            print("Revert failed:", error)
            ToastCenter.shared.show("Restore failed")
        }
    }
}

private struct HistoryRow: View {
    let entry: RemovalEntry
    let isRestoring: Bool
    let onRevert: () -> Void

    private let r: CGFloat = 14

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: entry.artworkURL)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.trackName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.artists.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Text(sourceText(entry))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()

            Button(action: onRevert) {
                if isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .buttonStyle(.plain)
            .opacity(canRevert(entry) ? 1 : 0.35)
            .disabled(!canRevert(entry) || isRestoring)
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: r).stroke(.white.opacity(0.15), lineWidth: 1))
        .overlay(BrickOverlay().blendMode(.overlay))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private func canRevert(_ e: RemovalEntry) -> Bool {
        switch e.source {
        case .liked: return e.trackID != nil
        case .playlist: return e.playlistID != nil && e.trackURI != nil
        }
    }
    private func sourceText(_ e: RemovalEntry) -> String {
        switch e.source {
        case .liked: return "Removed from Liked Songs"
        case .playlist: return "Removed from \(e.playlistName ?? "Playlist")"
        }
    }
}
