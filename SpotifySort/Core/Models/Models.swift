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
    let added_at: String?
    let added_by: AddedBy?
    var track: Track?
    private let uuid = UUID()
    var id: String { uuid.uuidString }

    private enum CodingKeys: String, CodingKey { case added_at, added_by, track }
}

struct AddedBy: Codable, Hashable { let id: String?; let uri: String? }

// Core track fields we use on cards
struct Track: Codable, Hashable {
    var id: String?
    var name: String
    var uri: String?
    var artists: [Artist]
    var album: Album
    var type: String?
    var preview_url: String?
    var explicit: Bool?
    var duration_ms: Int?
    var popularity: Int?
    var is_playable: Bool?

    // NEW: shareable link holder from API response
    var external_urls: [String: String]?   // e.g. ["spotify": "https://open.spotify.com/track/..."]

    // For Deezer preview lookup
    var isrc: String?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, artists, album, type, preview_url, explicit, duration_ms, popularity, is_playable
        case external_urls
        case external_ids
    }
    enum ExternalIDsKeys: String, CodingKey { case isrc }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try? c.decode(String.self, forKey: .id)
        name         = try c.decode(String.self, forKey: .name)
        uri          = try? c.decode(String.self, forKey: .uri)
        artists      = try c.decode([Artist].self, forKey: .artists)
        album        = try c.decode(Album.self, forKey: .album)
        type         = try? c.decode(String.self, forKey: .type)
        preview_url  = try? c.decode(String.self, forKey: .preview_url)
        explicit     = try? c.decode(Bool.self, forKey: .explicit)
        duration_ms  = try? c.decode(Int.self, forKey: .duration_ms)
        popularity   = try? c.decode(Int.self, forKey: .popularity)
        is_playable  = try? c.decode(Bool.self, forKey: .is_playable)
        external_urls = try? c.decode([String:String].self, forKey: .external_urls)

        if let ext = try? c.nestedContainer(keyedBy: ExternalIDsKeys.self, forKey: .external_ids) {
            isrc = try? ext.decode(String.self, forKey: .isrc)
        } else {
            isrc = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(uri, forKey: .uri)
        try c.encode(artists, forKey: .artists)
        try c.encode(album, forKey: .album)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(preview_url, forKey: .preview_url)
        try c.encodeIfPresent(explicit, forKey: .explicit)
        try c.encodeIfPresent(duration_ms, forKey: .duration_ms)
        try c.encodeIfPresent(popularity, forKey: .popularity)
        try c.encodeIfPresent(is_playable, forKey: .is_playable)
        try c.encodeIfPresent(external_urls, forKey: .external_urls)
        // intentionally NOT encoding external_ids or isrc
    }

    init(
        id: String? = nil,
        name: String,
        uri: String? = nil,
        artists: [Artist],
        album: Album,
        type: String? = nil,
        preview_url: String? = nil,
        explicit: Bool? = nil,
        duration_ms: Int? = nil,
        popularity: Int? = nil,
        is_playable: Bool? = nil,
        external_urls: [String:String]? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.name = name
        self.uri = uri
        self.artists = artists
        self.album = album
        self.type = type
        self.preview_url = preview_url
        self.explicit = explicit
        self.duration_ms = duration_ms
        self.popularity = popularity
        self.is_playable = is_playable
        self.external_urls = external_urls
        self.isrc = isrc
    }
}

// NOW includes optional id (used to fetch genres)
struct Artist: Codable, Hashable {
    let id: String?
    let name: String
}

struct Album: Codable, Hashable {
    let name: String
    let images: [SpotifyImage]?
    let release_date: String?
}

// MARK: - Convenience

extension Track {
    /// Best-effort share URL for Spotify.
    var spotifyURLString: String? {
        if let s = external_urls?["spotify"] { return s }
        if let id { return "https://open.spotify.com/track/\(id)" }
        return nil
    }
}
