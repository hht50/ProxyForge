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
    ] {
        didSet { Self.persistSortOrder(sortOrder) }
    }

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
        AppLogger.shared.debug("ContentViewModel 初始化", category: .app)
        // 从 UserSettings 恢复上次排序状态
        self.sortOrder = Self.restoredSortOrder(key: settings.appSortKey, ascending: settings.appSortAscending)
        // 预热 L1：从上次会话保存的 bundleID 列表加载 L2→L1，避免冷启动首屏等待
        let savedIDs = UserDefaults.standard.stringArray(forKey: Self.bundleIDsCacheKey) ?? []
        if !savedIDs.isEmpty {
            Task.detached(priority: .background) {
                AppIdentityResolver.shared.preload(bundleIDs: savedIDs)
            }
        }
    }

    // UserDefaults key — 存储上次解析的所有 bundleID，供下次启动预热用
    private static let bundleIDsCacheKey = "com.proxyforge.lastBundleIDs"

    // ── 排序持久化辅助 ────────────────────────────────────────────────────────

    /// 将当前 sortOrder 序列化为 (key, ascending) 写入 UserDefaults。
    /// 只取第一个 comparator（Table 交互通常只有一个主排序键）。
    private static func persistSortOrder(_ order: [KeyPathComparator<AppEntry>]) {
        guard let first = order.first else { return }
        let key: String
        switch first.keyPath {
        case \AppEntry.name:                  key = "name"
        case \AppEntry.totalHits:             key = "totalHits"
        case \AppEntry.domainCount:           key = "domainCount"
        case \AppEntry.exclusiveDomainCount:  key = "exclusiveDomainCount"
        case \AppEntry.sharedDomainCount:     key = "sharedDomainCount"
        case \AppEntry.ipCount:               key = "ipCount"
        case \AppEntry.bundleID:              key = "bundleID"
        default:                              key = "totalHits"
        }
        UserDefaults.standard.set(key,                            forKey: "com.proxyforge.sortKey")
        UserDefaults.standard.set(first.order == .forward,        forKey: "com.proxyforge.sortAscending")
    }

    /// 从持久化的 (key, ascending) 还原 sortOrder。
    static func restoredSortOrder(key: String, ascending: Bool) -> [KeyPathComparator<AppEntry>] {
        let dir: SortOrder = ascending ? .forward : .reverse
        switch key {
        case "name":                 return [KeyPathComparator(\.name,                  order: dir)]
        case "domainCount":          return [KeyPathComparator(\.domainCount,           order: dir)]
        case "exclusiveDomainCount": return [KeyPathComparator(\.exclusiveDomainCount,  order: dir)]
        case "sharedDomainCount":    return [KeyPathComparator(\.sharedDomainCount,     order: dir)]
        case "ipCount":              return [KeyPathComparator(\.ipCount,               order: dir)]
        case "bundleID":             return [KeyPathComparator(\.bundleID,              order: dir)]
        default:                     return [KeyPathComparator(\.totalHits,             order: .reverse)]
        }
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
    /// 导出格式（独立于预览格式，随 exportFormatIdx 持久化）
    var exportFormatter: any RuleFormatter { allFormatters[settings.exportFormatIdx] }

    // ── 文件操作 ──────────────────────────────────────────────────────────────

    /// 接收 Finder 拖放的文件（过滤非 .ndjson 格式）
    func loadDroppedFiles(_ urls: [URL]) {
        let valid = urls.filter { $0.pathExtension.lowercased() == "ndjson" }
        guard !valid.isEmpty else {
            statusText = "⚠ 请拖入 App_Privacy_Report_v4_*.ndjson 文件"
            return
        }
        fileURLs = valid
        loadFiles()
    }

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
                // 填充每个 App 的 sharedDomainCount（供表格"共享/独占"列排序）
                let sharedKeys = Set(shared.keys)
                let enriched   = result.map { app -> AppEntry in
                    var a = app
                    a.sharedDomainCount = app.domains.keys.filter { sharedKeys.contains($0) }.count
                    return a
                }

                // 持久化 bundleIDs，供下次启动预热 L1（非主线程操作，不阻塞 UI）
                let bundleIDs = result.map(\.id)
                UserDefaults.standard.set(bundleIDs, forKey: Self.bundleIDsCacheKey)

                await MainActor.run {
                    self.apps                  = enriched
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

    /// 将指定范围以单一格式导出。
    /// - `scope.selected([app])` → NSSavePanel，单文件（formatOne）
    /// - `scope.selected([...])` → NSSavePanel，ZIP（每App一文件）
    /// - `scope.all`             → NSSavePanel，ZIP（每 App 一文件，与多选语义一致）
    func export(scope: ExportScope, format: ExportFormat) {
        let fmt = format.formatter
        switch scope {
        case .selected(let targets):
            guard !targets.isEmpty else { return }
            if targets.count == 1 { exportSingle(app: targets[0], fmt: fmt) }
            else                  { exportMultipleAsZip(apps: targets, fmt: fmt) }
        case .all:
            guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
            exportMultipleAsZip(apps: sortedApps, fmt: fmt, baseName: "ProxyForge")
        }
    }

    /// 将指定范围以全部4种格式导出为 ZIP。
    /// - `scope.all`              → ZIP含4个合并文件（每格式一个，formatAll）
    /// - `scope.selected([app])`  → ZIP含4个单App文件（每格式一个，formatOne）
    /// - `scope.selected([...])`  → ZIP含4个子目录（每目录N个App文件）
    func exportAllFormats(scope: ExportScope) {
        let panel    = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"

        switch scope {
        case .selected(let targets) where targets.count == 1:
            let safeName = targets[0].name.replacingOccurrences(of: "/", with: "-")
            panel.nameFieldStringValue = "\(safeName)_所有格式_\(dateTag()).zip"
        case .selected(let targets):
            panel.nameFieldStringValue = "ProxyForge_\(targets.count)个应用_所有格式_\(dateTag()).zip"
        case .all:
            panel.nameFieldStringValue = "ProxyForge_所有格式_\(scopeTag)_\(dateTag()).zip"
        }
        if let t = UTType(filenameExtension: "zip") { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let zipURL = panel.url else { return }

        statusText = "生成所有格式 ZIP 中…"

        let capturedScope     = scope
        let capturedSortedApps = sortedApps
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await Self.buildAllFormatsZip(
                    scope:         capturedScope,
                    sortedApps:    capturedSortedApps,
                    options:       capturedOptions,
                    exclusiveOnly: capturedExclusive,
                    sharedKeys:    capturedShared,
                    scopeTag:      scopeTag,
                    to:            zipURL
                )
                await MainActor.run {
                    Logger.export.info("所有格式 ZIP 成功: \(zipURL.lastPathComponent, privacy: .public)")
                    self.statusText = "✓ 已导出所有格式 → \(zipURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    Logger.export.error("所有格式 ZIP 失败: \(error.localizedDescription, privacy: .public)")
                    self.statusText = "❌ 导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // ── 私有：合并大文件（formatAll）─────────────────────────────────────────

    private func exportAllMerged(fmt: any RuleFormatter) {
        guard !apps.isEmpty else { statusText = "⚠ 请先加载文件"; return }
        let panel    = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"
        panel.nameFieldStringValue = "ProxyForge_\(scopeTag)_\(dateTag()).\(fmt.fileExtension)"
        if let t = UTType(filenameExtension: fmt.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusText = "导出中…"

        let capturedApps      = sortedApps
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let exportApps = capturedExclusive
                    ? capturedApps.map { Self.filterApp($0, sharedKeys: capturedShared) }
                    : capturedApps
                let text = fmt.formatAll(apps: exportApps, options: capturedOptions)
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

    private func exportSingle(app: AppEntry, fmt: any RuleFormatter) {
        let panel    = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"
        let safeName = app.name.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName)_\(scopeTag)_\(dateTag()).\(fmt.fileExtension)"
        if let t = UTType(filenameExtension: fmt.fileExtension) { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusText = "导出中…"

        let capturedApp       = app
        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let exportApp = capturedExclusive
                    ? Self.filterApp(capturedApp, sharedKeys: capturedShared)
                    : capturedApp
                let text = fmt.formatOne(app: exportApp, options: capturedOptions)
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

    // ── 私有：多 App ZIP 导出（单格式）────────────────────────────────────────

    private func exportMultipleAsZip(apps targets: [AppEntry], fmt: any RuleFormatter, baseName: String? = nil) {
        let panel    = NSSavePanel()
        let scopeTag = settings.exclusiveOnly ? "独有" : "全部"
        let fileBase = baseName ?? "ProxyForge_\(targets.count)个应用"
        panel.nameFieldStringValue = "\(fileBase)_\(scopeTag)_\(dateTag()).zip"
        if let t = UTType(filenameExtension: "zip") { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let zipURL = panel.url else { return }

        statusText = "打包 ZIP 中…"

        let capturedOptions   = options
        let capturedExclusive = settings.exclusiveOnly
        let capturedShared    = Set(sharedDomainApps.keys)
        let capturedTargets   = targets

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let ctx = ExportLogger.start(
                format:      fmt.displayName,
                appCount:    capturedTargets.count,
                domainCount: capturedTargets.reduce(0) { $0 + $1.domainCount }
            )
            do {
                let t0 = CFAbsoluteTimeGetCurrent()
                let exportApps = capturedExclusive
                    ? capturedTargets.map { Self.filterApp($0, sharedKeys: capturedShared) }
                    : capturedTargets
                var c = ctx; c.addStep("filter", from: t0)
                let t1 = CFAbsoluteTimeGetCurrent()
                try await Self.buildZip(
                    apps:      exportApps,
                    formatter: fmt,
                    options:   capturedOptions,
                    scopeTag:  scopeTag,
                    to:        zipURL
                )
                var c2 = c; c2.addStep("zip", from: t1)
                await MainActor.run {
                    ExportLogger.complete(context: c2, fileURL: zipURL)
                    self.statusText = "✓ 已导出 \(capturedTargets.count) 个应用 → \(zipURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    ExportLogger.failed(error, context: ctx)
                    self.statusText = "❌ ZIP 导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // ── 私有静态：所有格式 ZIP ────────────────────────────────────────────────

    private static func buildAllFormatsZip(
        scope:         ExportScope,
        sortedApps:    [AppEntry],
        options:       RuleOptions,
        exclusiveOnly: Bool,
        sharedKeys:    Set<String>,
        scopeTag:      String,
        to zipURL:     URL
    ) async throws {
        let fm     = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        var flatFilePaths: [String] = []   // 用于 zip -j（平铺）
        var useSubDirs = false             // 用于 zip -r（子目录）

        switch scope {
        case .all:
            // 每格式一子目录，每 App 一文件（与 selected(N apps) 语义一致）
            useSubDirs = true
            let apps = exclusiveOnly
                ? sortedApps.map { filterApp($0, sharedKeys: sharedKeys) }
                : sortedApps
            for fmt in allFormatters {
                let subDir = tmpDir.appendingPathComponent(fmt.displayName)
                try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
                for app in apps {
                    let safeName = app.name.replacingOccurrences(of: "/", with: "-")
                    let fileURL  = subDir.appendingPathComponent("\(safeName).\(fmt.fileExtension)")
                    try fmt.formatOne(app: app, options: options)
                        .write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }

        case .selected(let targets):
            let apps = exclusiveOnly
                ? targets.map { filterApp($0, sharedKeys: sharedKeys) }
                : targets

            if apps.count == 1, let app = apps.first {
                // 单 App：每格式一文件，平铺
                let safeName = app.name.replacingOccurrences(of: "/", with: "-")
                for fmt in allFormatters {
                    let fileName = "\(safeName)_\(fmt.displayName).\(fmt.fileExtension)"
                    let fileURL  = tmpDir.appendingPathComponent(fileName)
                    try fmt.formatOne(app: app, options: options)
                        .write(to: fileURL, atomically: true, encoding: .utf8)
                    flatFilePaths.append(fileURL.path)
                }
            } else {
                // 多 App：每格式一子目录，每目录 N 个文件
                useSubDirs = true
                for fmt in allFormatters {
                    let subDir = tmpDir.appendingPathComponent(fmt.displayName)
                    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
                    for app in apps {
                        let safeName = app.name.replacingOccurrences(of: "/", with: "-")
                        let fileURL  = subDir.appendingPathComponent("\(safeName).\(fmt.fileExtension)")
                        try fmt.formatOne(app: app, options: options)
                            .write(to: fileURL, atomically: true, encoding: .utf8)
                    }
                }
            }
        }

        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        if useSubDirs {
            // zip -r 从 tmpDir 目录递归，保留子目录结构
            process.currentDirectoryURL = tmpDir
            process.arguments = ["-r", zipURL.path] + allFormatters.map(\.displayName)
        } else {
            process.arguments = ["-j", zipURL.path] + flatFilePaths
        }
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

    // ── 私有静态：单格式多 App ZIP ────────────────────────────────────────────

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
            try formatter.formatOne(app: app, options: options)
                .write(to: fileURL, atomically: true, encoding: .utf8)
            filePaths.append(fileURL.path)
        }

        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }

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
