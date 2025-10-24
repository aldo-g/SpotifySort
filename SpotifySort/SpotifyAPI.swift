import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {
    @Published var user: SpotifyUser?
    @Published var playlists: [Playlist] = []

    func authorizedRequest(_ path: String, auth: AuthManager, method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard let token = auth.accessToken else { return nil }
        var req = URLRequest(url: URL(string: path)!)
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
        guard let req = authorizedRequest("https://api.spotify.com/v1/me", auth: auth) else { return }
        let (data, _) = try await URLSession.shared.data(for: req)
        let me = try JSONDecoder().decode(SpotifyUser.self, from: data)
        user = me
    }

    func loadPlaylists(auth: AuthManager) async throws {
        var url = "https://api.spotify.com/v1/me/playlists?limit=20"
        var result: [Playlist] = []
        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(PlaylistPage.self, from: data)
            result.append(contentsOf: page.items)
            if let next = page.next { url = next } else { break }
        }
        playlists = result
    }

    // MARK: - Tracks (full load, resilient)

    func loadTracks(playlistID: String, auth: AuthManager) async throws -> [PlaylistTrack] {
        var url = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=20"
        var items: [PlaylistTrack] = []
        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)

            // Decode defensively; our Models.swift patch ensures bad items set `track = nil` instead of throwing.
            let page = try JSONDecoder().decode(TrackPage.self, from: data)

            // Keep songs; skip episodes/local/missing-track.
            let kept: [PlaylistTrack] = page.items.compactMap { item in
                guard var tr = item.track else { return nil }
                // If no URI but we have an ID, synthesize a URI so deletes work.
                if tr.uri == nil, let id = tr.id { tr.uri = "spotify:track:\(id)" }
                var newItem = item
                newItem.track = tr
                // Only accept real tracks (type == "track" or unknown); drop episodes.
                if let t = tr.type, t != "track" { return nil }
                return newItem
            }

            items.append(contentsOf: kept)
            if let next = page.next { url = next } else { break }
        }
        return items
    }

    // MARK: - Tracks (paged streaming, resilient)

    func loadTracksPaged(
        playlistID: String,
        auth: AuthManager,
        onPage: @MainActor ([PlaylistTrack]) -> Void
    ) async throws {
        var url = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=20"
        var delivered = false

        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(TrackPage.self, from: data)

            let batch: [PlaylistTrack] = page.items.compactMap { item in
                guard var tr = item.track else { return nil }
                if tr.uri == nil, let id = tr.id { tr.uri = "spotify:track:\(id)" }
                var newItem = item
                newItem.track = tr
                if let t = tr.type, t != "track" { return nil }
                return newItem
            }

            onPage(batch)
            delivered = true

            if let next = page.next { url = next } else { break }
        }

        if !delivered { onPage([]) }
    }

    // MARK: - Mutations

    func batchRemoveTracks(playlistID: String, uris: [String], auth: AuthManager) async throws {
        guard !uris.isEmpty else { return }
        let chunks = uris.chunked(into: 90) // under 100 per request
        for chunk in chunks {
            let body = ["tracks": chunk.map { ["uri": $0] }]
            let data = try JSONSerialization.data(withJSONObject: body)
            guard let req0 = authorizedRequest(
                "https://api.spotify.com/v1/playlists/\(playlistID)/tracks",
                auth: auth, method: "DELETE", body: data
            ) else { continue }
            _ = try await URLSession.shared.data(for: req0)
        }
    }

    // MARK: - Liked Songs

    func loadSavedTracksPaged(
        auth: AuthManager,
        onPage: @MainActor ([PlaylistTrack]) -> Void
    ) async throws {
        var url = "https://api.spotify.com/v1/me/tracks?limit=20"
        var delivered = false

        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(TrackPage.self, from: data)

            let batch: [PlaylistTrack] = page.items.compactMap { item in
                guard var tr = item.track, let id = tr.id else { return nil }
                if tr.uri == nil { tr.uri = "spotify:track:\(id)" }
                var newItem = item
                newItem.track = tr
                if let t = tr.type, t != "track" { return nil }
                return newItem
            }

            onPage(batch)
            delivered = true

            if let next = page.next, !next.isEmpty {
                url = next
            } else { break }
        }

        if !delivered { onPage([]) }
    }

    func batchUnsaveTracks(trackIDs: [String], auth: AuthManager) async throws {
        guard !trackIDs.isEmpty else { return }
        let chunks = trackIDs.chunked(into: 20)
        for chunk in chunks {
            let ids = chunk.joined(separator: ",")
            guard var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks") else { continue }
            comps.queryItems = [URLQueryItem(name: "ids", value: ids)]
            guard let url = comps.url,
                  var req = authorizedRequest(url.absoluteString, auth: auth, method: "DELETE")
            else { continue }
            req.setValue(nil, forHTTPHeaderField: "Content-Type")
            _ = try await URLSession.shared.data(for: req)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
