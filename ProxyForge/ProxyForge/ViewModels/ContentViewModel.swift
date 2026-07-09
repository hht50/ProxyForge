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
    @Published var apps:        [AppEntry]   = []
    /// 多选 ID 集合（AppTableView 直接绑定）
    @Published var selectedIDs: Set<String>  = []
    @Published var isLoading:   Bool         = false
    @Published var statusText:  String       = "请打开 App_Privacy_Report_v4_*.ndjson 文件"
    @Published var ruleText:    String       = "← 点击左侧应用列表，查看该应用的分流规则\n\n请先点击工具栏「打开文件」按钮"
    @Published var sortOrder: [KeyPathComparator<AppEntry>] = [
        KeyPathComparator(\.totalHits, order: .reverse)
    ]

    /// 已加载的文件列表（支持多文件合并）
    @Published private(set) var fileURLs: [URL] = []

    /// domain → [bundleID]；仅包含被 ≥2 个 App 访问的域名
    @Published private(set) var sharedDomainApps: [String: [String]] = [:]

    /// 含共享域名的 App ID 集合（预计算，供 AppTableView 每行 O(1) 查找）
    @Published private(set) var appsWithSharedDomains: Set<String> = []

    // ── 预览生成任务（异步取消用）──────────────────────────────────────────────
    private var previewTask: Task<Void, Never>?

    // ── 对设置的引用（由外部注入）────────────────────────────────────────────
    let settings: UserSettings

    init(settings: UserSettings) {
        self.settings = settings
        Logger.ui.debug("ContentViewModel 初始化")
    }

    // ── 派生属性 ──────────────────────────────────────────────────────────────

    var sortedApps: [AppEntry] { apps.sorted(using: sortOrder) }

    /// 当前预览用的单个 App（多选时取第一个）
    var selectedApp: AppEntry? {
        guard let first = selectedIDs.first else { return nil }
        return apps.first { $0.id == first }
    }

    /// 当前多选的 App 列表（保持 sortedApps 顺序）
    var selectedApps: [AppEntry] {
        sortedApps.filter { selectedIDs.contains($0.id) }
    }

    /// 基础选项（不含 sharedDomains；用于 formatAll / 导出）
    var options: RuleOptions {
        let level = OptimizationLevel(rawValue: settings.optimizationLevel) ?? .smart
        return RuleOptions(
            mergeSub:          level == .minimal,
            proxyTarget:       settings.proxyName,
            includeIPs:        settings.includeIPs,
            sharedDomains:     [],
            optimizationLevel: level,
            exportTypeName:    settings.exclusiveOnly ? "Unique Domains" : "All Domains"
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
                let result    = try await parseReports(urls: urls, filterSystem: filterSystem)
                let doms      = result.reduce(0) { $0 + $1.domainCount }
                let hits      = result.reduce(0) { $0 + $1.totalHits }
                let shared    = Self.computeSharedDomains(from: result)
                // 预计算含共享域名的 App ID 集合（在后台线程做，避免主线程压力）
                let withShared = Self.computeAppsWithSharedDomains(apps: result, sharedKeys: Set(shared.keys))

                await MainActor.run {
                    self.apps                  = result
                    self.sharedDomainApps      = shared
                    self.appsWithSharedDomains = withShared
                    self.isLoading             = false
                    let filePart   = urls.count > 1 ? "\(urls.count) 个文件  ·  " : ""
                    let sharedPart = shared.isEmpty ? "" : "  ·  \(shared.count) 共享域名"
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

    // ── 用户重命名后刷新身份信息 ─────────────────────────────────────────────

    /// 重新解析所有 App 的身份（用户覆盖名称更新后调用）。
    func reloadCurrentIdentities() {
        apps = apps.map { app in
            var updated  = app
            let identity = AppIdentityResolver.shared.resolveIdentity(app.id)
            updated.name     = identity.displayName
            updated.identity = identity
            return updated
        }
        refreshPreview()
    }

        // ── 预览刷新（异步 + 自动取消旧任务）────────────────────────────────────────

    func refreshPreview() {
        // 取消上一个未完成的格式化任务，避免旧结果覆盖新结果
        previewTask?.cancel()

        guard let app = selectedApp else {
            ruleText = "← 点击左侧应用列表，查看该应用的分流规则"
            return
        }

        // 立即给出占位文字，防止切换时出现空白
        ruleText = "正在生成 \(app.name) 的规则预览…"

        // 捕获所有需要的值，Task.detached 中不能访问 MainActor 属性
        let capturedApp       = app
        let capturedFormatter = formatter
        var capturedOptions   = options
        capturedOptions.sharedDomains = Set(sharedDomainApps.keys)

        previewTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // CPU 密集的格式化在后台线程执行
            let text = capturedFormatter.formatOne(app: capturedApp, options: capturedOptions)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.ruleText = text
                Logger.ui.debug("预览已更新: \(capturedApp.bundleID, privacy: .public)")
            }
        }
    }

    // ── 独占域名过滤 ──────────────────────────────────────────────────────────

    /// 返回去掉共享域名后的 AppEntry 副本。
    func filteredApp(_ app: AppEntry) -> AppEntry {
        guard !sharedDomainApps.isEmpty else { return app }
        let shared = Set(sharedDomainApps.keys)
        let doms   = app.domains.filter { !shared.contains($0.key) }
        let hits   = doms.values.reduce(0) { $0 + $1.hits }
        return AppEntry(id: app.id, name: app.name, domains: doms, totalHits: hits, identity: app.identity)
    }

    /// 纯函数版本，可在后台线程调用（不访问 self）
    nonisolated private static func filterApp(_ app: AppEntry, sharedKeys: Set<String>) -> AppEntry {
        guard !sharedKeys.isEmpty else { return app }
        let doms = app.domains.filter { !sharedKeys.contains($0.key) }
        let hits = doms.values.reduce(0) { $0 + $1.hits }
        return AppEntry(id: app.id, name: app.name, domains: doms, totalHits: hits, identity: app.identity)
    }

    // ── 共享域名计算 ──────────────────────────────────────────────────────────

    nonisolated private static func computeSharedDomains(from apps: [AppEntry]) -> [String: [String]] {
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

    /// 预计算含共享域名的 App ID 集合（O(n×d)，在后台线程做一次）
    nonisolated private static func computeAppsWithSharedDomains(
        apps: [AppEntry],
        sharedKeys: Set<String>
    ) -> Set<String> {
        guard !sharedKeys.isEmpty else { return [] }
        var result = Set<String>()
        for app in apps {
            if app.domains.keys.contains(where: { sharedKeys.contains($0) }) {
                result.insert(app.id)
            }
        }
        return result
    }

    // ── 复制 ──────────────────────────────────────────────────────────────────

    func copySelected() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ruleText, forType: .string)
        Logger.export.info("已复制选中规则: \(self.selectedApp?.bundleID ?? "none", privacy: .public)")
        statusText = "✓ 已复制到剪贴板"
    }

    func copyAll() {
        guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
        statusText = "生成全部规则中…"

        // 捕获所有值，避免 Task.detached 访问 MainActor 属性
        let capturedApps      = sortedApps
        let capturedFormatter = formatter
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let exportApps = capturedExclusive
                ? capturedApps.map { Self.filterApp($0, sharedKeys: capturedShared) }
                : capturedApps
            let text = capturedFormatter.formatAll(apps: exportApps, options: capturedOptions)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                Logger.export.info("已复制全部规则 (\(capturedApps.count, privacy: .public) 个应用)")
                self.statusText = "✓ 已复制全部规则（\(capturedApps.count) 个应用）"
            }
        }
    }

    // ── 导出 ──────────────────────────────────────────────────────────────────

    func exportSelected() {
        let targets = selectedApps
        guard !targets.isEmpty else { exportAll(); return }
        if targets.count == 1 {
            exportSingle(app: targets[0])
        } else {
            exportMultipleAsZip(apps: targets)
        }
    }

    func exportAll() {
        guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
        let panel = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"
        panel.nameFieldStringValue = "ProxyForge_\(scopeTag)_\(dateTag()).\(formatter.fileExtension)"
        if let t = UTType(filenameExtension: formatter.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusText = "导出中…"

        let capturedApps      = sortedApps
        let capturedFormatter = formatter
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let exportApps = capturedExclusive
                    ? capturedApps.map { Self.filterApp($0, sharedKeys: capturedShared) }
                    : capturedApps
                let text = capturedFormatter.formatAll(apps: exportApps, options: capturedOptions)
                try text.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    Logger.export.info("导出全部成功: \(url.lastPathComponent, privacy: .public)")
                    self.statusText = "✓ 已导出到 \(url.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    Logger.export.error("导出失败: \(error.localizedDescription, privacy: .public)")
                    self.statusText = "❌ 导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // ── 私有：单 App 导出 ─────────────────────────────────────────────────────

    private func exportSingle(app: AppEntry) {
        let panel = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"
        let safeName = app.name.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName)_\(scopeTag)_\(dateTag()).\(formatter.fileExtension)"
        if let t = UTType(filenameExtension: formatter.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusText = "导出中…"

        let capturedApp       = app
        let capturedFormatter = formatter
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let exportApp = capturedExclusive
                    ? Self.filterApp(capturedApp, sharedKeys: capturedShared)
                    : capturedApp
                let text = capturedFormatter.formatOne(app: exportApp, options: capturedOptions)
                try text.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    Logger.export.info("导出单 App 成功: \(url.lastPathComponent, privacy: .public)")
                    self.statusText = "✓ 已导出 \(capturedApp.name) → \(url.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    Logger.export.error("导出失败: \(error.localizedDescription, privacy: .public)")
                    self.statusText = "❌ 导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // ── 私有：多 App ZIP 导出 ─────────────────────────────────────────────────

    private func exportMultipleAsZip(apps targets: [AppEntry]) {
        let panel = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"
        panel.nameFieldStringValue = "ProxyForge_\(targets.count)个应用_\(scopeTag)_\(dateTag()).zip"
        if let t = UTType(filenameExtension: "zip") { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let zipURL = panel.url else { return }

        statusText = "打包 ZIP 中…"

        let capturedFormatter = formatter
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)
        let capturedTargets   = targets

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let exportApps = capturedExclusive
                    ? capturedTargets.map { Self.filterApp($0, sharedKeys: capturedShared) }
                    : capturedTargets
                try await Self.buildZip(
                    apps:      exportApps,
                    formatter: capturedFormatter,
                    options:   capturedOptions,
                    scopeTag:  scopeTag,
                    to:        zipURL
                )
                await MainActor.run {
                    Logger.export.info("ZIP 导出成功: \(zipURL.lastPathComponent, privacy: .public)")
                    self.statusText = "✓ 已导出 \(capturedTargets.count) 个应用 → \(zipURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    Logger.export.error("ZIP 导出失败: \(error.localizedDescription, privacy: .public)")
                    self.statusText = "❌ ZIP 导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func buildZip(
        apps:      [AppEntry],
        formatter: any RuleFormatter,
        options:   RuleOptions,
        scopeTag:  String,
        to zipURL: URL
    ) async throws {
        let fm     = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        var filePaths: [String] = []
        for app in apps {
            let safeName = app.name.replacingOccurrences(of: "/", with: "-")
            let fileName = "\(safeName)_\(scopeTag).\(formatter.fileExtension)"
            let fileURL  = tmpDir.appendingPathComponent(fileName)
            let text     = formatter.formatOne(app: app, options: options)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            filePaths.append(fileURL.path)
        }

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", zipURL.path] + filePaths
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ProxyForge.ZipError",
                code:   Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "zip 返回错误码 \(process.terminationStatus)"]
            )
        }
    }

    // ── 工具 ──────────────────────────────────────────────────────────────────

    private func dateTag() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
