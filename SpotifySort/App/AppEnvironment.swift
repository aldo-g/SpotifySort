import SwiftUI
import Combine

/// Single composition root object you can inject once into the view tree.
/// Holds shared services / app singletons to avoid many EnvironmentObjects in views.
@MainActor
final class AppEnvironment: ObservableObject {
    let auth: AuthManager
    let service: SpotifyService  // ← Changed from 'api'
    let router: Router
    let previews: PreviewResolver
    let metadata: TrackMetadataService
    
    private var cancellables = Set<AnyCancellable>()

    init(
        auth: AuthManager,
        service: SpotifyService,  // ← Changed from 'api'
        router: Router,
        previews: PreviewResolver,
        metadata: TrackMetadataService
    ) {
        self.auth = auth
        self.service = service
        self.router = router
        self.previews = previews
        self.metadata = metadata
        
        // Forward objectWillChange from all children
        auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        service.objectWillChange.sink { [weak self] _ in
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
