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

    static func detectNotch() -> NotchInfo? {
        guard let screen = builtInNotchScreen,
              let notchFrame = screen.notchFrame else {
            return nil
        }
        return NotchInfo(frame: notchFrame, screenFrame: screen.frame)
    }

    static func notchCenterX() -> CGFloat {
        builtInNotchScreen?.frame.midX ?? 0
    }

    /// The idle island size, using the target display's real notch dimensions.
    static func idleSize() -> CGSize {
        guard let screen = builtInNotchScreen else {
            return CGSize(width: AppConstants.notchWidth, height: AppConstants.notchHeight)
        }
        return CGSize(width: screen.notchWidth, height: screen.notchHeight)
    }

    /// A frame centered on the built-in notch and pinned to that screen's top.
    static func islandFrame(for size: CGSize) -> NSRect {
        guard let screen = builtInNotchScreen else { return .zero }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The largest window extent any island state can reach, based on the real
    /// notch width plus the expanded wings and shadow padding. The fixed-window
    /// architecture sizes the window to this once and never resizes it; every
    /// state change animates inside SwiftUI instead.
    static func fixedWindowSize() -> CGSize {
        let notch = idleSize()
        let width = notch.width + 2 * AppConstants.expandSidePanelWidth + 2 * AppConstants.islandShadowPadding
        let height = AppConstants.expandPanelHeight + AppConstants.islandShadowPadding
        return CGSize(width: width, height: height)
    }

    /// The fixed window frame: centered on the notch, top flush with the screen.
    static func fixedWindowFrame() -> NSRect {
        guard let screen = builtInNotchScreen else { return .zero }
        let size = fixedWindowSize()
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The fixed window frame for any screen (notched or not).
    static func fixedWindowFrame(for screen: NSScreen) -> NSRect {
        let notchW = screen.hasNotch ? screen.notchWidth  : AppConstants.notchWidth
        let notchH = screen.hasNotch ? screen.notchHeight : AppConstants.notchHeight
        let width  = notchW + 2 * AppConstants.expandSidePanelWidth + 2 * AppConstants.islandShadowPadding
        let height = AppConstants.expandPanelHeight + AppConstants.islandShadowPadding
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func expandPanelFrame() -> NSRect {
        guard let screen = builtInNotchScreen else { return .zero }
        let panelWidth = AppConstants.expandPanelWidth
        let panelHeight = AppConstants.expandPanelHeight
        let panelX = screen.frame.midX - panelWidth / 2
        let notchBottom = screen.frame.maxY - screen.notchHeight
        let panelY = notchBottom - panelHeight - 4
        return NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
    }
}

struct NotchInfo {
    let frame: NSRect
    let screenFrame: NSRect

    var centerX: CGFloat { frame.midX }
    var topY: CGFloat { frame.maxY }
    var bottomY: CGFloat { frame.minY }
}
