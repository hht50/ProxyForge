import SwiftUI
import UniformTypeIdentifiers
import AppKit
import os.log

// MARK: - ContentViewModel

/// 主视图的所有业务逻辑与状态。
/// 通过 @EnvironmentObject 注入的 UserSettings 读取/写入用户偏好。
@MainActor
final class ContentViewModel: ObservableObject {

    // ── 数据状态 ──────────────────────────────────────────────────────────────
    @Published var apps:       [AppEntry] = []
    @Published var selectedID: String?    = nil
    @Published var isLoading:  Bool       = false
    @Published var statusText: String     = "请打开 App_Privacy_Report_v4_*.ndjson 文件"
    @Published var ruleText:   String     = "← 点击左侧应用列表，查看该应用的分流规则\n\n请先点击工具栏「打开文件」按钮"
    @Published var sortOrder: [KeyPathComparator<AppEntry>] = [
        KeyPathComparator(\.totalHits, order: .reverse)
    ]

    private(set) var fileURL: URL? = nil

    // ── 对设置的引用（由外部注入）────────────────────────────────────────────
    let settings: UserSettings

    init(settings: UserSettings) {
        self.settings = settings
        Logger.ui.debug("ContentViewModel 初始化")
    }

    // ── 派生属性 ──────────────────────────────────────────────────────────────

    var sortedApps: [AppEntry]  { apps.sorted(using: sortOrder) }
    var selectedApp: AppEntry?  { apps.first { $0.id == selectedID } }

    var options: RuleOptions {
        RuleOptions(
            mergeSub:    settings.mergeSub,
            proxyTarget: settings.proxyName.isEmpty ? "Proxy" : settings.proxyName,
            includeIPs:  settings.includeIPs
        )
    }

    var formatter: any RuleFormatter { allFormatters[settings.formatterIdx] }

    // ── 文件操作 ──────────────────────────────────────────────────────────────

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "选择 App Privacy Report 文件"
        if let t = UTType(filenameExtension: "ndjson") { panel.allowedContentTypes = [t] }
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Logger.ui.info("用户选择文件: \(url.lastPathComponent, privacy: .public)")
        fileURL = url
        loadFile()
    }

    func loadFile() {
        guard let url = fileURL else { return }
        isLoading  = true
        statusText = "解析中…"

        // 捕获当前值，避免在后台任务中跨 actor 访问
        let filterSystem = settings.filterSystem

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try parseReport(url: url, filterSystem: filterSystem)
                let doms   = result.reduce(0) { $0 + $1.domainCount }
                let hits   = result.reduce(0) { $0 + $1.totalHits }
                await MainActor.run {
                    self.apps       = result
                    self.isLoading  = false
                    self.statusText = "✓  \(result.count) 个应用  ·  \(doms) 个域名  ·  \(hits) 次访问"
                    self.refreshPreview()
                }
            } catch {
                Logger.parser.error("解析失败: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.isLoading  = false
                    self.statusText = "❌ 解析失败: \(error.localizedDescription)"
                }
            }
        }
    }

    func refreshPreview() {
        guard let app = selectedApp else { return }
        ruleText = formatter.formatOne(app: app, options: options)
        Logger.ui.debug("刷新预览: \(app.bundleID, privacy: .public)")
    }

    // ── 复制 / 导出 ───────────────────────────────────────────────────────────

    func copySelected() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ruleText, forType: .string)
        Logger.export.info("已复制选中规则: \(self.selectedApp?.bundleID ?? "none", privacy: .public)")
        statusText = "✓ 已复制到剪贴板"
    }

    func copyAll() {
        guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
        let text = formatter.formatAll(apps: sortedApps, options: options)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Logger.export.info("已复制全部规则 (\(self.apps.count, privacy: .public) 个应用)")
        statusText = "✓ 已复制全部规则（\(apps.count) 个应用）"
    }

    func exportFile() {
        guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "rules.\(formatter.fileExtension)"
        if let t = UTType(filenameExtension: formatter.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = formatter.formatAll(apps: sortedApps, options: options)
            try text.write(to: url, atomically: true, encoding: .utf8)
            Logger.export.info("导出成功: \(url.lastPathComponent, privacy: .public)")
            statusText = "✓ 已导出到 \(url.lastPathComponent)"
        } catch {
            Logger.export.error("导出失败: \(error.localizedDescription, privacy: .public)")
            statusText = "❌ 导出失败: \(error.localizedDescription)"
        }
    }
}
