import SwiftUI

struct SortView: View {
    @EnvironmentObject var env: AppEnvironment
    let playlist: Playlist
    
    var body: some View {
        // Assume AppEnvironment exposes the data provider now
        SortScreen(
            mode: .playlist(playlist),
            env: env,
            dataProvider: env.dataProvider // <-- NEW: requires AppEnvironment change
        )
    }
}
