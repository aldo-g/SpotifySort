import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var api: SpotifyAPI
    @ObservedObject var store = HistoryStore.shared

    @State private var restoring: Set<UUID> = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.white)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("No history yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Removed songs will appear here after you commit changes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                } else {
                    List {
                        ForEach(store.entries) { e in
                            HStack(spacing: 12) {
                                RemoteImage(url: e.artworkURL)
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(e.trackName).font(.headline).lineLimit(1)
                                    Text(e.artists.joined(separator: ", "))
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    Text(sourceText(e))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await revert(e) }
                                } label: {
                                    if restoring.contains(e.id) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Revert", systemImage: "arrow.uturn.backward.circle.fill")
                                            .labelStyle(.iconOnly)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(restoring.contains(e.id) || !canRevert(e))
                                .opacity(canRevert(e) ? 1 : 0.4)
                                .accessibilityLabel("Revert")
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    Task { await revert(e) }
                                } label: {
                                    Label("Revert", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                                .disabled(restoring.contains(e.id) || !canRevert(e))
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sourceText(_ e: RemovalEntry) -> String {
        switch e.source {
        case .liked: return "Removed from Liked Songs"
        case .playlist: return "Removed from \(e.playlistName ?? "Playlist")"
        }
    }

    private func canRevert(_ e: RemovalEntry) -> Bool {
        switch e.source {
        case .liked: return e.trackID != nil
        case .playlist: return e.playlistID != nil && e.trackURI != nil
        }
    }

    // MARK: - Revert action (now removes entry on success)
    private func revert(_ e: RemovalEntry) async {
        guard canRevert(e), !restoring.contains(e.id) else { return }
        restoring.insert(e.id)
        defer { restoring.remove(e.id) }

        do {
            switch e.source {
            case .liked:
                if let id = e.trackID {
                    try await api.batchSaveTracks(trackIDs: [id], auth: auth)
                } else { throw RevertError.missingIdentifiers }
            case .playlist:
                if let pid = e.playlistID, let uri = e.trackURI {
                    try await api.batchAddTracks(playlistID: pid, uris: [uri], auth: auth)
                } else { throw RevertError.missingIdentifiers }
            }
            // ✅ Remove from history immediately after successful restore
            await store.remove(id: e.id)
            ToastCenter.shared.show("Restored")
        } catch {
            print("Revert failed:", error)
            ToastCenter.shared.show("Restore failed")
        }
    }

    enum RevertError: Error { case missingIdentifiers }
}
