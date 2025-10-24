import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {
    @Published var user: SpotifyUser?
    @Published var playlists: [Playlist] = []

    // ===== Liked Songs paging state =====
    private var savedNextURL: String? = nil
    private var savedPagingInFlight = false
    var hasMoreSaved: Bool { savedNextURL != nil }

    // MARK: - HTTP helper

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
        var url = "https://api.spotify.com/v1/me/playlists?limit=50"
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

    // MARK: - Playlist Tracks (paged streaming)

    func loadTracksPaged(
        playlistID: String,
        auth: AuthManager,
        onPage: @MainActor ([PlaylistTrack]) -> Void
    ) async throws {
        // keep 100 here for speed, or change to 20 if you prefer smaller batches
        var url = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=100"
        var delivered = false

        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(TrackPage.self, from: data)

            let batch: [PlaylistTrack] = page.items.compactMap { item in
                guard var tr = item.track else { return nil }
                if tr.uri == nil, let id = tr.id { tr.uri = "spotify:track:\(id)" }
                if let t = tr.type, t != "track" { return nil }
                var newItem = item
                newItem.track = tr
                return newItem
            }

            onPage(batch)
            delivered = true

            if let next = page.next, !next.isEmpty { url = next } else { break }
        }

        if !delivered { onPage([]) }
    }

    // MARK: - Liked Songs pager (20 per page)

    func resetSavedPager(limit: Int = 20) {
        savedNextURL = "https://api.spotify.com/v1/me/tracks?limit=\(limit)"
    }

    func fetchNextSavedPage(auth: AuthManager) async throws -> [PlaylistTrack] {
        guard let url = savedNextURL, !savedPagingInFlight else { return [] }
        savedPagingInFlight = true
        defer { savedPagingInFlight = false }

        guard let req = authorizedRequest(url, auth: auth) else { return [] }
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(TrackPage.self, from: data)

        let batch: [PlaylistTrack] = page.items.compactMap { item in
            guard var tr = item.track, let id = tr.id else { return nil }
            if tr.uri == nil { tr.uri = "spotify:track:\(id)" }
            if let t = tr.type, t != "track" { return nil }
            var newItem = item
            newItem.track = tr
            return newItem
        }

        savedNextURL = page.next // nil when no more
        return batch
    }

    // MARK: - Mutations

    func batchRemoveTracks(playlistID: String, uris: [String], auth: AuthManager) async throws {
        guard !uris.isEmpty else { return }
        let chunks = uris.chunked(into: 90) // under 100 per request
        for chunk in chunks {
            let body = ["tracks": chunk.map { ["uri": $0] }]
            let data = try JSONSerialization.data(withJSONObject: body)
            guard let req = authorizedRequest(
                "https://api.spotify.com/v1/playlists/\(playlistID)/tracks",
                auth: auth, method: "DELETE", body: data
            ) else { continue }
            _ = try await URLSession.shared.data(for: req)
        }
    }

    func batchUnsaveTracks(trackIDs: [String], auth: AuthManager) async throws {
        guard !trackIDs.isEmpty else { return }
        let chunks = trackIDs.chunked(into: 50)
        for chunk in chunks {
            let ids = chunk.joined(separator: ",")
            guard var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks") else { continue }
            comps.queryItems = [URLQueryItem(name: "ids", value: ids)]
            guard let url = comps.url,
                  var req = authorizedRequest(url.absoluteString, auth: auth, method: "DELETE")
            else { continue }
            // no JSON body for this endpoint
            req.setValue(nil, forHTTPHeaderField: "Content-Type")
            _ = try await URLSession.shared.data(for: req)
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
}
