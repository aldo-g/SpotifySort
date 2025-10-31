import Foundation

/// In-memory cache for track metadata with disk persistence.
/// Stores artist genres, track popularity, and preview URLs.
final class TrackMetadataCache {
    
    private var artistGenres: [String: [String]] = [:]
    private var trackPopularity: [String: Int] = [:]
    private var previewMap: [String: String] = [:]
    
    private let diskKey = "trackMetadataCache.v1"
    
    init() {
        load()
    }
    
    // MARK: - Artist Genres
    
    func getArtistGenres(id: String) -> [String]? {
        artistGenres[id]
    }
    
    func setArtistGenres(id: String, genres: [String]) {
        artistGenres[id] = genres
    }
    
    func setArtistGenresBatch(_ batch: [String: [String]]) {
        for (id, genres) in batch {
            artistGenres[id] = genres
        }
    }
    
    func hasArtistGenres(id: String) -> Bool {
        artistGenres[id] != nil
    }
    
    // MARK: - Track Popularity
    
    func getTrackPopularity(id: String) -> Int? {
        trackPopularity[id]
    }
    
    func setTrackPopularity(id: String, popularity: Int) {
        trackPopularity[id] = popularity
    }
    
    func setTrackPopularityBatch(_ batch: [String: Int]) {
        for (id, pop) in batch {
            trackPopularity[id] = pop
        }
    }
    
    func hasTrackPopularity(id: String) -> Bool {
        trackPopularity[id] != nil
    }
    
    // MARK: - Preview URLs
    
    func getPreviewURL(key: String) -> String? {
        previewMap[key]
    }
    
    func setPreviewURL(key: String, url: String) {
        previewMap[key] = url
    }
    
    func hasPreviewURL(key: String) -> Bool {
        previewMap[key] != nil
    }
    
    // MARK: - Persistence
    
    func save() {
        let data: [String: Any] = [
            "artistGenres": artistGenres,
            "trackPopularity": trackPopularity,
            "previewMap": previewMap
        ]
        UserDefaults.standard.set(data, forKey: diskKey)
    }
    
    private func load() {
        guard let data = UserDefaults.standard.dictionary(forKey: diskKey) else { return }
        
        if let genres = data["artistGenres"] as? [String: [String]] {
            artistGenres = genres
        }
        if let popularity = data["trackPopularity"] as? [String: Int] {
            trackPopularity = popularity
        }
        if let previews = data["previewMap"] as? [String: String] {
            previewMap = previews
        }
    }
    
    func clear() {
        artistGenres.removeAll()
        trackPopularity.removeAll()
        previewMap.removeAll()
        UserDefaults.standard.removeObject(forKey: diskKey)
    }
}
