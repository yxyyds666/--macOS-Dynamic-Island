import SwiftUI

/// A shape that hugs the physical notch: its top edge is flush with the screen
/// top, the two top corners curve *inward* (concave) so it reads as growing out
/// of the notch/bezel, and the bottom corners are normally rounded. As the
/// island grows the same shape simply drapes further down — the iPhone Dynamic
/// Island "expand around the notch" feel.
struct NotchShape: Shape {
    /// Concave radius where the top edge meets the sides (the notch shoulders).
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
        let topR = min(topCornerRadius, w / 2, h / 2)
        let botR = min(bottomCornerRadius, w / 2, h / 2)

        var path = Path()

        // Start at the very top-left, flush with the screen edge.
        path.move(to: CGPoint(x: 0, y: 0))

        // Left shoulder: concave curve dishing inward and down.
        path.addQuadCurve(
            to: CGPoint(x: topR, y: topR),
            control: CGPoint(x: topR, y: 0)
        )

        // Left side straight down.
        path.addLine(to: CGPoint(x: topR, y: h - botR))

        // Bottom-left convex corner.
        path.addQuadCurve(
            to: CGPoint(x: topR + botR, y: h),
            control: CGPoint(x: topR, y: h)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: w - topR - botR, y: h))

        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: w - topR, y: h - botR),
            control: CGPoint(x: w - topR, y: h)
        )

        // Right side straight up.
        path.addLine(to: CGPoint(x: w - topR, y: topR))

        // Right shoulder: concave curve back up to the top edge.
        path.addQuadCurve(
            to: CGPoint(x: w, y: 0),
            control: CGPoint(x: w - topR, y: 0)
        )

        path.closeSubpath()
        return path
    }
}

/// The expanded-state bar that wraps AROUND the physical notch: a wide panel
/// whose top edge is flush with the screen, with a notch-shaped cutout punched
/// out of the top-middle so the real notch shows through. Content lives in the
/// two "wings" to the left and right of the cutout.
struct ExpandedNotchShape: Shape {
    /// Width of the notch cutout (matches the physical notch).
    var notchCutoutWidth: CGFloat
    /// Height/depth of the notch cutout.
    var notchCutoutHeight: CGFloat
    /// Radius of the shoulder curve where the flush top meets the cutout walls.
    var shoulderRadius: CGFloat = AppConstants.notchCutoutCornerRadius
    /// Radius of the cutout's two inner bottom corners.
    var innerRadius: CGFloat = AppConstants.notchCutoutCornerRadius
    /// Radius of the bar's two bottom corners.
    var bottomCornerRadius: CGFloat = AppConstants.expandPanelCornerRadius

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let nW = min(notchCutoutWidth, w - 2 * shoulderRadius)
        let nH = min(notchCutoutHeight, h / 2)
        let L = cx - nW / 2
        let R = cx + nW / 2
        let sR = min(shoulderRadius, (w - nW) / 2, nH)
        let iR = min(innerRadius, nW / 2, nH)
        let botR = min(bottomCornerRadius, w / 2, h / 2)

        var path = Path()

        // Top-left outer corner, flush with the screen edge.
        path.move(to: CGPoint(x: 0, y: 0))
        // Top edge of the left wing, up to the cutout's left shoulder.
        path.addLine(to: CGPoint(x: L - sR, y: 0))
        // Left shoulder curving down into the cutout.
        path.addQuadCurve(to: CGPoint(x: L, y: sR), control: CGPoint(x: L, y: 0))
        // Left wall of the cutout.
        path.addLine(to: CGPoint(x: L, y: nH - iR))
        // Inner bottom-left corner of the cutout.
        path.addQuadCurve(to: CGPoint(x: L + iR, y: nH), control: CGPoint(x: L, y: nH))
        // Floor of the cutout.
        path.addLine(to: CGPoint(x: R - iR, y: nH))
        // Inner bottom-right corner of the cutout.
        path.addQuadCurve(to: CGPoint(x: R, y: nH - iR), control: CGPoint(x: R, y: nH))
        // Right wall of the cutout.
        path.addLine(to: CGPoint(x: R, y: sR))
        // Right shoulder curving back up to the flush top.
        path.addQuadCurve(to: CGPoint(x: R + sR, y: 0), control: CGPoint(x: R, y: 0))
        // Top edge of the right wing.
        path.addLine(to: CGPoint(x: w, y: 0))
        // Right side down.
        path.addLine(to: CGPoint(x: w, y: h - botR))
        // Bottom-right corner.
        path.addQuadCurve(to: CGPoint(x: w - botR, y: h), control: CGPoint(x: w, y: h))
        // Bottom edge.
        path.addLine(to: CGPoint(x: botR, y: h))
        // Bottom-left corner.
        path.addQuadCurve(to: CGPoint(x: 0, y: h - botR), control: CGPoint(x: 0, y: h))

        path.closeSubpath()
        return path
    }
}
