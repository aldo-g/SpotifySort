import Foundation

/// Represents a removed track for undo/redo functionality.
struct RemovalEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case playlist
        case liked
    }

    let id: UUID
    let timestamp: Date
    let source: Source
    let playlistID: String?
    let playlistName: String?
    let trackID: String?
    let trackURI: String?
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
