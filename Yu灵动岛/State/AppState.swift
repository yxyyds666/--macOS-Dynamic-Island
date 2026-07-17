import Foundation
import Combine
import SwiftUI

@Observable
final class AppState {
    // Current active module
    var currentModule: NotchModule = .music
    
    // Expand panel state
    var isExpanded: Bool = false
    
    // Music state
    var isPlaying: Bool = false
    var songTitle: String = ""
    var artistName: String = ""
    var albumArt: NSImage? = nil
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.5
    var lyrics: [String] = []
    var currentLyricIndex: Int = -1
    
    // File transfer state
    var fileItems: [FileItem] = []
    
    // Settings
    var showMusicModule: Bool = true
    var showFileModule: Bool = true
    
    // Drag state
    var isDragTarget: Bool = false
    
    init() {
        loadSettings()
    }
    
    var hasMediaPlaying: Bool {
        !songTitle.isEmpty
    }
    
    var hasFiles: Bool {
        !fileItems.isEmpty
    }
    
    var canAddFile: Bool {
        fileItems.count < AppConstants.maxFileItems
    }
    
    func nextModule() {
        let modules = availableModules
        guard let currentIndex = modules.firstIndex(of: currentModule) else { return }
        let nextIndex = (currentIndex + 1) % modules.count
        currentModule = modules[nextIndex]
    }
    
    var availableModules: [NotchModule] {
        var modules: [NotchModule] = []
        if showMusicModule { modules.append(.music) }
        if showFileModule { modules.append(.file) }
        return modules.isEmpty ? [.music] : modules
    }
    
    func addFile(_ item: FileItem) {
        guard canAddFile else { return }
        fileItems.append(item)
    }
    
    func removeFile(at index: Int) {
        guard fileItems.indices.contains(index) else { return }
        fileItems.remove(at: index)
    }
    
    func clearAllFiles() {
        fileItems.removeAll()
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        showMusicModule = defaults.object(forKey: AppConstants.DefaultsKeys.showMusicModule) as? Bool ?? true
        showFileModule = defaults.object(forKey: AppConstants.DefaultsKeys.showFileModule) as? Bool ?? true
    }
}
