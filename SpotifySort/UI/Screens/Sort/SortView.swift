import SwiftUI

struct SortView: View {
    @EnvironmentObject var env: AppEnvironment
    let playlist: Playlist
    
    var body: some View {
        SortScreen(
            mode: .playlist(playlist),
            env: env
        )
    }
}
