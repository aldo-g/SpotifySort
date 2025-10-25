import Foundation

/// Looks up 30s MP3 previews from Deezer for tracks where Spotify has no preview.
final class DeezerPreviewService {
    static let shared = DeezerPreviewService()

    private let session = URLSession(configuration: {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 10
        return c
    }())

    private let cache = NSCache<NSString, NSString>()
    private let defaultsKey = "deezer.preview.cache" // id/uri -> previewURL
    private lazy var persisted: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }()

    /// Returns a preview URL string if found, else nil.
    func resolvePreview(for track: Track) async -> String? {
        // Key by Spotify track id if available, else URI, else name+artist.
        let key = track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"
        if let cached = cache.object(forKey: key as NSString) {
            return cached as String
        }
        if let persisted = persisted[key] {
            cache.setObject(persisted as NSString, forKey: key as NSString)
            return persisted
        }

        // 1) ISRC lookup (best match)
        if let isrc = track.isrc, let url = await lookupByISRC(isrc) {
            store(url, for: key)
            return url
        }

        // 2) Fallback: artist + title search
        let title = normalizeTitle(track.name)
        let artist = normalizeArtist(track.artists.first?.name ?? "")
        if let url = await lookupByArtistTitle(artist: artist, title: title) {
            store(url, for: key)
            return url
        }

        return nil
    }

    // MARK: - Private

    private func store(_ url: String, for key: String) {
        cache.setObject(url as NSString, forKey: key as NSString)
        persisted[key] = url
        UserDefaults.standard.set(persisted, forKey: defaultsKey)
    }

    private func lookupByISRC(_ isrc: String) async -> String? {
        // Deezer supports ISRC search; two variants generally work:
        //  a) /search?q=isrc:"CODE"
        //  b) /track/isrc:CODE
        // Try the direct track endpoint first, then fallback to search.
        if let u = URL(string: "https://api.deezer.com/track/isrc:\(isrc)") {
            if let url = await fetchPreview(from: u) { return url }
        }
        if let q = "isrc:\"\(isrc)\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let u = URL(string: "https://api.deezer.com/search/track?q=\(q)&limit=1") {
            if let url = await fetchPreview(from: u, expectsArray: true) { return url }
        }
        return nil
    }

    private func lookupByArtistTitle(artist: String, title: String) async -> String? {
        // Quote both to force exact terms; Deezer does token scoring.
        let query = "artist:\"\(artist)\" track:\"\(title)\""
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let u = URL(string: "https://api.deezer.com/search/track?q=\(q)&limit=3")
        else { return nil }

        // Try top 1–3; choose the first with a preview.
        return await fetchPreview(from: u, expectsArray: true)
    }

    private struct DeezerTrack: Decodable {
        let preview: String?
        let title: String?
        let duration: Int?
        let artist: DeezerArtist?
    }
    private struct DeezerArtist: Decodable { let name: String? }
    private struct SearchResp: Decodable { let data: [DeezerTrack] }

    private func fetchPreview(from url: URL, expectsArray: Bool = false) async -> String? {
        do {
            let (data, _) = try await session.data(from: url)
            if expectsArray {
                let resp = try JSONDecoder().decode(SearchResp.self, from: data)
                return resp.data.first(where: { $0.preview?.isEmpty == false })?.preview
            } else {
                // Single track object
                let t = try JSONDecoder().decode(DeezerTrack.self, from: data)
                return t.preview
            }
        } catch {
            print("Deezer fetch error: \(error)")
            return nil
        }
    }

    private func normalizeTitle(_ s: String) -> String {
        // Strip “(feat. …)”, “- Remaster …” etc. to improve match odds.
        var t = s.lowercased()
        let patterns = ["(feat.", "(with ", " - remaster", " - radio edit", " - single", " - explicit"]
        for p in patterns {
            if let r = t.range(of: p) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeArtist(_ s: String) -> String {
        var a = s.lowercased()
        if let r = a.range(of: "&") { a = String(a[..<r.lowerBound]) }
        if let r = a.range(of: ",") { a = String(a[..<r.lowerBound]) }
        return a.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
