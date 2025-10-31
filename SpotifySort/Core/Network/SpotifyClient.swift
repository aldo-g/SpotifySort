import Foundation

/// Pure HTTP client for Spotify Web API.
/// Actor-based to run network calls off main thread.
/// Takes access tokens directly - no AuthManager dependency.
actor SpotifyClient {
    
    private let decoder = JSONDecoder()
    
    // MARK: - Request Building
    
    private func buildRequest(
        _ path: String,
        token: String,
        method: String = "GET",
        body: Data? = nil
    ) -> URLRequest? {
        guard let url = URL(string: path) else { return nil }
        
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return req
    }
    
    // MARK: - User / Playlists
    
    func fetchUser(token: String) async throws -> SpotifyUser {
        guard let req = buildRequest("https://api.spotify.com/v1/me", token: token) else {
            throw ClientError.invalidRequest
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(SpotifyUser.self, from: data)
    }
    
    func fetchPlaylists(token: String) async throws -> [Playlist] {
        var url = "https://api.spotify.com/v1/me/playlists?limit=50"
        var result: [Playlist] = []
        
        while true {
            guard let req = buildRequest(url, token: token) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try decoder.decode(PlaylistPage.self, from: data)
            result.append(contentsOf: page.items)
            
            if let next = page.next, !next.isEmpty {
                url = next
            } else {
                break
            }
        }
        
        return result.filter { $0.tracks.total > 0 }
    }
    
    // MARK: - Playlist Tracks
    
    func fetchAllPlaylistTracks(
        playlistID: String,
        token: String
    ) async throws -> [PlaylistTrack] {
        var url = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=100&market=from_token"
        var all: [PlaylistTrack] = []
        
        while true {
            guard let req = buildRequest(url, token: token) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try decoder.decode(TrackPage.self, from: data)
            
            let batch = page.items.compactMap { item -> PlaylistTrack? in
                guard var tr = item.track else { return nil }
                if let t = tr.type, t != "track" { return nil }
                if tr.uri == nil, let id = tr.id { tr.uri = "spotify:track:\(id)" }
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
        
        return all
    }
    
    // MARK: - Saved Tracks
    
    func fetchAllSavedTracks(token: String) async throws -> [PlaylistTrack] {
        var url = "https://api.spotify.com/v1/me/tracks?limit=50&market=from_token"
        var all: [PlaylistTrack] = []
        
        while true {
            guard let req = buildRequest(url, token: token) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try decoder.decode(TrackPage.self, from: data)
            
            let batch = page.items.compactMap { item -> PlaylistTrack? in
                guard var tr = item.track, let id = tr.id else { return nil }
                if let t = tr.type, t != "track" { return nil }
                if tr.uri == nil { tr.uri = "spotify:track:\(id)" }
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
        
        return all
    }
    
    func fetchSavedTracksPage(
        token: String,
        nextURL: String? = nil
    ) async throws -> (items: [PlaylistTrack], next: String?) {
        let url = nextURL ?? "https://api.spotify.com/v1/me/tracks?limit=50&market=from_token"
        guard let req = buildRequest(url, token: token) else {
            return ([], nil)
        }
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try decoder.decode(TrackPage.self, from: data)
        
        let items = page.items.compactMap { item -> PlaylistTrack? in
            guard var tr = item.track, let id = tr.id else { return nil }
            if let t = tr.type, t != "track" { return nil }
            if tr.uri == nil { tr.uri = "spotify:track:\(id)" }
            var copy = item
            copy.track = tr
            return copy
        }
        
        return (items, page.next)
    }
    
    // MARK: - Mutations
    
    func removeTracks(
        playlistID: String,
        uris: [String],
        token: String
    ) async throws {
        guard !uris.isEmpty else { return }
        
        for chunk in uris.chunked(into: 90) {
            let body = ["tracks": chunk.map { ["uri": $0] }]
            let data = try JSONSerialization.data(withJSONObject: body)
            
            guard let req = buildRequest(
                "https://api.spotify.com/v1/playlists/\(playlistID)/tracks",
                token: token,
                method: "DELETE",
                body: data
            ) else { continue }
            
            _ = try await URLSession.shared.data(for: req)
        }
    }
    
    func unsaveTracks(trackIDs: [String], token: String) async throws {
        guard !trackIDs.isEmpty else { return }
        
        for chunk in trackIDs.chunked(into: 50) {
            let ids = chunk.joined(separator: ",")
            guard var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks") else { continue }
            comps.queryItems = [URLQueryItem(name: "ids", value: ids)]
            
            guard let url = comps.url,
                  var req = buildRequest(url.absoluteString, token: token, method: "DELETE") else { continue }
            req.setValue(nil, forHTTPHeaderField: "Content-Type")
            
            _ = try await URLSession.shared.data(for: req)
        }
    }
    
    func saveTracks(trackIDs: [String], token: String) async throws {
        guard !trackIDs.isEmpty else { return }
        
        for chunk in trackIDs.chunked(into: 50) {
            let ids = chunk.joined(separator: ",")
            guard var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks") else { continue }
            comps.queryItems = [URLQueryItem(name: "ids", value: ids)]
            
            guard let url = comps.url,
                  var req = buildRequest(url.absoluteString, token: token, method: "PUT") else { continue }
            req.setValue(nil, forHTTPHeaderField: "Content-Type")
            
            _ = try await URLSession.shared.data(for: req)
        }
    }
    
    func addTracks(
        playlistID: String,
        uris: [String],
        token: String
    ) async throws {
        guard !uris.isEmpty else { return }
        
        for chunk in uris.chunked(into: 90) {
            let body = ["uris": chunk]
            let data = try JSONSerialization.data(withJSONObject: body)
            
            guard let req = buildRequest(
                "https://api.spotify.com/v1/playlists/\(playlistID)/tracks",
                token: token,
                method: "POST",
                body: data
            ) else { continue }
            
            _ = try await URLSession.shared.data(for: req)
        }
    }
    
    // MARK: - Metadata
    
    func fetchArtistGenres(artistIDs: [String], token: String) async throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        
        for chunk in artistIDs.chunked(into: 50) {
            let ids = chunk.joined(separator: ",")
            guard let req = buildRequest(
                "https://api.spotify.com/v1/artists?ids=\(ids)",
                token: token
            ) else { continue }
            
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                struct Resp: Decodable {
                    struct A: Decodable { let id: String; let genres: [String] }
                    let artists: [A]
                }
                let resp = try decoder.decode(Resp.self, from: data)
                for a in resp.artists {
                    result[a.id] = a.genres
                }
            } catch {
                // Continue on partial failures
            }
        }
        
        return result
    }
    
    func fetchTrackPopularity(trackIDs: [String], token: String) async throws -> [String: Int] {
        var result: [String: Int] = [:]
        
        for chunk in trackIDs.chunked(into: 50) {
            let ids = chunk.joined(separator: ",")
            guard let req = buildRequest(
                "https://api.spotify.com/v1/tracks?ids=\(ids)",
                token: token
            ) else { continue }
            
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                struct Resp: Decodable {
                    struct T: Decodable { let id: String; let popularity: Int }
                    let tracks: [T]
                }
                let resp = try decoder.decode(Resp.self, from: data)
                for t in resp.tracks {
                    result[t.id] = t.popularity
                }
            } catch {
                // Continue on partial failures
            }
        }
        
        return result
    }
    
    // MARK: - Error
    
    enum ClientError: Error {
        case invalidRequest
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
}
