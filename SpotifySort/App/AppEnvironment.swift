import SwiftUI
import Combine

/// Single composition root object you can inject once into the view tree.
/// Holds shared services / app singletons to avoid many EnvironmentObjects in views.
@MainActor
final class AppEnvironment: ObservableObject {
    let auth: AuthManager
    let api: SpotifyAPI
    let router: Router
    let previews: PreviewResolver
    let metadata: TrackMetadataService
    
    private var cancellables = Set<AnyCancellable>()

    init(auth: AuthManager, api: SpotifyAPI, router: Router, previews: PreviewResolver, metadata: TrackMetadataService) {
        self.auth = auth
        self.api = api
        self.router = router
        self.previews = previews
        self.metadata = metadata
        
        // Forward objectWillChange from all children
        auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        api.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        router.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        previews.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        metadata.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
}
