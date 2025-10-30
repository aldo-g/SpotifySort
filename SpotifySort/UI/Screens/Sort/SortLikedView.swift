import SwiftUI

struct SortLikedView: View {
    @EnvironmentObject var api: SpotifyAPI
    @EnvironmentObject var auth: AuthManager
    
    var body: some View {
        SortScreen(
            mode: .liked,
            api: api,
            auth: auth
        )
    }
}
