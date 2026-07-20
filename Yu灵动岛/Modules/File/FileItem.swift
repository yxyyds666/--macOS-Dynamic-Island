import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable {
    let id = UUID()
    private let originalURL: URL
    private let bookmarkData: Data?
    let icon: NSImage
    let name: String
    let size: Int64
    let isDirectory: Bool

    /// Resolving a bookmark lets the item follow renames and moves on the same volume.
    var url: URL {
        guard let bookmarkData else { return originalURL }
        var stale = false
        return (try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )) ?? originalURL
    }

    var formattedSize: String {
        if isDirectory { return "文件夹" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    init?(url: URL) {
        guard url.isFileURL, (try? url.checkResourceIsReachable()) == true else { return nil }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .localizedNameKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isDirectory != nil else { return nil }

        self.originalURL = url
        self.bookmarkData = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: keys,
            relativeTo: nil
        )
        self.name = values.localizedName ?? (url.path == "/" ? "/" : url.lastPathComponent)
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.size = Int64(values.fileSize ?? 0)
        self.isDirectory = values.isDirectory == true
    }
}
