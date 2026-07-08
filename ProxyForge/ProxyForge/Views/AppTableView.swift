import SwiftUI

// MARK: - 应用列表

/// 展示已解析的 AppEntry 列表，支持多选和列标题排序。
struct AppTableView: View {
    @EnvironmentObject private var vm: ContentViewModel

    var body: some View {
        Table(vm.sortedApps, selection: $vm.selectedIDs, sortOrder: $vm.sortOrder) {

            TableColumn("Bundle ID", value: \.bundleID) { app in
                Text(app.bundleID)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(app.bundleID.hasPrefix("com.apple.") ? .secondary : .primary)
            }
            .width(min: 220, ideal: 290)

            TableColumn("应用名称", value: \.name) { app in
                Text(app.name).fontWeight(.medium)
            }
            .width(min: 100, ideal: 150)

            TableColumn("域名数", value: \.domainCount) { app in
                Text("\(app.domainCount)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(70)

            TableColumn("访问次数", value: \.totalHits) { app in
                Text("\(app.totalHits)")
                    .monospacedDigit()
                    .foregroundStyle(hitColor(app.totalHits))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)

            TableColumn("IP 数", value: \.ipCount) { app in
                Text(app.ipCount > 0 ? "\(app.ipCount)" : "—")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(app.ipCount > 0 ? Color.orange : .secondary)
            }
            .width(60)
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
