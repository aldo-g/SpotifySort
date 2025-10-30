import SwiftUI

/// Centralized math for swipe gestures, tilt/lift visuals, and edge-glow mapping.
enum SwipeDynamics {
    /// Horizontal distance needed to commit a swipe.
    static let swipeThreshold: CGFloat = 120

    /// Card tilt (in degrees) from horizontal drag.
    static func tilt(forDragX x: CGFloat) -> Double {
        Double(x) / 22
    }

    /// Card "lift"/shadow radius from horizontal drag.
    static func lift(forDragX x: CGFloat) -> CGFloat {
        8 + min(18, abs(x) / 12)
    }

    /// Map drag to edge glow intensities (0...1) for left/right.
    /// Left glow for negative x, right glow for positive x.
    static func edgeIntensities(forDragX x: CGFloat) -> (left: CGFloat, right: CGFloat) {
        guard x != 0 else { return (0, 0) }
        let c = min(1, abs(x) / 180)
        return x < 0 ? (c, 0) : (0, c)
    }
}
