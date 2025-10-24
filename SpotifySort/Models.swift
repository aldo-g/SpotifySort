import Foundation

struct SpotifyUser: Codable, Hashable { let id: String; let display_name: String? }

struct PlaylistPage: Codable { let items: [Playlist]; let next: String? }
struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let owner: Owner
    let tracks: TrackRef
    let images: [SpotifyImage]?
}
struct Owner: Codable, Hashable { let id: String }
struct TrackRef: Codable, Hashable { let total: Int }
struct SpotifyImage: Codable, Hashable { let url: String }

// MARK: - Tracks / Playlist Items

struct TrackPage: Codable { let items: [PlaylistTrack]; let next: String? }

struct PlaylistTrack: Codable, Hashable, Identifiable {
    // Spotify returns ISO8601 strings; we keep as String for lightweight decode
    let added_at: String?
    let added_by: AddedBy?
    var track: Track?
    // Stable-ish identity per card/session
    private let uuid = UUID()
    var id: String { uuid.uuidString }
}

struct AddedBy: Codable, Hashable { let id: String?; let uri: String? }

// Core track fields we use on cards
struct Track: Codable, Hashable {
    var id: String?
    var name: String
    var uri: String?          // must be var (we synthesize spotify:track:<id>)
    var artists: [Artist]
    var album: Album
    var type: String?         // "track" or "episode"
    var preview_url: String?
    var explicit: Bool?
    var duration_ms: Int?
    var popularity: Int?
    var is_playable: Bool?
}

struct Artist: Codable, Hashable { let name: String }
struct Album: Codable, Hashable {
    let name: String
    let images: [SpotifyImage]?
    let release_date: String?
}
