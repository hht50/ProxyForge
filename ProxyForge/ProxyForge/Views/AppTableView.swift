import SwiftUI

// MARK: - 应用列表

/// 展示已解析的 AppEntry 列表，支持多选和列标题排序。
/// apps 由外部（AppSidebarView）传入，支持搜索过滤。
struct AppTableView: View {
    @EnvironmentObject private var vm: ContentViewModel
    let apps: [AppEntry]

    var body: some View {
        Table(apps, selection: $vm.selectedIDs, sortOrder: $vm.sortOrder) {

            TableColumn("应用名称", value: \.name) { app in
                HStack(spacing: 6) {
                    // 使用预计算的 Set（O(1) 查找），替代原来的双重 contains 遍历（O(n²)）
                    if vm.appsWithSharedDomains.contains(app.id) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                            .foregroundStyle(.tint)
                            .help("含共享域名")
                    }
                    Text(app.name).fontWeight(.medium)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("Bundle ID", value: \.bundleID) { app in
                Text(app.bundleID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(app.bundleID.hasPrefix("com.apple.") ? .tertiary : .secondary)
            }
            .width(min: 180, ideal: 240)

            TableColumn("域名", value: \.domainCount) { app in
                Text("\(app.domainCount)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(52)

            TableColumn("访问", value: \.totalHits) { app in
                Text("\(app.totalHits)")
                    .monospacedDigit()
                    .foregroundStyle(hitColor(app.totalHits))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(64)

            TableColumn("IP", value: \.ipCount) { app in
                Text(app.ipCount > 0 ? "\(app.ipCount)" : "—")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(app.ipCount > 0 ? Color.orange : Color.secondary)
            }
            .width(44)
        }
        .onChange(of: vm.selectedIDs) { _ in vm.refreshPreview() }
    }

    private func hitColor(_ hits: Int) -> Color {
        switch hits {
        case ..<100:  return .primary
        case ..<1000: return .orange
        default:      return .red
        }
    }
}
