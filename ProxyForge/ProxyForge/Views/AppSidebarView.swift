import SwiftUI

// MARK: - 应用侧边栏

/// 左侧面板:搜索框 + 选中统计 + 应用列表(AppTableView)。
/// 封装搜索/过滤逻辑,将过滤结果向下传给 AppTableView。
struct AppSidebarView: View {
    @EnvironmentObject private var vm:       ContentViewModel
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var debounceTask: Task<Void, Never>?

    // ── 计算属性 ──────────────────────────────────────────────────────────────

    private var filteredApps: [AppEntry] {
        guard !debouncedSearch.isEmpty else { return vm.sortedApps }
        let q = debouncedSearch.lowercased()
        return vm.sortedApps.filter {
            $0.name.lowercased().contains(q) ||
            $0.bundleID.lowercased().contains(q)
        }
    }

    private var allFiltered: Bool {
        !filteredApps.isEmpty &&
        filteredApps.allSatisfy { vm.selectedIDs.contains($0.id) }
    }

    private var selectionLabel: String {
        let sel   = vm.selectedIDs.count
        let total = filteredApps.count
        if sel == 0 { return "共 \(total) 个应用" }
        return "已选 \(sel) / \(total)"
    }

    // ── 视图 ──────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if !vm.apps.isEmpty {
                selectionBar
                Divider()
            }
            AppTableView(apps: filteredApps)
        }
        .onChange(of: searchText) { newValue in
            // 防抖:300ms 后才触发搜索
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearch = newValue
            }
        }
    }

    // ── 搜索框 ────────────────────────────────────────────────────────────────

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            TextField("搜索应用名称或 Bundle ID…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debouncedSearch = ""
                    debounceTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // ── 选中统计 + 全选 ───────────────────────────────────────────────────────

    private var selectionBar: some View {
        HStack(spacing: 4) {
            Text(selectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button(allFiltered ? "取消全选" : "全选") {
                if allFiltered {
                    vm.selectedIDs = []
                } else {
                    vm.selectedIDs = Set(filteredApps.map(\.id))
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
