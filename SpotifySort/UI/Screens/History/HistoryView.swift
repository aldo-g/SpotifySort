import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = HistoryStore.shared

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
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(sourceText(e))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(dateFormatter.string(from: e.timestamp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .listRowBackground(Color.clear)
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
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sourceText(_ e: RemovalEntry) -> String {
        switch e.source {
        case .liked: return "Removed from Liked Songs"
        case .playlist:
            return "Removed from \(e.playlistName ?? "Playlist")"
        }
    }
}
