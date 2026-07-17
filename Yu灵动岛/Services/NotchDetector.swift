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
