import UIKit

/// Tiny façade over UIKit haptics to avoid sprinkling in Views.
enum Haptics {
    static func tapLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func impactMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func selectionChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
