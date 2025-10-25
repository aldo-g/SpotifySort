import Foundation
import Combine

struct RemovalEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable { case playlist, liked }

    let id: UUID
    let timestamp: Date
    let source: Source
    let playlistID: String?
    let playlistName: String?   // nil for liked
    let trackID: String?        // Spotify track ID (for liked) if available
    let trackURI: String?       // Spotify URI (for playlists) if available
    let trackName: String
    let artists: [String]
    let album: String?
    let artworkURL: String?

    init(
        source: Source,
        playlistID: String?,
        playlistName: String?,
        trackID: String?,
        trackURI: String?,
        trackName: String,
        artists: [String],
        album: String?,
        artworkURL: String?,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.source = source
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.trackID = trackID
        self.trackURI = trackURI
        self.trackName = trackName
        self.artists = artists
        self.album = album
        self.artworkURL = artworkURL
    }
}

/// Simple, durable history store backed by UserDefaults.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [RemovalEntry] = []

    private let key = "history.removals.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEntries = 500

    private init() {
        load()
    }

    func add(_ newEntries: [RemovalEntry]) {
        guard !newEntries.isEmpty else { return }
        // Prepend newest first
        var merged = newEntries + entries
        if merged.count > maxEntries { merged = Array(merged.prefix(maxEntries)) }
        entries = merged
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? decoder.decode([RemovalEntry].self, from: data) else { return }
        entries = decoded
    }
}
