import Foundation

/// Looks up 30s MP3 previews from Deezer for tracks where Spotify has no preview.
/// Now validates cached URLs (HEAD) to avoid 403s from expired signed links.
final class DeezerPreviewService {
    static let shared = DeezerPreviewService()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 8
        // Present like Mobile Safari and hint we want audio
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
            "Accept": "audio/mpeg, audio/*;q=0.9, */*;q=0.5",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://www.deezer.com/"
        ]
        return URLSession(configuration: cfg)
    }()

    private let cache = NSCache<NSString, NSString>()
    private let defaultsKey = "deezer.preview.cache" // id/uri -> previewURL
    private lazy var persisted: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }()

    /// Returns a preview URL string if found (and **validated**), else nil.
    func resolvePreview(for track: Track) async -> String? {
        // Key by Spotify track id if available, else URI, else name+artist.
        let key = track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"

        // 0) Check in-memory cache first (but validate before trusting)
        if let cached = cache.object(forKey: key as NSString) as String?,
           let validated = await validateOrRefresh(urlString: cached, key: key, track: track) {
            return validated
        }

        // 1) Check persisted cache (validate before trusting)
        if let persistedURL = persisted[key],
           let validated = await validateOrRefresh(urlString: persistedURL, key: key, track: track) {
            cache.setObject(validated as NSString, forKey: key as NSString)
            return validated
        }

        // 2) Fresh lookup path (ISRC best match, then artist+title)
        if let fresh = await freshLookup(for: track) {
            store(fresh, for: key)
            return fresh
        }

        return nil
    }

    // MARK: - Validation / Refresh

    /// Validate a Deezer preview URL with HEAD; if invalid, try host variant & finally re-query API.
    private func validateOrRefresh(urlString: String, key: String, track: Track) async -> String? {
        // First enforce HTTPS and try the exact URL
        if let u = URL(string: forceHTTPS(urlString)) {
            if await headOK(u) { return u.absoluteString }
        }

        // Try host variant swap (cdnt-preview <-> cdns-preview)
        if let alt = swappedHost(urlString) {
            if await headOK(alt) {
                return alt.absoluteString
            }
        }

        // If either failed (403/404), it’s likely expired — remove and re-lookup.
        remove(key)
        if let fresh = await freshLookup(for: track) {
            store(fresh, for: key)
            return fresh
        }
        return nil
    }

    /// HEAD request; returns true if 2xx
    private func headOK(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        // Some Deezer edges prefer ranged requests even for HEAD
        req.setValue("bytes=0-", forHTTPHeaderField: "Range")
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                // 200/206 are fine; 204 is unusual but accept 2xx broadly
                return (200...299).contains(http.statusCode)
            }
        } catch {
            // Network error, treat as not OK
        }
        return false
    }

    // MARK: - Fresh lookup against Deezer API

    private func freshLookup(for track: Track) async -> String? {
        // ISRC first
        if let isrc = track.isrc, let url = await lookupByISRC(isrc) {
            return forceHTTPS(url)
        }
        // Artist + Title fallback
        let title = normalizeTitle(track.name)
        let artist = normalizeArtist(track.artists.first?.name ?? "")
        if let url = await lookupByArtistTitle(artist: artist, title: title) {
            return forceHTTPS(url)
        }
        return nil
    }

    // MARK: - Storage

    private func store(_ url: String, for key: String) {
        cache.setObject(url as NSString, forKey: key as NSString)
        persisted[key] = url
        UserDefaults.standard.set(persisted, forKey: defaultsKey)
    }

    private func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
        persisted.removeValue(forKey: key)
        UserDefaults.standard.set(persisted, forKey: defaultsKey)
    }

    // MARK: - Deezer API lookups

    private func lookupByISRC(_ isrc: String) async -> String? {
        // Try the direct track endpoint first, then fallback to search.
        if let u = URL(string: "https://api.deezer.com/track/isrc:\(isrc)"),
           let url = await fetchPreview(from: u) { return url }

        if let q = "isrc:\"\(isrc)\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let u = URL(string: "https://api.deezer.com/search/track?q=\(q)&limit=1"),
           let url = await fetchPreview(from: u, expectsArray: true) { return url }

        return nil
    }

    private func lookupByArtistTitle(artist: String, title: String) async -> String? {
        let query = "artist:\"\(artist)\" track:\"\(title)\""
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let u = URL(string: "https://api.deezer.com/search/track?q=\(q)&limit=3")
        else { return nil }
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
                let t = try JSONDecoder().decode(DeezerTrack.self, from: data)
                return t.preview
            }
        } catch {
            print("Deezer fetch error:", error)
            return nil
        }
    }

    // MARK: - Helpers

    private func forceHTTPS(_ u: String) -> String {
        if u.lowercased().hasPrefix("http://") {
            return "https://" + u.dropFirst("http://".count)
        }
        return u
    }

    private func swappedHost(_ urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString), let host = comps.host else { return nil }
        // Common Deezer variants observed in the wild: cdnt-preview, cdns-preview, cdn-preview
        if host.contains("cdnt-preview.") {
            comps.host = host.replacingOccurrences(of: "cdnt-preview.", with: "cdns-preview.")
        } else if host.contains("cdns-preview.") {
            comps.host = host.replacingOccurrences(of: "cdns-preview.", with: "cdnt-preview.")
        } else if host.contains("cdn-preview.") {
            comps.host = host.replacingOccurrences(of: "cdn-preview.", with: "cdns-preview.")
        }
        return comps.url
    }

    private func normalizeTitle(_ s: String) -> String {
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
