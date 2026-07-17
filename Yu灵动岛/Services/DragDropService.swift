import AppKit
import UniformTypeIdentifiers

final class DragDropService: NSObject, NSDraggingDestination {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func setupDragDestination(for view: NSView) {
        view.registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            .string
        ])
    }
    
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        appState.isDragTarget = true
        return .copy
    }
    
    func draggingExited(_ sender: NSDraggingInfo?) {
        appState.isDragTarget = false
    }
    
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        appState.isDragTarget = false
        
        let pasteboard = sender.draggingPasteboard
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingContentsConformToTypes: [UTType.item.identifier]
            ]
        ) as? [URL] else {
            return false
        }
        
        for url in urls.prefix(AppConstants.maxFileItems - appState.fileItems.count) {
            let item = FileItem(url: url)
            appState.addFile(item)
        }
        
        return true
    }
    
    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
}
