import Foundation
import SwiftUI

extension LikedSongsService {
    /// Kick off the remaining prefetch work on a background task, and call `onComplete` on the main actor.
    @MainActor
    func prefetchRemainingInBackground(
        reviewedIDs: Set<String>,
        onComplete: @escaping @MainActor () -> Void
    ) {
        Task.detached { [weak self] in
            guard let self else { return }
            await self.backgroundFetchRemaining(reviewedIDs: reviewedIDs)
            await MainActor.run {
                onComplete()
            }
        }
    }
}
