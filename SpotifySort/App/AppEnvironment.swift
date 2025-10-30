import SwiftUI

/// Single composition root object you can inject once into the view tree.
/// Holds shared services / app singletons to avoid many EnvironmentObjects in views.
@MainActor
final class AppEnvironment: ObservableObject {
    let auth: AuthManager
    let api: SpotifyAPI
    let router: Router
    let previews: PreviewResolver
    let metadata: TrackMetadataService

    init(auth: AuthManager, api: SpotifyAPI, router: Router, previews: PreviewResolver, metadata: TrackMetadataService) {
        self.auth = auth
        self.api = api
        self.router = router
        self.previews = previews
        self.metadata = metadata
    }
}
