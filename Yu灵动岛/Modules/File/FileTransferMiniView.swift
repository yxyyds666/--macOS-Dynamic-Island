import SwiftUI

struct FileTransferMiniView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
            
            if appState.hasFiles {
                Text("\(appState.fileItems.count) 个文件")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Text("拖拽文件到此处")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: AppConstants.notchHeight)
        .background(
            appState.isDragTarget
                ? RoundedRectangle(cornerRadius: AppConstants.notchCornerRadius)
                    .fill(.blue.opacity(0.3))
                : nil
        )
        .animation(.easeInOut(duration: 0.15), value: appState.isDragTarget)
    }
}
