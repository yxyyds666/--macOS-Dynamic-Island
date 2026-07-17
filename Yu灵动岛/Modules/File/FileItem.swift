import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let icon: NSImage
    let name: String
    let size: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        let icon = NSWorkspace.shared.icon(forFileType: url.pathExtension)
        self.icon = icon
        
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.size = Int64(resourceValues?.fileSize ?? 0)
    }
}
