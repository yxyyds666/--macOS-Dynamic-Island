import AppKit
import SwiftUI

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    var notchFrame: NSRect? {
        guard hasNotch else { return nil }
        let screenFrame = frame
        let centerX = screenFrame.midX
        let notchX = centerX - AppConstants.notchWidth / 2
        let notchY = screenFrame.maxY - AppConstants.notchHeight
        return NSRect(
            x: notchX,
            y: notchY,
            width: AppConstants.notchWidth,
            height: AppConstants.notchHeight
        )
    }
}

extension NSView {
    func addSubviews(_ views: NSView...) {
        views.forEach { addSubview($0) }
    }
}
