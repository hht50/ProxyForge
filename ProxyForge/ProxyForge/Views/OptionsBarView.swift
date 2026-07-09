import SwiftUI

// MARK: - 选项栏（精简版）

/// 主窗口顶部控制条。格式、优化、策略名、过滤选项。
/// 状态文字已移至底部 StatusBarView，不在此显示。
struct OptionsBarView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var vm:       ContentViewModel

    var body: some View {
        HStack(spacing: 8) {

            // ── 格式选择 ──────────────────────────────────────────────────────
            Picker("", selection: $settings.formatterIdx) {
                ForEach(allFormatters.indices, id: \.self) { i in
                    Text(allFormatters[i].displayName).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 276)
            .help("选择规则输出格式")
            .onChange(of: settings.formatterIdx) { _ in vm.refreshPreview() }

            Divider().frame(height: 16)

            // ── 优化等级 ──────────────────────────────────────────────────────
            Text("优化").font(.callout).foregroundStyle(.secondary)
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

            // ── 策略名 ────────────────────────────────────────────────────────
            Text("策略").font(.callout).foregroundStyle(.secondary)
            TextField("留空不附加", text: $settings.proxyName)
                .frame(width: 100)
                .textFieldStyle(.roundedBorder)
                .help("Loon/Surge 策略名，如 PROXY、🚀 节点选择，留空则不生成策略目标")
                .onChange(of: settings.proxyName) { _ in vm.refreshPreview() }

            Divider().frame(height: 16)

            // ── 过滤选项（紧凑）──────────────────────────────────────────────
            Toggle("系统应用", isOn: $settings.filterSystem)
                .help("过滤 com.apple.* 系统应用（推荐开启）")
                .onChange(of: settings.filterSystem) { _ in vm.loadFiles() }

            Toggle("包含 IP", isOn: $settings.includeIPs)
                .help("在规则中包含 IP 地址条目")
                .onChange(of: settings.includeIPs) { _ in vm.refreshPreview() }

            Toggle("共享域名", isOn: Binding(
                get:  { !settings.exclusiveOnly },
                set:  { settings.exclusiveOnly = !$0 }
            ))
            .help("""
                开启：导出时同时包含被多个 App 共享的域名（作为活跃规则）
                关闭：只导出该 App 独占使用的域名（推荐，更精准）
                """)
            .onChange(of: settings.exclusiveOnly) { _ in vm.refreshPreview() }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
