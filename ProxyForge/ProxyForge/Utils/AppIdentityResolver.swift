import Foundation
import AppKit

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
// BundleID 规范化在所有解析之前执行：
//   剥离 .helper / .xpc / .service / .plugin / .extension / .agent 等后缀，
//   使 com.tencent.xin.helper 和 com.tencent.xin 合并到同一个条目。

final class AppIdentityResolver {

    // MARK: - Singleton
    static let shared = AppIdentityResolver()

    // MARK: - Cache：normalized bundleID → ResolvedAppIdentity
    private var cache: [String: ResolvedAppIdentity] = [:]
    private let cacheLock = NSLock()

    // MARK: - 用户覆盖（normalized bundleID → 自定义名称）
    private var userOverrides: [String: String] = [:]

    private var overridesURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ProxyForge/UserOverrideApps.json")
    }

    private init() {
        loadUserOverrides()
    }

    // MARK: - 用户覆盖 API

    /// 添加或更新用户自定义名称（持久化到磁盘，下次启动自动加载）。
    func setUserOverride(bundleID: String, name: String) {
        let key = normalize(bundleID)
        userOverrides[key] = name
        // 用新名称更新（或写入）缓存
        let identity = ResolvedAppIdentity.userOverride(bundleID: key, name: name)
        cacheLock.withLock { cache[key] = identity }
        saveUserOverrides()
    }

    /// 删除一条用户自定义覆盖。
    func removeUserOverride(bundleID: String) {
        let key = normalize(bundleID)
        userOverrides.removeValue(forKey: key)
        cacheLock.withLock { cache.removeValue(forKey: key) }
        saveUserOverrides()
    }

    /// 当前所有用户覆盖（规范化 bundleID → 自定义名称）。
    var allUserOverrides: [String: String] { userOverrides }

    private func loadUserOverrides() {
        guard let url = overridesURL,
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
        while let last = parts.last, stripped.contains(String(last)) {
            parts.removeLast()
        }
        let result = parts.joined(separator: ".")
        return result.isEmpty ? lowered : result
    }

    // MARK: - 主解析入口

    /// 解析 bundleID，返回完整的应用身份（名称、开发者、分类、图标、置信度）。
    /// 结果会缓存，相同 bundleID 只解析一次。
    func resolveIdentity(_ rawBundleID: String) -> ResolvedAppIdentity {
        let key = normalize(rawBundleID)
        if let cached = cacheLock.withLock({ cache[key] }) { return cached }
        let result = resolveUncached(key: key, raw: rawBundleID)
        cacheLock.withLock { cache[key] = result }
        return result
    }

    /// 便利方法：只需要显示名称时使用。
    func resolve(_ rawBundleID: String) -> String {
        resolveIdentity(rawBundleID).displayName
    }

    // MARK: - 解析链（内部）

    private func resolveUncached(key: String, raw: String) -> ResolvedAppIdentity {

        // Level 1: 用户自定义覆盖
        if let name = userOverrides[key] {
            return ResolvedAppIdentity.userOverride(bundleID: key, name: name)
        }

        // Level 2: KnownApps 静态数据库
        if let name = KnownApps.displayName(for: key) {
            return ResolvedAppIdentity(
                canonicalBundleID: key,
                displayName:       name,
                developer:         KnownApps.developer(for: key),
                category:          KnownApps.category(for: key),
                icon:              appIcon(for: key),
                source:            .knownApps
            )
        }

        // Level 3: NSWorkspace LaunchServices + Info.plist
        if let (name, icon) = appNameAndIconFromLaunchServices(key) {
            return ResolvedAppIdentity(
                canonicalBundleID: key,
                displayName:       name,
                developer:         developerFromBundle(key),
                category:          nil,
                icon:              icon,
                source:            .launchServices
            )
        }

        // Level 4: BundleID 段词典
        if let name = appNameFromSegmentDictionary(key) {
            return ResolvedAppIdentity(
                canonicalBundleID: key,
                displayName:       name,
                source:            .bundleDictionary
            )
        }

        // Level 5: CamelCase 拆分
        if let name = camelCaseName(from: key), name != key {
            return ResolvedAppIdentity(
                canonicalBundleID: key,
                displayName:       name,
                source:            .camelCase
            )
        }

        // Level 6: 原始 bundleID 兜底
        return ResolvedAppIdentity.fallback(bundleID: raw)
    }

    // MARK: - Level 3: NSWorkspace + Info.plist

    private func appNameAndIconFromLaunchServices(_ bundleID: String) -> (name: String, icon: NSImage?)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        // 优先读 Info.plist 的 CFBundleDisplayName / CFBundleName
        if let name = appNameFromInfoPlist(url: url), !name.isEmpty {
            return (name, icon)
        }
        // 次选文件系统显示名
        let fsName = FileManager.default.displayName(atPath: url.path)
        let clean  = fsName.hasSuffix(".app") ? String(fsName.dropLast(4)) : fsName
        guard !clean.isEmpty else { return nil }
        return (clean, icon)
    }

    private func appNameFromInfoPlist(url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty { return name }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty { return name }
        return nil
    }

    private func developerFromBundle(_ bundleID: String) -> String? {
        guard let url  = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url),
              let org  = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        else { return nil }
        // "Copyright © 2024 Tencent..." → "Tencent..."（简单截取）
        let stripped = org
            .replacingOccurrences(of: "Copyright", with: "")
            .replacingOccurrences(of: "©", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
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
}

// MARK: - NSLock 便利扩展

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
