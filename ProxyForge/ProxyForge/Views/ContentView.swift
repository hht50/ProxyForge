import SwiftUI

// MARK: - 主视图（布局协调器）

/// 将 OptionsBarView、AppTableView、RulePreviewView 组合为最终窗口布局。
/// 所有状态通过 @EnvironmentObject 流动，本身不持有任何业务逻辑。
struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            OptionsBarView()
            Divider()
            SharedDomainsView()
            Divider()
            VSplitView {
                AppTableView()
                    .frame(minHeight: 200)
                RulePreviewView()
                    .frame(minHeight: 140)
            }
        }
        .toolbar { toolbarItems }
        .frame(minWidth: 980, minHeight: 660)
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

// MARK: - 工具栏子组件（访问 vm 需要 EnvironmentObject，单独声明以满足 ToolbarContent 协议）

private struct OpenFileButton: View {
    @EnvironmentObject private var vm: ContentViewModel
    var body: some View {
        Button { vm.openFilePicker() } label: {
            Label("打开文件", systemImage: "folder.badge.plus")
        }
        .help("打开 App_Privacy_Report_v4_*.ndjson")
    }
}

private struct RefreshButton: View {
    @EnvironmentObject private var vm: ContentViewModel
    var body: some View {
        Button { vm.loadFiles() } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .disabled(vm.fileURLs.isEmpty || vm.isLoading)
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
