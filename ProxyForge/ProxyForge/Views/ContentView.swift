import SwiftUI
import UniformTypeIdentifiers

// MARK: - 主视图（布局协调器）

/// HSplitView 布局：左侧 AppSidebarView，右侧 RulePreviewView。
/// 底部固定 StatusBarView 显示状态文字和加载指示器。
/// 支持从 Finder 拖入 .ndjson 文件。
struct ContentView: View {
    @EnvironmentObject private var vm: ContentViewModel

    /// 拖放悬停时高亮边框
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            OptionsBarView()
            Divider()
            HSplitView {
                AppSidebarView()
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: 520)
                RulePreviewView()
                    .frame(minWidth: 420)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers: providers)
            }
            .overlay(alignment: .center) {
                if isDragTargeted { dropHighlight }
            }
            Divider()
            StatusBarView()
        }
        .toolbar { toolbarItems }
        .frame(minWidth: 920, minHeight: 560)
    }

    // ── 拖放处理 ─────────────────────────────────────────────────────────────

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            vm.loadDroppedFiles(urls)
        }
        return true
    }

    // ── 拖放悬停高亮 ──────────────────────────────────────────────────────────

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.04).clipShape(RoundedRectangle(cornerRadius: 10)))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                    Text("拖入 .ndjson 文件")
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .allowsHitTesting(false)
    }

    // ── 工具栏 ────────────────────────────────────────────────────────────────

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            OpenFileButton()
        }
        ToolbarItem {
            RefreshButton()
        }
        ToolbarItem {
            AboutButton()
        }
    }
}

// MARK: - 工具栏子组件

private struct OpenFileButton: View {
    @EnvironmentObject private var vm: ContentViewModel
    var body: some View {
        Button { vm.openFilePicker() } label: {
            Label("打开文件", systemImage: "folder.badge.plus")
        }
        .help("打开 App_Privacy_Report_v4_*.ndjson（可多选合并）⌘O")
        .keyboardShortcut("o")
    }
}

private struct RefreshButton: View {
    @EnvironmentObject private var vm: ContentViewModel
    var body: some View {
        Button { vm.loadFiles() } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .disabled(vm.fileURLs.isEmpty || vm.isLoading)
        .help("重新解析已加载的文件 ⌘R")
        .keyboardShortcut("r")
    }
}

private struct AboutButton: View {
    var body: some View {
        Button { NSApp.orderFrontStandardAboutPanel(nil) } label: {
            Label("关于", systemImage: "info.circle")
        }
    }
}

#Preview {
    let settings = UserSettings()
    ContentView()
        .environmentObject(settings)
        .environmentObject(ContentViewModel(settings: settings))
}
