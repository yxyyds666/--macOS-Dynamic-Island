import AppKit

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
    let fileSize: Int64
    let isDirectory: Bool
    let addedAt: Date
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = url.hasDirectoryPath
        
        let resourceValues = try? url.resourceValues(
            forKeys: [.fileSizeKey, .isDirectoryKey]
        )
        self.fileSize = resourceValues?.fileSize ?? 0
        self.isDirectory = resourceValues?.isDirectory ?? false
        self.addedAt = Date()
    }
    
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: fileSize,
            countStyle: .file
        )
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
}
