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

struct TrackPage: Codable { let items: [PlaylistTrack]; let next: String? }

struct PlaylistTrack: Codable, Identifiable, Hashable {
    let id = UUID()
    let added_at: String?
    let track: Track?
    enum CodingKeys: String, CodingKey { case added_at, track }
}

struct Track: Codable, Hashable {
    let id: String?
    let name: String
    let uri: String?
    let artists: [Artist]
    let album: Album
}

struct Artist: Codable, Hashable { let name: String }

struct Album: Codable, Hashable {
    let name: String
    let images: [SpotifyImage]?
}
