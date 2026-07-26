import AppKit
import UniformTypeIdentifiers

/// Owns the drag-in logic and vends an `NSView` that actually receives the
/// dragging callbacks. Registering types on an `NSHostingView` isn't enough —
/// AppKit delivers `NSDraggingDestination` messages to the view itself, so we
/// need a concrete view that forwards them here.
@MainActor
final class DragDropService: NSObject {
    private let appState: AppState
    private let island: IslandState

    init(island: IslandState, appState: AppState) {
        self.island = island
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

    fileprivate func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
            return []
        }
        guard island.beginFileDrag() else { return [] }
        return .copy
    }

    fileprivate func draggingExited() {
        island.dragExitedNotch()
    }

    fileprivate func performDrop(_ sender: NSDraggingInfo) -> Bool {
        island.isDragTarget = false

        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else {
            appState.showFileDropFeedback("没有可添加的文件", isError: true)
            return false
        }

        let result = appState.addFiles(urls)
        island.expand()
        appState.currentModule = .file

        switch result {
        case .added, .partial: return true
        case .full, .disabled, .empty: return false
        }
    }
}

/// Concrete view that receives dragging callbacks and forwards them.
@MainActor
private final class DraggingView: NSView {
    weak var service: DragDropService?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        service?.draggingEntered(sender) ?? []
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
