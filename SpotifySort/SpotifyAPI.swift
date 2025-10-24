import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {
    @Published var user: SpotifyUser?
    @Published var playlists: [Playlist] = []

    // ✅ Add this property so SwipeCard can store Deezer/Spotify preview URLs
    @Published var previewMap: [String: String] = [:]

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
            var copy = item
            copy.track = tr
            return copy
        }
        return (items, page.next)
    }

    // MARK: - Mutations

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
