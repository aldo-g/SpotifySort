import SwiftUI

struct SortView: View {
    @EnvironmentObject var router: Router
    let playlist: Playlist
    var body: some View { SortScreen(mode: .playlist(playlist)) }
}
