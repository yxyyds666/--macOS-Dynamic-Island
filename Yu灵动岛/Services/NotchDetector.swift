import AppKit
import CoreGraphics

struct NotchDetector {
    /// The physical built-in display with a notch. External displays are never
    /// valid island targets, even if their safe-area metadata is unusual.
    static var builtInNotchScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard screen.hasNotch else { return false }
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return true
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
    }

    /// The fixed window frame for any screen (notched or not): sized once to the
    /// largest extent any island state can reach (notch + expanded wings + shadow
    /// padding), centered on the notch, top flush with the screen. The window
    /// never resizes; every state change animates inside SwiftUI.
    static func fixedWindowFrame(for screen: NSScreen) -> NSRect {
        let notchW = screen.hasNotch ? screen.notchWidth  : AppConstants.notchWidth
        let notchH = screen.hasNotch ? screen.notchHeight : AppConstants.notchHeight
        let width  = notchW + 2 * AppConstants.expandSidePanelWidth + 2 * AppConstants.islandShadowPadding
        let height = AppConstants.expandPanelHeight + AppConstants.islandShadowPadding
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
