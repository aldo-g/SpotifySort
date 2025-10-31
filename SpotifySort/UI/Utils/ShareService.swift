import Foundation
import UIKit

/// Centralized sharing actions to keep UIKit out of SwiftUI Views.
enum ShareService {
    static func share(track: Track) {
        var items: [Any] = []
        if let id = track.id, let url = URL(string: "https://open.spotify.com/track/\(id)") {
            items = [url]
        } else {
            items = [track.name]
        }
        presentShare(items: items)
    }

    static func presentShare(items: [Any]) {
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
