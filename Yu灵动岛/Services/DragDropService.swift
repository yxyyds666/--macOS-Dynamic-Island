import AppKit
import UniformTypeIdentifiers

/// Owns the drag-in logic and vends an `NSView` that actually receives the
/// dragging callbacks. Registering types on an `NSHostingView` isn't enough —
/// AppKit delivers `NSDraggingDestination` messages to the view itself, so we
/// need a concrete view that forwards them here.
final class DragDropService: NSObject {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Creates the overlay view to drop into the notch window's content view.
    func makeDraggingView() -> NSView {
        let view = DraggingView()
        view.service = self
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    // MARK: - Drop handling

    fileprivate func draggingEntered() -> NSDragOperation {
        appState.isDragTarget = true
        // Pop the island open so the file transfer panel is ready to receive.
        appState.dragEnteredNotch()
        return .copy
    }

    fileprivate func draggingExited() {
        appState.isDragTarget = false
        // Drag left without dropping — snap back to idle.
        appState.dragExitedNotch()
    }

    fileprivate func performDrop(_ sender: NSDraggingInfo) -> Bool {
        appState.isDragTarget = false

        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else {
            // Nothing usable dropped — snap back to idle.
            appState.dragExitedNotch()
            return false
        }

        let remaining = AppConstants.maxFileItems - appState.fileItems.count
        for url in urls.prefix(remaining) {
            appState.addFile(FileItem(url: url))
        }
        // Auto-switch to the file module so the user sees the result.
        if appState.showFileModule {
            appState.currentModule = .file
        }
        // Stay expanded after the drop; the next mouse-exit collapses it.
        return true
    }
}

/// Concrete view that receives dragging callbacks and forwards them.
private final class DraggingView: NSView {
    weak var service: DragDropService?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        service?.draggingEntered() ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        service?.draggingExited()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        service?.performDrop(sender) ?? false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    /// Let mouse clicks fall through to the SwiftUI content underneath. Drag
    /// destinations are resolved by AppKit independently of `hitTest`, so drops
    /// still land here while taps reach the buttons and tap-to-expand gesture.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
