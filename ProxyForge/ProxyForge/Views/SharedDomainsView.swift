import SwiftUI

// MARK: - 共享域名面板

/// 被 ≥2 个 App 共同访问的域名，折叠式面板，显示在应用列表上方。
struct SharedDomainsView: View {
    @EnvironmentObject private var vm:       ContentViewModel
    @EnvironmentObject private var settings: UserSettings
    @State private var isExpanded = true
    @State private var sortOrder: [KeyPathComparator<SharedRow>] = [
        KeyPathComparator(\.appCount, order: .reverse)
    ]

    // ── 派生数据 ──────────────────────────────────────────────────────────────

    private var rows: [SharedRow] {
        vm.sharedDomainApps
            .map { domain, bundleIDs -> SharedRow in
                let names = bundleIDs.compactMap { id in
                    vm.apps.first { $0.id == id }?.name ?? id
                }.sorted()
                return SharedRow(id: domain, appNames: names)
            }
            .sorted(using: sortOrder)
    }

    // ── 视图 ──────────────────────────────────────────────────────────────────

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            label
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // ── 折叠标签 ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 8) {
            Label("共享域名", systemImage: "arrow.triangle.branch")
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            if !vm.sharedDomainApps.isEmpty {
                // 数量徽章
                Text("\(vm.sharedDomainApps.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)

                // 独占模式提示
                if settings.exclusiveOnly {
                    Text("已过滤")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            if vm.sharedDomainApps.isEmpty && !vm.apps.isEmpty {
                Text("无共享域名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ── 内容区 ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var content: some View {
        if vm.apps.isEmpty {
            Text("请先加载 App Privacy Report 文件")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else if rows.isEmpty {
            Text("所有域名均为各 App 独占")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            Table(rows, sortOrder: $sortOrder) {

                TableColumn("共享域名", value: \.domain) { row in
                    Text(row.domain)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 180, ideal: 240)

                TableColumn("App 数", value: \.appCount) { row in
                    Text("\(row.appCount)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(row.appCount > 5 ? .red : .orange)
                }
                .width(55)

                TableColumn("使用此域名的应用") { row in
                    Text(row.appNames.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // 自适应高度：至少 3 行，最多 7 行，超过后可以通过展开整体滚动
            .frame(height: max(96, min(CGFloat(rows.count) * 23 + 38, 200)))
        }
    }
}

// MARK: - 行模型

private struct SharedRow: Identifiable {
    let id:       String           // domain（唯一）
    let appNames: [String]

    var domain:   String { id }
    var appCount: Int    { appNames.count }
}
