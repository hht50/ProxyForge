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

    /// 已加载的文件列表（支持多文件合并）
    @Published private(set) var fileURLs: [URL] = []

    /// domain → [bundleID]；仅包含被 ≥2 个 App 访问的域名
    @Published private(set) var sharedDomainApps: [String: [String]] = [:]

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
        panel.title = "选择 App Privacy Report 文件（可多选合并）"
        if let t = UTType(filenameExtension: "ndjson") { panel.allowedContentTypes = [t] }
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let names = panel.urls.map(\.lastPathComponent).joined(separator: ", ")
        Logger.ui.info("用户选择 \(panel.urls.count, privacy: .public) 个文件: \(names, privacy: .public)")
        fileURLs = panel.urls
        loadFiles()
    }

    func loadFiles() {
        guard !fileURLs.isEmpty else { return }
        isLoading  = true
        statusText = fileURLs.count == 1 ? "解析中…" : "并发解析 \(fileURLs.count) 个文件…"

        let urls         = fileURLs
        let filterSystem = settings.filterSystem

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await parseReports(urls: urls, filterSystem: filterSystem)
                let doms   = result.reduce(0) { $0 + $1.domainCount }
                let hits   = result.reduce(0) { $0 + $1.totalHits }
                await MainActor.run {
                    self.apps             = result
                    self.sharedDomainApps = Self.computeSharedDomains(from: result)
                    self.isLoading        = false
                    let filePart    = urls.count > 1 ? "\(urls.count) 个文件  ·  " : ""
                    let sharedPart  = self.sharedDomainApps.isEmpty ? "" : "  ·  \(self.sharedDomainApps.count) 共享域名"
                    self.statusText = "✓  \(filePart)\(result.count) 个应用  ·  \(doms) 个域名  ·  \(hits) 次访问\(sharedPart)"
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
        ruleText = formatter.formatOne(app: filteredApp(app), options: options)
        Logger.ui.debug("刷新预览: \(app.bundleID, privacy: .public)")
    }

    // ── 独占域名过滤 ──────────────────────────────────────────────────────────

    /// exclusiveOnly 开启时，返回去掉共享域名后的 AppEntry 副本；否则原样返回。
    func filteredApp(_ app: AppEntry) -> AppEntry {
        guard settings.exclusiveOnly, !sharedDomainApps.isEmpty else { return app }
        let shared = Set(sharedDomainApps.keys)
        let doms   = app.domains.filter { !shared.contains($0.key) }
        let hits   = doms.values.reduce(0) { $0 + $1.hits }
        return AppEntry(id: app.id, name: app.name, domains: doms, totalHits: hits)
    }

    // ── 共享域名计算 ──────────────────────────────────────────────────────────

    /// 返回被 ≥2 个 App 访问的域名映射（domain → [bundleID]）。
    private static func computeSharedDomains(from apps: [AppEntry]) -> [String: [String]] {
        var map = [String: Set<String>]()
        for app in apps {
            for domain in app.domains.keys {
                map[domain, default: []].insert(app.bundleID)
            }
        }
        var result = [String: [String]]()
        for (domain, ids) in map where ids.count >= 2 {
            result[domain] = Array(ids)
        }
        return result
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
        let filtered = sortedApps.map { filteredApp($0) }
        let text     = formatter.formatAll(apps: filtered, options: options)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Logger.export.info("已复制全部规则 (\(self.apps.count, privacy: .public) 个应用, 独占:\(self.settings.exclusiveOnly, privacy: .public))")
        statusText = "✓ 已复制全部规则（\(apps.count) 个应用）"
    }

    func exportFile() {
        guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "rules.\(formatter.fileExtension)"
        if let t = UTType(filenameExtension: formatter.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let filtered = sortedApps.map { filteredApp($0) }
            let text     = formatter.formatAll(apps: filtered, options: options)
            try text.write(to: url, atomically: true, encoding: .utf8)
            Logger.export.info("导出成功: \(url.lastPathComponent, privacy: .public)")
            statusText = "✓ 已导出到 \(url.lastPathComponent)"
        } catch {
            Logger.export.error("导出失败: \(error.localizedDescription, privacy: .public)")
            statusText = "❌ 导出失败: \(error.localizedDescription)"
        }
    }
}
