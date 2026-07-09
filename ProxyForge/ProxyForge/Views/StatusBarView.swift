import SwiftUI

// MARK: - 底部状态栏

/// 窗口底部固定状态条，显示加载进度和操作结果。
struct StatusBarView: View {
    @EnvironmentObject private var vm: ContentViewModel

    var body: some View {
        HStack(spacing: 6) {
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }
            Text(vm.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
