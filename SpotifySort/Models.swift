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
    var track: Track?   // var + optional so we can patch URI and tolerate bad items

    enum CodingKeys: String, CodingKey { case added_at, track }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added_at = try? c.decode(String.self, forKey: .added_at)
        track = try? c.decode(Track.self, forKey: .track)  // tolerant decode
    }
}

struct Track: Codable, Hashable {
    var id: String?
    var name: String
    var uri: String?          // must be var (we synthesize spotify:track:<id>)
    var artists: [Artist]
    var album: Album
    var type: String?         // "track" or "episode"
}

struct Artist: Codable, Hashable { let name: String }
struct Album: Codable, Hashable { let name: String; let images: [SpotifyImage]? }
