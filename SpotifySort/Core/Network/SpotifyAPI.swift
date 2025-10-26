// SpotifySort/Core/Network/SpotifyAPI.swift
import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {
    // MARK: - Published state
    @Published var user: SpotifyUser?
    @Published var playlists: [Playlist] = []

    /// Cache for preview URLs (Spotify/Deezer) keyed by track key (id/uri/name|artist).
    @Published var previewMap: [String: String] = [:]

    /// Cache of artist genres keyed by artist ID.
    @Published var artistGenres: [String: [String]] = [:]

    /// NEW: Cache of track popularity (0–100) keyed by track ID.
    @Published var trackPopularity: [String: Int] = [:]

    // MARK: - HTTP helper

    func authorizedRequest(
        _ path: String,
        auth: AuthManager,
        method: String = "GET",
        body: Data? = nil
    ) -> URLRequest? {
        guard let token = auth.accessToken,
              let url = URL(string: path)
        else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    // MARK: - Me / Playlists

    func loadMe(auth: AuthManager) async throws {
        guard let req = authorizedRequest("https://api.spotify.com/v1/me", auth: auth)
        else { return }
        let (data, _) = try await URLSession.shared.data(for: req)
        user = try JSONDecoder().decode(SpotifyUser.self, from: data)
    }

    func loadPlaylists(auth: AuthManager) async throws {
        var url = "https://api.spotify.com/v1/me/playlists?limit=50"
        var result: [Playlist] = []

        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(PlaylistPage.self, from: data)
            result.append(contentsOf: page.items)
            if let next = page.next, !next.isEmpty {
                url = next
            } else {
                break
            }
        }
        playlists = result.filter { $0.tracks.total > 0 }
    }

    // MARK: - Playlist Tracks

    func loadAllPlaylistTracksOrdered(
        playlistID: String,
        auth: AuthManager,
        reviewedURIs: Set<String>
    ) async throws -> [PlaylistTrack] {
        var url = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=100&market=from_token"
        var all: [PlaylistTrack] = []

        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(TrackPage.self, from: data)

            let batch = page.items.compactMap { item -> PlaylistTrack? in
                guard var tr = item.track else { return nil }
                if let t = tr.type, t != "track" { return nil }
                if tr.uri == nil, let id = tr.id { tr.uri = "spotify:track:\(id)" }
                // Cache popularity when present
                if let id = tr.id, let pop = tr.popularity { trackPopularity[id] = pop }

                var copy = item
                copy.track = tr
                return copy
            }

            all.append(contentsOf: batch)
            if let next = page.next, !next.isEmpty {
                url = next + "&market=from_token"
            } else {
                break
            }
        }

        // Reviewed-last bias + randomized within groups
        let (unreviewed, reviewed) = all.partitioned {
            guard let uri = $0.track?.uri else { return false }
            return !reviewedURIs.contains(uri)
        }
        return unreviewed.shuffled() + reviewed.shuffled()
    }

    // MARK: - Saved Tracks

    func loadAllSavedTracksOrdered(
        auth: AuthManager,
        reviewedIDs: Set<String>
    ) async throws -> [PlaylistTrack] {
        var url = "https://api.spotify.com/v1/me/tracks?limit=50&market=from_token"
        var all: [PlaylistTrack] = []

        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(TrackPage.self, from: data)

            let batch = page.items.compactMap { item -> PlaylistTrack? in
                guard var tr = item.track, let id = tr.id else { return nil }
                if let t = tr.type, t != "track" { return nil }
                if tr.uri == nil { tr.uri = "spotify:track:\(id)" }
                // Cache popularity when present
                if let pop = tr.popularity { trackPopularity[id] = pop }

                var copy = item
                copy.track = tr
                return copy
            }

            all.append(contentsOf: batch)
            if let next = page.next, !next.isEmpty {
                url = next + "&market=from_token"
            } else { break }
        }

        let (unreviewed, reviewed) = all.partitioned {
            guard let id = $0.track?.id else { return false }
            return !reviewedIDs.contains(id)
        }
        return unreviewed.shuffled() + reviewed.shuffled()
    }

    // MARK: - Paged fetch for Liked Songs

    func fetchSavedTracksPage(
        auth: AuthManager,
        nextURL: String? = nil
    ) async throws -> (items: [PlaylistTrack], next: String?) {
        let url = nextURL ?? "https://api.spotify.com/v1/me/tracks?limit=50&market=from_token"
        guard let req = authorizedRequest(url, auth: auth)
        else { return ([], nil) }

        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(TrackPage.self, from: data)

        let items = page.items.compactMap { item -> PlaylistTrack? in
            guard var tr = item.track, let id = tr.id else { return nil }
            if let t = tr.type, t != "track" { return nil }
            if tr.uri == nil { tr.uri = "spotify:track:\(id)" }
            // Cache popularity when present
            if let pop = tr.popularity { trackPopularity[id] = pop }

            var copy = item
            copy.track = tr
            return copy
        }
        return (items, page.next)
    }

    // MARK: - Mutations (remove)

    func batchRemoveTracks(playlistID: String, uris: [String], auth: AuthManager) async throws {
        guard !uris.isEmpty else { return }
        for chunk in uris.chunked(into: 90) {
            let body = ["tracks": chunk.map { ["uri": $0] }]
            let data = try JSONSerialization.data(withJSONObject: body)
            guard let req = authorizedRequest(
                "https://api.spotify.com/v1/playlists/\(playlistID)/tracks",
                auth: auth,
                method: "DELETE",
                body: data
            ) else { continue }
            _ = try await URLSession.shared.data(for: req)
        }
    }

    func batchUnsaveTracks(trackIDs: [String], auth: AuthManager) async throws {
        guard !trackIDs.isEmpty else { return }
        for chunk in trackIDs.chunked(into: 50) {
            let ids = chunk.joined(separator: ",")
            guard var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")
            else { continue }
            comps.queryItems = [URLQueryItem(name: "ids", value: ids)]
            guard let url = comps.url,
                  var req = authorizedRequest(url.absoluteString, auth: auth, method: "DELETE")
            else { continue }
            req.setValue(nil, forHTTPHeaderField: "Content-Type")
            _ = try await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Mutations (restore / add)

    /// Re-add saved tracks to the user's library.
    func batchSaveTracks(trackIDs: [String], auth: AuthManager) async throws {
        guard !trackIDs.isEmpty else { return }
        for chunk in trackIDs.chunked(into: 50) {
            let ids = chunk.joined(separator: ",")
            guard var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")
            else { continue }
            comps.queryItems = [URLQueryItem(name: "ids", value: ids)]
            guard let url = comps.url,
                  var req = authorizedRequest(url.absoluteString, auth: auth, method: "PUT")
            else { continue }
            req.setValue(nil, forHTTPHeaderField: "Content-Type")
            _ = try await URLSession.shared.data(for: req)
        }
    }

    /// Add tracks to a playlist by Spotify URI.
    func batchAddTracks(playlistID: String, uris: [String], auth: AuthManager) async throws {
        guard !uris.isEmpty else { return }
        for chunk in uris.chunked(into: 90) {
            let body = ["uris": chunk]
            let data = try JSONSerialization.data(withJSONObject: body)
            guard let req = authorizedRequest(
                "https://api.spotify.com/v1/playlists/\(playlistID)/tracks",
                auth: auth,
                method: "POST",
                body: data
            ) else { continue }
            _ = try await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Artist Genres

    private struct ArtistFull: Codable { let id: String; let genres: [String] }
    private struct ArtistsResp: Codable { let artists: [ArtistFull] }

    /// Batch fetch genres for up to 50 artist IDs and merge into `artistGenres`.
    func fetchArtistGenres(ids: [String], auth: AuthManager) async throws {
        guard !ids.isEmpty else { return }
        for chunk in ids.chunked(into: 50) {
            let joined = chunk.joined(separator: ",")
            guard let req = authorizedRequest("https://api.spotify.com/v1/artists?ids=\(joined)", auth: auth)
            else { continue }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(ArtistsResp.self, from: data)
            for a in resp.artists {
                artistGenres[a.id] = a.genres
            }
        }
    }

    /// Ensure we have genres for given artist IDs; fetches only the missing ones.
    func ensureArtistGenres(for ids: [String], auth: AuthManager) async {
        let missing = ids.filter { artistGenres[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            try await fetchArtistGenres(ids: missing, auth: auth)
        } catch {
            print("Genres fetch failed:", error)
        }
    }

    // MARK: - Track Popularity (NEW)

    private struct TracksResp: Codable {
        struct TrackSlim: Codable {
            let id: String
            let popularity: Int?
        }
        let tracks: [TrackSlim]
    }

    /// Batch fetch popularity for up to 50 track IDs and merge into `trackPopularity`.
    func fetchTrackPopularity(ids: [String], auth: AuthManager) async throws {
        guard !ids.isEmpty else { return }
        for chunk in ids.chunked(into: 50) {
            let joined = chunk.joined(separator: ",")
            guard let req = authorizedRequest("https://api.spotify.com/v1/tracks?ids=\(joined)", auth: auth)
            else { continue }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(TracksResp.self, from: data)
            for t in resp.tracks {
                if let pop = t.popularity { trackPopularity[t.id] = pop }
            }
        }
    }

    /// Ensure we have popularity cached for given track IDs; fetches only missing.
    func ensureTrackPopularity(for ids: [String], auth: AuthManager) async {
        let missing = ids.filter { trackPopularity[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            try await fetchTrackPopularity(ids: missing, auth: auth)
        } catch {
            print("Popularity fetch failed:", error)
        }
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }

    func partitioned(_ isFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for el in self {
            if isFirst(el) { first.append(el) } else { second.append(el) }
        }
        return (first, second)
    }
}
