import AppKit
import SwiftUI

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// The physical notch width, measured as the gap between the two usable
    /// menu-bar areas that flank it. Falls back to the constant if unavailable.
    var notchWidth: CGFloat {
        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            let gap = right.minX - left.maxX
            if gap > 0 { return gap }
        }
        return AppConstants.notchWidth
    }

    /// The physical notch height (the top safe-area inset).
    var notchHeight: CGFloat {
        safeAreaInsets.top > 0 ? safeAreaInsets.top : AppConstants.notchHeight
    }

    var notchFrame: NSRect? {
        guard hasNotch else { return nil }
        let screenFrame = frame
        let w = notchWidth
        let h = notchHeight
        let notchX = screenFrame.midX - w / 2
        let notchY = screenFrame.maxY - h
        return NSRect(x: notchX, y: notchY, width: w, height: h)
    }
}
