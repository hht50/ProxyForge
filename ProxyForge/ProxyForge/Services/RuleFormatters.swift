import Foundation

// MARK: - 规则格式协议

protocol RuleFormatter {
    var displayName:   String { get }
    var fileExtension: String { get }
    func formatAll(apps: [AppEntry], options: RuleOptions) -> String
    func formatOne(app:  AppEntry,   options: RuleOptions) -> String
}

// MARK: - 格式注册表

let allFormatters: [any RuleFormatter] = [
    LoonFormatter(),
    SurgeFormatter(),
    QuantumultXFormatter(),
    ClashFormatter(),
]

// MARK: - 域名/IP 分组结果

private struct SplitRules {
    let exclusive: [String]   // 独占域名规则前缀（不含策略）
    let shared:    [String]   // 共享域名规则前缀（不含策略）
    let ips:       [String]   // IP 规则前缀（不含策略）
}

// MARK: - 共用规则构建（支持共享域名分组）

private func buildSplitRules(
    app:          AppEntry,
    options:      RuleOptions,
    domainPrefix: String,
    ipv4Prefix:   String,
    ipv6Prefix:   String
) -> SplitRules {
    var exclusiveDoms: [String]      = []
    var sharedDoms:    [String]      = []
    var ipRules:       [(String, Int)] = []
    let sharedSet = options.sharedDomains

    if options.mergeSub {
        // 合并子域：先计算根域 hits，再判断是否在共享集
        var rootHits:   [String: Int]  = [:]
        var rootShared: Set<String>    = []
        for (dom, info) in app.domains {
            if isIPAddress(dom) {
                ipRules.append((dom, info.hits))
            } else {
                let root = rootDomain(dom)
                rootHits[root, default: 0] += info.hits
                if sharedSet.contains(dom) { rootShared.insert(root) }
            }
        }
        for (root, _) in rootHits.sorted(by: { $0.value > $1.value }) {
            let line = "\(domainPrefix),\(root)"
            if rootShared.contains(root) { sharedDoms.append(line) }
            else                         { exclusiveDoms.append(line) }
        }
    } else {
        for (dom, info) in app.domains.sorted(by: { $0.value.hits > $1.value.hits }) {
            if isIPAddress(dom) {
                ipRules.append((dom, info.hits))
            } else {
                let line = "\(domainPrefix),\(dom)"
                if sharedSet.contains(dom) { sharedDoms.append(line) }
                else                       { exclusiveDoms.append(line) }
            }
        }
    }

    guard options.includeIPs else {
        return SplitRules(exclusive: exclusiveDoms, shared: sharedDoms, ips: [])
    }
    let ipLines = ipRules.sorted { $0.1 > $1.1 }.map { ip, _ in
        ip.contains(":") ? "\(ipv6Prefix),\(ip)/128" : "\(ipv4Prefix),\(ip)/32"
    }
    return SplitRules(exclusive: exclusiveDoms, shared: sharedDoms, ips: ipLines)
}

/// 平铺版本（供 formatAll 使用，不区分共享/独占）
private func buildRules(
    app:          AppEntry,
    options:      RuleOptions,
    domainPrefix: String,
    ipv4Prefix:   String,
    ipv6Prefix:   String
) -> [String] {
    let s = buildSplitRules(app: app, options: options,
                            domainPrefix: domainPrefix,
                            ipv4Prefix: ipv4Prefix,
                            ipv6Prefix: ipv6Prefix)
    return s.exclusive + s.shared + s.ips
}

// MARK: - 策略后缀辅助

private extension String {
    /// ",策略名"；空目标时返回空字符串
    func proxySuffix() -> String { isEmpty ? "" : ",\(self)" }
}

// MARK: - 文件头

private func makeHeader(tool: String, count: Int) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm"
    return """
    # ============================================================
    # \(tool) 分流规则 — 由 iOS App 隐私报告生成
    # 生成时间: \(fmt.string(from: Date()))
    # 应用数量: \(count)
    # ============================================================
    """
}

// MARK: - 应用头注释（含共享/独占统计）

private func appHeader(app: AppEntry, sharedCount: Int) -> [String] {
    let exclusiveCount = app.domainCount - sharedCount
    let detail: String
    if sharedCount > 0 {
        detail = "域名数: \(app.domainCount)（独占 \(exclusiveCount)  共享 \(sharedCount)）   总访问: \(app.totalHits) 次"
    } else {
        detail = "域名数: \(app.domainCount)   总访问: \(app.totalHits) 次"
    }
    return [
        "# ── \(app.name)  (\(app.bundleID))",
        "# \(detail)",
    ]
}

