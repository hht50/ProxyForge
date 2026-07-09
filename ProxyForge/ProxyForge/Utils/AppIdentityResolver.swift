import Foundation
import AppKit
import os.log

// MARK: - App Identity Resolver
//
// 解析链（优先级从高到低）：
//   1. 用户自定义覆盖 → confidence 1.00
//   2. KnownApps 静态数据库 → 0.99
//   3. NSWorkspace LaunchServices + Info.plist → 0.97
//   4. BundleID 段词典（NLP）→ 0.82
//   5. CamelCase 拆分兜底 → 0.58
//   6. 原始 bundleID → 0.20
//
// 缓存层（L1 → L2 → L3）：
//   L1 内存缓存   — 进程内命中，0μs
//   L2 磁盘缓存   — JSON 文件（~/Library/ApplicationSupport/ProxyForge/IdentityCache.json），
//                   跳过 LaunchServices，只做 NSImage 重建，约 5~10ms
//   L3 NSWorkspace — 冷路径，约 10~50ms per app；结果写回 L1 + L2
//
// BundleID 规范化在所有解析之前执行：
//   剥离 .helper / .xpc / .service / .plugin / .extension / .agent 等后缀，
//   使 com.tencent.xin.helper 和 com.tencent.xin 合并到同一个条目。

// MARK: - 磁盘缓存条目（不含 NSImage）

/// 可序列化的缓存条目。故意不存储 NSImage — 启动时按 bundlePath 重建，
/// 避免占用内存和序列化开销。
private struct CachedIdentity: Codable {
    let canonicalBundleID: String
    let displayName:       String
    let developer:         String?
    let categoryRaw:       String?   // AppCategory.rawValue
    let bundlePath:        String?   // 本机 .app 路径，用于图标重建
    let sourceRaw:         String    // ResolutionSource.rawValue
    let timestamp:         Date

    /// 磁盘缓存有效期：30 天。超期后触发 L3 重新解析。
    static let expiryInterval: TimeInterval = 30 * 24 * 3600

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > Self.expiryInterval
    }

    /// 重建 ResolvedAppIdentity。图标从 bundlePath 直接加载（跳过 LaunchServices 查询）。
    func toResolved() -> ResolvedAppIdentity {
        let icon = bundlePath.flatMap { NSWorkspace.shared.icon(forFile: $0) }
        return ResolvedAppIdentity(
            canonicalBundleID: canonicalBundleID,
            displayName:       displayName,
            developer:         developer,
            category:          categoryRaw.flatMap { AppCategory(rawValue: $0) },
            icon:              icon,
            source:            ResolutionSource(rawValue: sourceRaw) ?? .fallback
        )
    }
}

// MARK: - Resolver

final class AppIdentityResolver {

    // MARK: - Singleton
    static let shared = AppIdentityResolver()

    // MARK: - L1 内存缓存（normalized bundleID → ResolvedAppIdentity）
    private var cache:     [String: ResolvedAppIdentity] = [:]

    // MARK: - L2 磁盘缓存（normalized bundleID → CachedIdentity）
    private var diskCache: [String: CachedIdentity] = [:]

    /// 保护 cache + diskCache 的字典读写
    private let cacheLock = NSLock()

    /// 后台磁盘写入队列（串行，防止并发写入损坏文件）
    private let saveQueue = DispatchQueue(label: "com.proxyforge.identity.save", qos: .utility)

    // MARK: - 用户覆盖（highest priority, normalized bundleID → 自定义名称）
    private var userOverrides: [String: String] = [:]

