import SwiftUI

// MARK: - 选项栏

/// 主窗口顶部的控制条：过滤开关、策略名、格式选择器、导出范围、状态文字。
struct OptionsBarView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var vm:       ContentViewModel

    var body: some View {
        HStack(spacing: 14) {
            Toggle("过滤系统应用", isOn: $settings.filterSystem)
                .onChange(of: settings.filterSystem) { _ in vm.loadFiles() }

            Toggle("合并子域", isOn: $settings.mergeSub)
                .onChange(of: settings.mergeSub) { _ in vm.refreshPreview() }

            Toggle("包含 IP", isOn: $settings.includeIPs)
                .onChange(of: settings.includeIPs) { _ in vm.refreshPreview() }

            Divider().frame(height: 16)

            // 导出范围：单选 Picker，替代原 Toggle
            Text("导出范围:").foregroundStyle(.secondary)
            Picker("", selection: $settings.exclusiveOnly) {
                Text("仅独有域名").tag(true)
                Text("全部域名").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .help("仅独有域名：只导出该 App 独占使用的域名\n全部域名：包含独有域名 + 与其他 App 共享的域名")
            .onChange(of: settings.exclusiveOnly) { _ in vm.refreshPreview() }

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
