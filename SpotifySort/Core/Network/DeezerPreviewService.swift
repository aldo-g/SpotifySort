import Foundation

/// Looks up 30s MP3 previews from Deezer for tracks where Spotify has no preview.
/// Validates cached URLs (HEAD) to avoid 403/404/hostname issues.
final class DeezerPreviewService {
    static let shared = DeezerPreviewService()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 8
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

    // MARK: - Public API

    /// Resolve a preview URL (validated) or re-query if needed.
    func resolvePreview(for track: Track) async -> String? {
        let key = makeKey(for: track)

        // In-memory
        if let cached = cache.object(forKey: key as NSString) as String?,
           let ok = await validateOrRefresh(urlString: cached, key: key, track: track) {
            return ok
        }

        // Persisted
        if let persistedURL = persisted[key],
           let ok = await validateOrRefresh(urlString: persistedURL, key: key, track: track) {
            cache.setObject(ok as NSString, forKey: key as NSString)
            return ok
        }

        // Fresh
        if let fresh = await freshLookup(for: track) {
            store(fresh, for: key)
            return fresh
        }
        return nil
    }

    /// Validate a (possibly stale) preview URL; refreshes if invalid.
    func validatePreview(urlString: String, trackKey: String, track: Track) async -> String? {
        await validateOrRefresh(urlString: urlString, key: trackKey, track: track)
    }

    // MARK: - Validation / Refresh

    private func validateOrRefresh(urlString: String, key: String, track: Track) async -> String? {
        // try exact URL
        if let u = URL(string: forceHTTPS(urlString)), await headOK(u) { return u.absoluteString }

        // try host swap
        if let alt = swappedHost(urlString), await headOK(alt) { return alt.absoluteString }

        // re-lookup
        remove(key)
        if let fresh = await freshLookup(for: track) {
            store(fresh, for: key)
            return fresh
        }
        return nil
    }

    /// HEAD request; returns true if 2xx. Any network/DNS error => false.
    private func headOK(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.setValue("bytes=0-", forHTTPHeaderField: "Range")
        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200...299).contains(http.statusCode) }
        } catch { /* DNS/timeouts => invalid */ }
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

    private func lookupByISRC(_ isrc: String) async -> String? {
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

    private struct DeezerTrack: Decodable { let preview: String? }
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
        } catch { return nil }
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

    // MARK: - Helpers

    private func forceHTTPS(_ u: String) -> String {
        if u.lowercased().hasPrefix("http://") { return "https://" + u.dropFirst("http://".count) }
        return u
    }

    private func swappedHost(_ urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString), let host = comps.host else { return nil }
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
        for p in patterns { if let r = t.range(of: p) { t = String(t[..<r.lowerBound]) } }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeArtist(_ s: String) -> String {
        var a = s.lowercased()
        if let r = a.range(of: "&") { a = String(a[..<r.lowerBound]) }
        if let r = a.range(of: ",") { a = String(a[..<r.lowerBound]) }
        return a.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeKey(for track: Track) -> String {
        track.id ?? track.uri ?? "\(track.name)|\(track.artists.first?.name ?? "")"
    }
}
