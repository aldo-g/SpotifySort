import SwiftUI

struct SortLikedView: View {
    @EnvironmentObject var env: AppEnvironment
    
    var body: some View {
        SortScreen(
            mode: .liked,
            env: env
        )
    }
}