    private var overridesURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ProxyForge/UserOverrideApps.json")
    }

    private var diskCacheURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ProxyForge/IdentityCache.json")
    }

    private init() {
        loadUserOverrides()
        loadDiskCache()
        Logger.resolver.info("初始化完成: L2磁盘缓存 \(self.diskCache.count, privacy: .public) 条")
    }

    // MARK: - 用户覆盖 API

    /// 添加或更新用户自定义名称（持久化到磁盘，下次启动自动加载）。
    func setUserOverride(bundleID: String, name: String) {
        let key = normalize(bundleID)
        userOverrides[key] = name
        let identity = ResolvedAppIdentity.userOverride(bundleID: key, name: name)
        cacheLock.withLock {
            cache[key] = identity
            diskCache.removeValue(forKey: key)   // 强制下次重新写入（带 userOverride source）
        }
        saveUserOverrides()
    }

    /// 删除一条用户自定义覆盖。
    func removeUserOverride(bundleID: String) {
        let key = normalize(bundleID)
        userOverrides.removeValue(forKey: key)
        cacheLock.withLock {
            cache.removeValue(forKey: key)
            diskCache.removeValue(forKey: key)
        }
        saveUserOverrides()
    }

    /// 当前所有用户覆盖（规范化 bundleID → 自定义名称）。
    var allUserOverrides: [String: String] { userOverrides }

    // MARK: - 预热接口

    /// 批量预热 L1 内存缓存（从 L2 磁盘加载或触发 L3 解析）。
    /// 应从后台线程调用，避免阻塞主线程。
    /// 典型调用时机：ContentViewModel 加载报告后。
    func preload(bundleIDs: [String]) {
        Logger.resolver.info("预热开始: \(bundleIDs.count, privacy: .public) 个 bundleID")
        let t0 = CFAbsoluteTimeGetCurrent()
        for bid in bundleIDs { _ = resolveIdentity(bid) }
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        Logger.resolver.info("预热完成: \(bundleIDs.count, privacy: .public) 个，耗时 \(elapsed, privacy: .public)ms")
    }

    // MARK: - BundleID 规范化

    /// 剥离进程后缀，实现同 App 多进程自动合并。
    /// 例：com.tencent.xin.helper → com.tencent.xin
    func normalize(_ bundleID: String) -> String {
        let lowered = bundleID.lowercased()
        var parts   = lowered.split(separator: ".", omittingEmptySubsequences: true)
        let stripped: Set<String> = [
            "helper", "xpc", "service", "plugin", "extension", "agent", "daemon",
            "notificationservice", "notificationserviceextension",
            "shareextension", "widget", "widgetextension",
            "watchkitapp", "watchkitextension",
            "intentsextension", "intentsuiextension",
            "notificationcontentextension", "fileprovidernodeprovider",
            "fileprovider", "clipboardservice", "loginitem", "launcher",
        ]
        while let last = parts.last, stripped.contains(String(last)) { parts.removeLast() }
        let result = parts.joined(separator: ".")
        return result.isEmpty ? lowered : result
    }

    // MARK: - 主解析入口（三级缓存）

    /// 解析 bundleID，返回完整的应用身份（名称、开发者、分类、图标、置信度）。
    /// 顺序：L1 内存 → L2 磁盘 → L3 NSWorkspace（结果写回 L1 + L2）。
    func resolveIdentity(_ rawBundleID: String) -> ResolvedAppIdentity {
        let key = normalize(rawBundleID)

        // L1: 内存缓存 — 0μs
        if let hit = cacheLock.withLock({ cache[key] }) {
            Logger.resolver.debug("🟢 memory: \(key, privacy: .public)")
            return hit
        }

        // L2: 磁盘缓存 — 跳过 LaunchServices，只重建图标
        if let entry = cacheLock.withLock({ diskCache[key] }), !entry.isExpired {
            Logger.resolver.debug("🔵 disk: \(key, privacy: .public) [\(entry.sourceRaw, privacy: .public)]")
            let resolved = entry.toResolved()
            cacheLock.withLock { cache[key] = resolved }
            return resolved
        }

        // L3: 完整解析（NSWorkspace + 各级回退）
        let t0 = CFAbsoluteTimeGetCurrent()
        let (result, bundlePath) = resolveUncached(key: key, raw: rawBundleID)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        Logger.resolver.info("🔴 resolved: \(key, privacy: .public) via \(result.source.rawValue, privacy: .public) [\(elapsed, privacy: .public)ms]")

        // 写回 L1 + L2
        let diskEntry = CachedIdentity(
            canonicalBundleID: key,
            displayName:       result.displayName,
            developer:         result.developer,
            categoryRaw:       result.category?.rawValue,
            bundlePath:        bundlePath,
            sourceRaw:         result.source.rawValue,
            timestamp:         Date()
        )
        cacheLock.withLock {
            cache[key]     = result
            diskCache[key] = diskEntry
        }
        saveDiskCacheAsync()

        return result
    }

    /// 便利方法：只需要显示名称时使用。
    func resolve(_ rawBundleID: String) -> String {
        resolveIdentity(rawBundleID).displayName
    }

    // MARK: - 解析链（内部）

    /// 返回 (identity, bundlePath)，bundlePath 供磁盘缓存条目使用。
    private func resolveUncached(key: String, raw: String) -> (ResolvedAppIdentity, bundlePath: String?) {

        // Level 1: 用户自定义覆盖
        if let name = userOverrides[key] {
            return (.userOverride(bundleID: key, name: name), bundlePath: nil)
        }

        // Level 2: KnownApps 静态数据库
        if let name = KnownApps.displayName(for: key) {
            let (icon, path) = appIconAndPath(for: key) ?? (nil, nil)
            return (ResolvedAppIdentity(
                canonicalBundleID: key,
                displayName:       name,
                developer:         KnownApps.developer(for: key),
                category:          KnownApps.category(for: key),
                icon:              icon,
                source:            .knownApps
            ), bundlePath: path)
        }

        // Level 3: NSWorkspace LaunchServices + Info.plist
        if let (name, icon, path) = appNameAndIconFromLaunchServices(key) {
            return (ResolvedAppIdentity(
                canonicalBundleID: key,
                displayName:       name,
                developer:         developerFromBundle(bundlePath: path),
                category:          nil,
                icon:              icon,
                source:            .launchServices
            ), bundlePath: path)
        }

        // Level 4: BundleID 段词典
        if let name = appNameFromSegmentDictionary(key) {
            return (ResolvedAppIdentity(canonicalBundleID: key, displayName: name, source: .bundleDictionary),
                    bundlePath: nil)
        }

        // Level 5: CamelCase 拆分
        if let name = camelCaseName(from: key), name != key {
            return (ResolvedAppIdentity(canonicalBundleID: key, displayName: name, source: .camelCase),
                    bundlePath: nil)
        }

        // Level 6: 原始 bundleID 兜底
        return (.fallback(bundleID: raw), bundlePath: nil)
    }

    // MARK: - Level 3: NSWorkspace + Info.plist

    /// 返回 (displayName, icon, bundlePath)，bundlePath 供缓存重用。
    private func appNameAndIconFromLaunchServices(_ bundleID: String) -> (name: String, icon: NSImage?, path: String)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let path = url.path
        let icon = NSWorkspace.shared.icon(forFile: path)
        if let name = appNameFromInfoPlist(url: url), !name.isEmpty {
            return (name, icon, path)
        }
        let fsName = FileManager.default.displayName(atPath: path)
        let clean  = fsName.hasSuffix(".app") ? String(fsName.dropLast(4)) : fsName
        guard !clean.isEmpty else { return nil }
        return (clean, icon, path)
    }

    private func appNameFromInfoPlist(url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty { return name }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty { return name }
        return nil
    }

    /// 从已知 bundlePath 读取开发者信息（已有 URL，不再二次查询 LaunchServices）。
    private func developerFromBundle(bundlePath: String) -> String? {
        let url = URL(fileURLWithPath: bundlePath)
        guard let bundle = Bundle(url: url),
              let org = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        else { return nil }
        let stripped = org
            .replacingOccurrences(of: "Copyright", with: "")
            .replacingOccurrences(of: "©", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// 获取应用图标 + bundlePath（用于 Level 2 KnownApps）。
    private func appIconAndPath(for bundleID: String) -> (icon: NSImage, path: String)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return (NSWorkspace.shared.icon(forFile: url.path), url.path)
    }

    // MARK: - Level 4: 段词典

    private static let segmentDict: [String: String] = [
        // 腾讯
        "xin": "微信", "wechat": "WeChat", "xinwechat": "WeChat",
        "qq": "QQ", "qqmail": "QQ邮箱", "qqmusic": "QQ音乐",
        "tenvideo": "腾讯视频", "wemeet": "腾讯会议",
        "wetype": "腾讯文档", "enterprise": "企业微信",
        // 字节跳动
        "aweme": "抖音", "musically": "抖音", "toutiao": "今日头条",
        "xigua": "西瓜视频", "lark": "Lark", "feishu": "飞书",
        "capcut": "剪映", "coze": "扣子", "keeta": "Keeta",
        // 阿里
        "taobao": "淘宝", "alipay": "支付宝", "dingtalk": "钉钉",
        "youku": "优酷",
        // 百度
        "baiduapp": "百度", "netdisk": "百度网盘", "tieba": "百度贴吧",
        // 国内其他
        "bilibili": "哔哩哔哩", "danmaku": "哔哩哔哩",
        "douyin": "抖音", "kuaishou": "快手", "weibo": "微博",
        "zhihu": "知乎", "pinduoduo": "拼多多",
        "cloudmusic": "网易云音乐", "imeituan": "美团",
        "discover": "小红书",
        // 国际
        "spotify": "Spotify", "discord": "Discord", "telegram": "Telegram",
        "signal": "Signal", "slack": "Slack", "zoom": "Zoom",
        "notion": "Notion", "figma": "Figma", "firefox": "Firefox",
        "chrome": "Chrome", "safari": "Safari", "outlook": "Outlook",
        "teams": "Microsoft Teams", "onedrive": "OneDrive",
        "dropbox": "Dropbox", "netflix": "Netflix", "youtube": "YouTube",
        "instagram": "Instagram", "whatsapp": "WhatsApp",
        "facebook": "Facebook", "messenger": "Messenger",
        "reddit": "Reddit", "snapchat": "Snapchat", "tiktok": "TikTok",
        "twitter": "X (Twitter)", "chatgpt": "ChatGPT", "claude": "Claude",
    ]

    private func appNameFromSegmentDictionary(_ bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        for seg in parts.reversed() {
            let s = String(seg)
            if !s.allSatisfy(\.isNumber), s.count > 2,
               let name = Self.segmentDict[s] { return name }
        }
        return nil
    }

    // MARK: - Level 5: CamelCase 拆分

    private func camelCaseName(from bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        let rawSeg: String
        if let last = parts.last, !last.allSatisfy(\.isNumber), last.count > 2 {
            rawSeg = String(last)
        } else if parts.count >= 2 {
            rawSeg = String(parts[parts.count - 2])
        } else {
            return nil
        }
        let spaced = rawSeg
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        var expanded = ""
        var prevWasLower = false
        for ch in spaced {
            if ch.isUppercase && prevWasLower && !expanded.isEmpty && expanded.last != " " {
                expanded.append(" ")
            }
            expanded.append(ch)
            prevWasLower = ch.isLowercase
        }
        let words = expanded
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    // MARK: - 磁盘缓存 I/O

    private func loadDiskCache() {
        guard let url  = diskCacheURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: CachedIdentity].self, from: data)
        else { return }
        // 过滤掉过期条目，避免启动时加载大量废旧数据
        diskCache = dict.filter { !$0.value.isExpired }
        let expired = dict.count - diskCache.count
        if expired > 0 {
            Logger.resolver.info("磁盘缓存已清理 \(expired, privacy: .public) 条过期记录")
        }
    }

    /// 异步快照写盘（不阻塞调用方）。
    private func saveDiskCacheAsync() {
        let snapshot = cacheLock.withLock { diskCache }
        saveQueue.async { [weak self] in
            self?.writeDiskCache(snapshot)
        }
    }

    private func writeDiskCache(_ snapshot: [String: CachedIdentity]) {
        guard let url = diskCacheURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            Logger.resolver.debug("磁盘缓存写入: \(snapshot.count, privacy: .public) 条")
        } catch {
            Logger.resolver.error("磁盘缓存写入失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 用户覆盖 I/O

    private func loadUserOverrides() {
        guard let url  = overridesURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        userOverrides = dict
    }

    private func saveUserOverrides() {
        guard let url = overridesURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(userOverrides)
            try data.write(to: url, options: .atomic)
        } catch { /* 写入失败不影响主功能 */ }
    }
}

// MARK: - NSLock 便利扩展

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
