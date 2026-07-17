import AppKit
import SwiftUI

final class NotchWindow: NSWindow {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        guard let notchInfo = NotchDetector.detectNotch() else {
            fatalError("NotchWindow requires a MacBook Pro with notch")
        }
        
        super.init(
            contentRect: notchInfo.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
    }
    
    private func setupWindow() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        let contentView = NotchContentView(appState: appState)
        self.contentView = NSHostingView(rootView: contentView)
        
        makeKeyAndOrderFront(nil)
    }
}

struct NotchContentView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        ZStack {
            // Background blur
            RoundedRectangle(cornerRadius: AppConstants.notchCornerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppConstants.notchCornerRadius)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
            
            // Content based on current module
            if appState.currentModule == .music && appState.showMusicModule {
                MusicMiniView(appState: appState)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else if appState.currentModule == .file && appState.showFileModule {
                FileTransferMiniView(appState: appState)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .frame(width: AppConstants.notchWidth, height: AppConstants.notchHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.notchCornerRadius))
        .animation(.easeInOut(duration: AppConstants.moduleSwitchDuration), value: appState.currentModule)
        .onTapGesture {
            appState.isExpanded.toggle()
        }
        .onDrag {
            // Provide drag source for file items
            return NSItemProvider()
        }
    }
}