// MARK: - Loon

struct LoonFormatter: RuleFormatter {
    let displayName   = "Loon"
    let fileExtension = "conf"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let t     = options.proxyTarget.proxySuffix()
        let split = buildSplitRules(app: app, options: options,
                                    domainPrefix: "DOMAIN-SUFFIX",
                                    ipv4Prefix:   "IP-CIDR",
                                    ipv6Prefix:   "IP-CIDR6")
        var lines = appHeader(app: app, sharedCount: split.shared.count)
        lines += split.exclusive.map { "\($0)\(t)" }
        lines += split.ips.map       { "\($0)\(t)" }
        if !split.shared.isEmpty {
            lines.append("")
            lines.append("# ── 共享域名（同时被其他 App 使用）──")
            lines += split.shared.map { "# \($0)\(t)" }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        makeHeader(tool: displayName, count: apps.count)
            + "\n[Rule]\n\n"
            + apps.map { formatOne(app: $0, options: options) }.joined(separator: "\n")
    }
}

// MARK: - Surge（语法与 Loon 相同）

struct SurgeFormatter: RuleFormatter {
    let displayName   = "Surge"
    let fileExtension = "conf"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        LoonFormatter().formatOne(app: app, options: options)
    }
    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        makeHeader(tool: displayName, count: apps.count)
            + "\n[Rule]\n\n"
            + apps.map { formatOne(app: $0, options: options) }.joined(separator: "\n")
    }
}

// MARK: - Quantumult X

struct QuantumultXFormatter: RuleFormatter {
    let displayName   = "Quantumult X"
    let fileExtension = "conf"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let t     = options.proxyTarget.lowercased()
        let proxy = t.proxySuffix()
        let split = buildSplitRules(app: app, options: options,
                                    domainPrefix: "host-suffix",
                                    ipv4Prefix:   "ip-cidr",
                                    ipv6Prefix:   "ip6-cidr")
        var lines = ["# \(app.name) (\(app.bundleID))"]
        // Quantumult X 格式：host-suffix, domain, policy
        lines += split.exclusive.map { r in
            let parts = r.split(separator: ",", maxSplits: 1)
            return parts.count == 2 ? "\(parts[0]), \(parts[1])\(proxy)" : "\(r)\(proxy)"
        }
        if options.includeIPs {
            lines += split.ips.map { r in
                let parts = r.split(separator: ",", maxSplits: 1)
                return parts.count == 2 ? "\(parts[0]), \(parts[1])\(proxy)" : "\(r)\(proxy)"
            }
        }
        if !split.shared.isEmpty {
            lines.append("")
            lines.append("# ── 共享域名 ──")
            lines += split.shared.map { r in
                let parts = r.split(separator: ",", maxSplits: 1)
                let rule  = parts.count == 2 ? "\(parts[0]), \(parts[1])\(proxy)" : "\(r)\(proxy)"
                return "# \(rule)"
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        makeHeader(tool: displayName, count: apps.count) + "\n"
            + apps.map { formatOne(app: $0, options: options) }.joined(separator: "\n")
    }
}

// MARK: - Clash / ClashX（YAML）

struct ClashFormatter: RuleFormatter {
    let displayName   = "Clash"
    let fileExtension = "yaml"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let t     = options.proxyTarget
        let proxy = t.proxySuffix()
        let split = buildSplitRules(app: app, options: options,
                                    domainPrefix: "DOMAIN-SUFFIX",
                                    ipv4Prefix:   "IP-CIDR",
                                    ipv6Prefix:   "IP-CIDR6")
        var lines = ["  # \(app.name) (\(app.bundleID))"]
        lines += split.exclusive.map { "  - \($0)\(proxy)" }
        if options.includeIPs {
            lines += split.ips.map   { "  - \($0)\(proxy)" }
        }
        if !split.shared.isEmpty {
            lines.append("  # ── 共享域名 ──")
            lines += split.shared.map { "  # - \($0)\(proxy)" }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        let header = makeHeader(tool: displayName, count: apps.count)
        let body   = apps.map { formatOne(app: $0, options: options) }.joined(separator: "\n")
        return "\(header)\nrules:\n\(body)"
    }
}
