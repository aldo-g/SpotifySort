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
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }

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

    func loadTracks(playlistID: String, auth: AuthManager) async throws -> [PlaylistTrack] {
        var url = "https://api.spotify.com/v1/playlists/\(playlistID)/tracks?limit=100"
        var items: [PlaylistTrack] = []
        while true {
            guard let req = authorizedRequest(url, auth: auth) else { break }
            let (data, _) = try await URLSession.shared.data(for: req)
            let page = try JSONDecoder().decode(TrackPage.self, from: data)
            items.append(contentsOf: page.items.filter { $0.track?.uri != nil })
            if let next = page.next { url = next } else { break }
        }
        return items
    }

    func batchRemoveTracks(playlistID: String, uris: [String], auth: AuthManager) async throws {
        guard !uris.isEmpty else { return }
        let chunks = uris.chunked(into: 90)
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
