import SwiftUI

// MARK: - 主视图（布局协调器）

/// HSplitView 布局：左侧 AppSidebarView，右侧 RulePreviewView。
/// 底部固定 StatusBarView 显示状态文字和加载指示器。
struct ContentView: View {
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
            Divider()
            StatusBarView()
        }
        .toolbar { toolbarItems }
        .frame(minWidth: 920, minHeight: 560)
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
        .help("打开 App_Privacy_Report_v4_*.ndjson（可多选合并）")
    }
}

private struct RefreshButton: View {
    @EnvironmentObject private var vm: ContentViewModel
    var body: some View {
        Button { vm.loadFiles() } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .disabled(vm.fileURLs.isEmpty || vm.isLoading)
        .help("重新解析已加载的文件")
    }
}

private struct AboutButton: View {
    var body: some View {
        Button { showAbout() } label: {
            Label("关于", systemImage: "info.circle")
        }
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText     = "ProxyForge"
        alert.informativeText = """
            基于 iOS App 隐私报告 (App Privacy Report)
            分析网络访问记录，生成 Loon / Surge / Quantumult X / Clash 分流规则

            数据来源：iPhone → 设置 → 隐私与安全性 → App 隐私报告
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

#Preview {
    let settings = UserSettings()
    ContentView()
        .environmentObject(settings)
        .environmentObject(ContentViewModel(settings: settings))
}
