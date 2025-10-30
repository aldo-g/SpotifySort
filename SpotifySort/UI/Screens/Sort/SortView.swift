import SwiftUI

struct SortView: View {
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var auth: AuthManager
    
    let playlist: Playlist
    
    var body: some View {
        SortScreen(
            mode: .playlist(playlist),
            api: api,
            auth: auth
        )
    }
}
