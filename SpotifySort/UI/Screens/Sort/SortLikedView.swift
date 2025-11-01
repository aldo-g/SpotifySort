import SwiftUI

struct SortLikedView: View {
    @EnvironmentObject var env: AppEnvironment
    
    var body: some View {
        // Assume AppEnvironment exposes the data provider now
        SortScreen(
            mode: .liked,
            env: env,
            dataProvider: env.dataProvider // <-- NEW: requires AppEnvironment change
        )
    }
}
