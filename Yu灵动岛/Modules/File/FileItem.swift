import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let icon: NSImage
    let name: String
    let size: Int64
    
    var formattedSize: String {
        if isDirectory { return "文件夹" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.size = Int64(resourceValues?.fileSize ?? 0)
    }
}
