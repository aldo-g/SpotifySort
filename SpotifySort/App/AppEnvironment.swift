import SwiftUI
import Combine

/// Single composition root object you can inject once into the view tree.
/// Holds shared services / app singletons to avoid many EnvironmentObjects in views.
@MainActor
final class AppEnvironment: ObservableObject {
    let auth: AuthManager
    let service: SpotifyService
    let router: Router
    let previews: PreviewResolver
    let dataProvider: any TrackDataProvider
    let history: HistoryCoordinator
    
    private var cancellables = Set<AnyCancellable>()

    init(
        auth: AuthManager,
        service: SpotifyService,
        router: Router,
        previews: PreviewResolver,
        dataProvider: any TrackDataProvider,
        history: HistoryCoordinator
    ) {
        self.auth = auth
        self.service = service
        self.router = router
        self.previews = previews
        self.dataProvider = dataProvider
        self.history = history
        
        auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        router.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        history.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
    }
}
