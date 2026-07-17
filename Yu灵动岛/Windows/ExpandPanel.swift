import AppKit
import SwiftUI

final class ExpandPanel: NSPanel {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        let panelFrame = NotchDetector.expandPanelFrame()
        
        super.init(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        setupPanel()
    }
    
    private func setupPanel() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        animationBehavior = .utilityWindow
        
        let contentView = ExpandPanelContent(appState: appState)
        self.contentView = NSHostingView(rootView: contentView)
    }
    
    func show() {
        guard let notchInfo = NotchDetector.detectNotch() else { return }
        
        // Animate from notch position
        let startFrame = NSRect(
            x: notchInfo.frame.origin.x,
            y: notchInfo.frame.origin.y,
            width: notchInfo.frame.width,
            height: notchInfo.frame.height
        )
        
        let endFrame = NotchDetector.expandPanelFrame()
        
        self.setFrame(startFrame, display: true)
        self.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppConstants.expandDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            self.setFrame(endFrame, display: true)
        }
    }
    
    func hide() {
        guard let notchInfo = NotchDetector.detectNotch() else {
            self.orderOut(nil)
            return
        }
        
        let endFrame = notchInfo.frame
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AppConstants.expandDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            self.setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}

struct ExpandPanelContent: View {
    @Bindable var appState: AppState
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: AppConstants.expandPanelCornerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppConstants.expandPanelCornerRadius)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
            
            // Module content
            Group {
                if appState.currentModule == .music && appState.showMusicModule {
                    MusicExpandedView(appState: appState)
                } else if appState.currentModule == .file && appState.showFileModule {
                    FileTransferExpandedView(appState: appState)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.expandPanelCornerRadius))
        }
        .frame(
            width: AppConstants.expandPanelWidth,
            height: AppConstants.expandPanelHeight
        )
        .onTapGesture {
            // Prevent click-through to close
        }
    }
}
