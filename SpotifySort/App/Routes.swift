import SwiftUI

// MARK: - App routes

enum AppRoute: Hashable {
    case liked(provider: MusicProvider)
    case playlists(provider: MusicProvider)
}

enum MusicProvider: String, Hashable, CaseIterable {
    case spotify, appleMusic, youtubeMusic, deezer
    var displayName: String {
        switch self {
        case .spotify:     return "Spotify"
        case .appleMusic:  return "Apple Music"
        case .youtubeMusic:return "YouTube Music"
        case .deezer:      return "Deezer"
        }
    }
}
