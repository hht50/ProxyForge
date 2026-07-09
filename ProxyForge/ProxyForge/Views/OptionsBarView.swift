import SwiftUI

// MARK: - 选项栏

/// 主窗口顶部的控制条。
struct OptionsBarView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var vm:       ContentViewModel

    var body: some View {
        HStack(spacing: 14) {
            Toggle("过滤系统应用", isOn: $settings.filterSystem)
                .onChange(of: settings.filterSystem) { _ in vm.loadFiles() }

            Toggle("包含 IP", isOn: $settings.includeIPs)
                .onChange(of: settings.includeIPs) { _ in vm.refreshPreview() }

            Toggle("包含共享域名", isOn: Binding(
                get:  { !settings.exclusiveOnly },
                set:  { settings.exclusiveOnly = !$0 }
            ))
            .help("关闭：只导出该 App 独占使用的域名（推荐）\n开启：同时导出与其他 App 共享的域名，作为活跃规则输出")
            .onChange(of: settings.exclusiveOnly) { _ in vm.refreshPreview() }

            Divider().frame(height: 16)

            // 规则优化等级
            Text("规则优化:").foregroundStyle(.secondary)
            Picker("", selection: $settings.optimizationLevel) {
                ForEach(OptimizationLevel.allCases, id: \.rawValue) { level in
                    Text(level.displayName).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .help(OptimizationLevel(rawValue: settings.optimizationLevel)?.helpText ?? "")
            .onChange(of: settings.optimizationLevel) { _ in vm.refreshPreview() }

            Divider().frame(height: 16)

            Text("策略名:").foregroundStyle(.secondary)
            TextField("留空则不附加策略", text: $settings.proxyName)
                .frame(width: 120)
                .textFieldStyle(.roundedBorder)
                .onChange(of: settings.proxyName) { _ in vm.refreshPreview() }

            Divider().frame(height: 16)

            Text("格式:").foregroundStyle(.secondary)
            Picker("", selection: $settings.formatterIdx) {
                ForEach(allFormatters.indices, id: \.self) { i in
                    Text(allFormatters[i].displayName).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .onChange(of: settings.formatterIdx) { _ in vm.refreshPreview() }

            Spacer()

            if vm.isLoading { ProgressView().scaleEffect(0.7) }

            Text(vm.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
