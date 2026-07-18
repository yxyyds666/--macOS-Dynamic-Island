import AppKit

struct NotchDetector {
    static func detectNotch() -> NotchInfo? {
        guard let screen = NSScreen.main,
              screen.hasNotch,
              let notchFrame = screen.notchFrame else {
            return nil
        }
        return NotchInfo(
            frame: notchFrame,
            screenFrame: screen.frame
        )
    }
    
    static func notchCenterX() -> CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        return screen.frame.midX
    }

    /// The idle island size, using the screen's real notch dimensions so the
    /// collapsed pill matches the physical notch exactly.
    static func idleSize() -> CGSize {
        guard let screen = NSScreen.main else {
            return CGSize(width: AppConstants.notchWidth, height: AppConstants.notchHeight)
        }
        return CGSize(width: screen.notchWidth, height: screen.notchHeight)
    }
    
    /// A frame of `size` centered on the notch's X and pinned to the top of the
    /// screen — used to grow/shrink the island in place across its three states.
    static func islandFrame(for size: CGSize) -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    static func expandPanelFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let panelWidth = AppConstants.expandPanelWidth
        let panelHeight = AppConstants.expandPanelHeight
        let centerX = screen.frame.midX
        let panelX = centerX - panelWidth / 2
        let notchBottom = screen.frame.maxY - AppConstants.notchHeight
        let panelY = notchBottom - panelHeight - 4
        return NSRect(
            x: panelX,
            y: panelY,
            width: panelWidth,
            height: panelHeight
        )
    }
}

struct NotchInfo {
    let frame: NSRect
    let screenFrame: NSRect
    
    var centerX: CGFloat {
        frame.midX
    }
    
    var topY: CGFloat {
        frame.maxY
    }
    
    var bottomY: CGFloat {
        frame.minY
    }
}
