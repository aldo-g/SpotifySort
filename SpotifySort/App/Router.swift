import SwiftUI

@MainActor
final class Router: ObservableObject {
    enum Selection: Equatable {
        case liked
        case playlist(id: String)
    }

    @Published var selection: Selection = .liked

    func selectLiked() { selection = .liked }
    func selectPlaylist(_ id: String) { selection = .playlist(id: id) }
}
