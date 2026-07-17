import SwiftUI

struct FileTransferExpandedView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text("文件中转站")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(appState.fileItems.count)/\(AppConstants.maxFileItems)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Divider()
                .background(.white.opacity(0.2))
            
            if appState.fileItems.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("从 Finder 或其他 App 拖拽文件到此处")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // File list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(appState.fileItems.enumerated()), id: \.element.id) { index, item in
                            FileRow(item: item)
                                .onTapGesture {
                                    // Drag from here
                                }
                        }
                    }
                }
                
                // Action buttons
                HStack {
                    Button("全部清除") {
                        appState.clearAllFiles()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
                    
                    Spacer()
                    
                    Button("全部导出") {
                        // Export to Finder
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
    }
}

struct FileRow: View {
    let item: FileItem
    
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(item.formattedSize)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.08))
        )
    }
}
