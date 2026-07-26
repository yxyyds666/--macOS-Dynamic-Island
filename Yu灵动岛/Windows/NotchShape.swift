import SwiftUI

/// A shape that fully covers the physical notch: the whole top edge is flush
/// with the screen and spans the full width with SQUARE top corners, so there is
/// no scoop beside the notch — the black panel sits solidly over the notch and
/// the bezel around it. Only the bottom corners are rounded. As the island grows
/// the same shape simply drapes further down.
///
/// `topCornerRadius` is kept for API/animation compatibility but no longer insets
/// the top edge; the top stays square so nothing shows through beside the notch.
struct NotchShape: Shape {
    /// Retained for compatibility; the top edge is square so this is unused.
    var topCornerRadius: CGFloat
    /// Convex radius of the two bottom corners.
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let botR = min(bottomCornerRadius, w / 2, h / 2)

        var path = Path()

        // Full-width flush top with square corners — covers the notch and the
        // bezel beside it, no gap.
        path.move(to: CGPoint(x: 0, y: 0))

        // Left side straight down.
        path.addLine(to: CGPoint(x: 0, y: h - botR))

        // Bottom-left convex corner.
        path.addQuadCurve(
            to: CGPoint(x: botR, y: h),
            control: CGPoint(x: 0, y: h)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: w - botR, y: h))

        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: w, y: h - botR),
            control: CGPoint(x: w, y: h)
        )

        // Right side straight up to the flush top.
        path.addLine(to: CGPoint(x: w, y: 0))

        path.closeSubpath()
        return path
    }
}
