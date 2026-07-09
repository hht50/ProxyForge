import SwiftUI

// MARK: - 选项栏

/// 主窗口顶部控制条。
/// 主流程（格式 → 优化 → 策略名）直接显示；
/// 高级过滤条件（系统/IP/共享）折叠进 ⚙ 选项 Popover，减少主 bar 宽度压力。
struct OptionsBarView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var vm:       ContentViewModel

    @State private var showFilterPopover = false

    // 激活过滤选项数量（非默认值时亮起 badge）
    private var activeFilterCount: Int {
        (settings.filterSystem  ? 1 : 0)  // 默认开，开着不算激活
            + (settings.includeIPs ? 1 : 0)
            + (!settings.exclusiveOnly ? 0 : 1) // exclusiveOnly=true 是非默认
    }

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

            // ── ⚙ 选项 Popover ────────────────────────────────────────────────
            filterButton

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // ── ⚙ 按钮（有激活项时显示蓝色小圆点）─────────────────────────────────────

    private var filterButton: some View {
        Button {
            showFilterPopover.toggle()
        } label: {
            Label("选项", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("过滤选项：系统应用、IP 规则、共享域名")
        .overlay(alignment: .topTrailing) {
            // 圆点仅在有非默认激活选项时出现
            if activeFilterCount > 0 {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .offset(x: 3, y: -3)
            }
        }
        .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
            filterPopoverContent
        }
    }

    // ── Popover 内容 ──────────────────────────────────────────────────────────

    private var filterPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            Text("过滤选项")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Toggle("过滤系统应用", isOn: $settings.filterSystem)
                    .help("过滤 com.apple.* 系统应用（推荐开启）")
                    .onChange(of: settings.filterSystem) { _ in vm.loadFiles() }

                Toggle("包含 IP 规则", isOn: $settings.includeIPs)
                    .help("在规则中包含 IP 地址条目")
                    .onChange(of: settings.includeIPs) { _ in vm.refreshPreview() }

                Toggle("包含共享域名", isOn: Binding(
                    get:  { !settings.exclusiveOnly },
                    set:  { settings.exclusiveOnly = !$0 }
                ))
                .help("""
                    开启：导出时包含被多个 App 共享的域名
                    关闭：只导出该 App 独占的域名（更精准）
                    """)
                .onChange(of: settings.exclusiveOnly) { _ in vm.refreshPreview() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(width: 220)
    }
}
