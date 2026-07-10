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
    let exclusive: [String]    // 独有域名规则前缀（不含策略）
    let shared:    [String]    // 共享域名规则前缀（不含策略）
    let ips:       [String]    // IP 规则前缀（不含策略）
}

// MARK: - 规则统计

struct RuleStats {
    let uniqueCount:   Int
    let sharedCount:   Int
    let ipCount:       Int
    let totalRequests: Int

    var totalDomains: Int { uniqueCount + sharedCount }
}

// MARK: - 核心规则构建（含优化等级过滤）

private func buildSplitRules(
    app:          AppEntry,
    options:      RuleOptions,
    domainPrefix: String,
    ipv4Prefix:   String,
    ipv6Prefix:   String
) -> SplitRules {
    let level     = options.optimizationLevel
    // minimal 级别隐式开启 mergeSub
    let doMerge   = options.mergeSub || level == .minimal
    let sharedSet = options.sharedDomains

    var exclusiveDoms: [String]        = []
    var sharedDoms:    [String]        = []
    var ipRules:       [(String, Int)] = []

    if doMerge {
        // 合并子域：先计算根域 hits，再判断是否在共享集
        var rootHits:   [String: Int]  = [:]
        var rootShared: Set<String>    = []
        for (dom, info) in app.domains {
            if isIPAddress(dom) {
                if !shouldFilter(dom, level: level) {
                    ipRules.append((dom, info.hits))
                }
            } else {
                if shouldFilter(dom, level: level) { continue }
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
                if !shouldFilter(dom, level: level) {
                    ipRules.append((dom, info.hits))
                }
            } else {
                if shouldFilter(dom, level: level) { continue }
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

/// 统计一次 split 的域名/IP 数量
private func makeStats(_ split: SplitRules, totalRequests: Int) -> RuleStats {
    RuleStats(
        uniqueCount:   split.exclusive.count,
        sharedCount:   split.shared.count,
        ipCount:       split.ips.count,
        totalRequests: totalRequests
    )
}

// MARK: - 策略后缀辅助

private extension String {
    /// ",策略名"；空目标时返回空字符串
    func proxySuffix() -> String { isEmpty ? "" : ",\(self)" }
}

// MARK: - 文件头（per-app block header）

/// width=60 的分隔线（不含前缀 "# "）
private let hRule = String(repeating: "=", count: 60)

private func appBlockHeader(
    app:      AppEntry,
    stats:    RuleStats,
    options:  RuleOptions,
    prefix:   String       // Clash 用 "  ", 其他用 ""
) -> String {
    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
    let now = fmt.string(from: Date())

    // 右对齐数字时对齐宽度
    let rows: [(String, String)] = [
        ("Application", app.name),
        ("Bundle ID",   app.bundleID),
        ("Export Type", options.exportTypeName),
        ("Export Time", now),
    ]

    var lines: [String] = []
    let p = prefix + "# "

    lines.append(prefix + "# \(hRule)")
    for (k, v) in rows {
        lines.append("\(p)\(k.padding(toLength: 12, withPad: " ", startingAt: 0)) : \(v)")
    }
    lines.append(p)
    lines.append("\(p)Domains")
    lines.append("\(p)  Total   : \(stats.totalDomains)")
    lines.append("\(p)  Unique  : \(stats.uniqueCount)")
    lines.append("\(p)  Shared  : \(stats.sharedCount)")
    lines.append(p)
    lines.append("\(p)Requests  : \(stats.totalRequests)")
    lines.append(prefix + "# \(hRule)")
    return lines.joined(separator: "\n")
}

// MARK: - 文件尾统计（formatAll 使用）

private func fileSummaryFooter(apps: [AppEntry], allStats: [RuleStats]) -> String {
    let totalDoms = allStats.reduce(0) { $0 + $1.totalDomains }
    let unique    = allStats.reduce(0) { $0 + $1.uniqueCount  }
    let shared    = allStats.reduce(0) { $0 + $1.sharedCount  }
    let ips       = allStats.reduce(0) { $0 + $1.ipCount      }
    let reqs      = allStats.reduce(0) { $0 + $1.totalRequests}
    let lines: [String] = [
        "# \(hRule)",
        "# Export Summary",
        "#",
        "#   Apps     : \(apps.count)",
        "#   Domains  : \(totalDoms)",
        "#   Unique   : \(unique)",
        "#   Shared   : \(shared)",
        "#   IPs      : \(ips)",
        "#   Requests : \(reqs)",
        "# \(hRule)",
    ]
    return lines.joined(separator: "\n")
}

// MARK: - 全文件头（formatAll 使用）

private func fileHeader(tool: String) -> String {
    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
    return """
    # \(hRule)
    # \(tool) Rule Set
    # Generated by ProxyForge from iOS App Privacy Report
    # \(fmt.string(from: Date()))
    # \(hRule)
    """
}

// MARK: - 通用块构建（Loon/Surge/QX 风格）

/// 构建单个 App 的规则块文本（含 header、各 section、不含尾部空行）。
/// `ruleMap` 将规则前缀行转换为最终输出行。
private func buildPlainBlock(
    app:      AppEntry,
    options:  RuleOptions,
    split:    SplitRules,
    stats:    RuleStats,
    ruleMap:  (String) -> String
) -> String {
    let header = appBlockHeader(app: app, stats: stats, options: options, prefix: "")
    var lines = [header, ""]

    if !split.exclusive.isEmpty {
        lines.append("# ===== Unique Domains =====")
        lines.append(contentsOf: split.exclusive.map(ruleMap))
        lines.append("")
    }
    if !split.shared.isEmpty {
        lines.append("# ===== Shared Domains =====")
        lines.append(contentsOf: split.shared.map(ruleMap))
        lines.append("")
    }
    if !split.ips.isEmpty {
        lines.append("# ===== IP Rules =====")
        lines.append(contentsOf: split.ips.map(ruleMap))
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

// MARK: - Loon

struct LoonFormatter: RuleFormatter {
    let displayName   = "Loon"
    let fileExtension = "txt"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let split = buildSplitRules(app: app, options: options,
                                    domainPrefix: "DOMAIN-SUFFIX",
                                    ipv4Prefix:   "IP-CIDR",
                                    ipv6Prefix:   "IP-CIDR6")
        let stats = makeStats(split, totalRequests: app.totalHits)
        let t     = options.proxyTarget.proxySuffix()

        // 预览模式：sharedDomains 非空时，共享域名以注释显示（便于识别）
        if !options.sharedDomains.isEmpty {
            let header = appBlockHeader(app: app, stats: stats, options: options, prefix: "")
            var lines  = [header, ""]
            if !split.exclusive.isEmpty {
                lines.append("# ===== Unique Domains =====")
                lines += split.exclusive.map { "\($0)\(t)" }
                lines.append("")
            }
            if !split.shared.isEmpty {
                lines.append("# ===== Shared Domains (commented — enable in options) =====")
                lines += split.shared.map { "# \($0)\(t)" }
                lines.append("")
            }
            if !split.ips.isEmpty {
                lines.append("# ===== IP Rules =====")
                lines += split.ips.map { "\($0)\(t)" }
                lines.append("")
            }
            return lines.joined(separator: "\n")
        }

        // 导出模式：所有域名均为活跃规则
        return buildPlainBlock(app: app, options: options, split: split, stats: stats) { "\($0)\(t)" }
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        var allStats: [RuleStats] = []
        let body = apps.map { app -> String in
            let split = buildSplitRules(app: app, options: options,
                                        domainPrefix: "DOMAIN-SUFFIX",
                                        ipv4Prefix:   "IP-CIDR",
                                        ipv6Prefix:   "IP-CIDR6")
            let s = makeStats(split, totalRequests: app.totalHits)
            allStats.append(s)
            return formatOne(app: app, options: options)
        }.joined(separator: "\n")

        return fileHeader(tool: displayName)
            + "\n[Rule]\n\n"
            + body
            + "\n\n" + fileSummaryFooter(apps: apps, allStats: allStats) + "\n"
    }
}

// MARK: - Surge（语法与 Loon 相同）

struct SurgeFormatter: RuleFormatter {
    let displayName   = "Surge"
    let fileExtension = "txt"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        LoonFormatter().formatOne(app: app, options: options)
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        var allStats: [RuleStats] = []
        let body = apps.map { app -> String in
            let split = buildSplitRules(app: app, options: options,
                                        domainPrefix: "DOMAIN-SUFFIX",
                                        ipv4Prefix:   "IP-CIDR",
                                        ipv6Prefix:   "IP-CIDR6")
            allStats.append(makeStats(split, totalRequests: app.totalHits))
            return formatOne(app: app, options: options)
        }.joined(separator: "\n")

        return fileHeader(tool: displayName)
            + "\n[Rule]\n\n"
            + body
            + "\n\n" + fileSummaryFooter(apps: apps, allStats: allStats) + "\n"
    }
}

// MARK: - Quantumult X

struct QuantumultXFormatter: RuleFormatter {
    let displayName   = "Quantumult X"
    let fileExtension = "txt"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let t     = options.proxyTarget.lowercased().proxySuffix()
        let split = buildSplitRules(app: app, options: options,
                                    domainPrefix: "host-suffix",
                                    ipv4Prefix:   "ip-cidr",
                                    ipv6Prefix:   "ip6-cidr")
        let stats = makeStats(split, totalRequests: app.totalHits)

        func qxLine(_ prefix: String) -> String {
            let parts = prefix.split(separator: ",", maxSplits: 1)
            return parts.count == 2 ? "\(parts[0]), \(parts[1])\(t)" : "\(prefix)\(t)"
        }

        if !options.sharedDomains.isEmpty {
            let header = appBlockHeader(app: app, stats: stats, options: options, prefix: "")
            var lines  = [header, ""]
            if !split.exclusive.isEmpty {
                lines.append("# ===== Unique Domains =====")
                lines += split.exclusive.map(qxLine)
                lines.append("")
            }
            if !split.shared.isEmpty {
                lines.append("# ===== Shared Domains (commented) =====")
                lines += split.shared.map { "# \(qxLine($0))" }
                lines.append("")
            }
            if !split.ips.isEmpty {
                lines.append("# ===== IP Rules =====")
                lines += split.ips.map(qxLine)
                lines.append("")
            }
            return lines.joined(separator: "\n")
        }

        return buildPlainBlock(app: app, options: options, split: split, stats: stats, ruleMap: qxLine)
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        var allStats: [RuleStats] = []
        let body = apps.map { app -> String in
            let split = buildSplitRules(app: app, options: options,
                                        domainPrefix: "host-suffix",
                                        ipv4Prefix:   "ip-cidr",
                                        ipv6Prefix:   "ip6-cidr")
            allStats.append(makeStats(split, totalRequests: app.totalHits))
            return formatOne(app: app, options: options)
        }.joined(separator: "\n")

        return fileHeader(tool: displayName) + "\n"
            + body
            + "\n\n" + fileSummaryFooter(apps: apps, allStats: allStats) + "\n"
    }
}

// MARK: - Clash / ClashX（YAML）

struct ClashFormatter: RuleFormatter {
    let displayName   = "Clash"
    let fileExtension = "txt"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let t     = options.proxyTarget.proxySuffix()
        let split = buildSplitRules(app: app, options: options,
                                    domainPrefix: "DOMAIN-SUFFIX",
                                    ipv4Prefix:   "IP-CIDR",
                                    ipv6Prefix:   "IP-CIDR6")
        let stats  = makeStats(split, totalRequests: app.totalHits)
        let header = appBlockHeader(app: app, stats: stats, options: options, prefix: "  ")
        var lines  = ["  \(header.components(separatedBy: "\n").joined(separator: "\n  "))", ""]

        if !split.exclusive.isEmpty {
            lines.append("  # ===== Unique Domains =====")
            lines += split.exclusive.map { "  - \($0)\(t)" }
            lines.append("")
        }

        if !split.shared.isEmpty {
            if !options.sharedDomains.isEmpty {
                // 预览：注释
                lines.append("  # ===== Shared Domains (commented) =====")
                lines += split.shared.map { "  # - \($0)\(t)" }
            } else {
                // 导出：活跃规则
                lines.append("  # ===== Shared Domains =====")
                lines += split.shared.map { "  - \($0)\(t)" }
            }
            lines.append("")
        }

        if !split.ips.isEmpty {
            lines.append("  # ===== IP Rules =====")
            lines += split.ips.map { "  - \($0)\(t)" }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func formatAll(apps: [AppEntry], options: RuleOptions) -> String {
        var allStats: [RuleStats] = []
        let body = apps.map { app -> String in
            let split = buildSplitRules(app: app, options: options,
                                        domainPrefix: "DOMAIN-SUFFIX",
                                        ipv4Prefix:   "IP-CIDR",
                                        ipv6Prefix:   "IP-CIDR6")
            allStats.append(makeStats(split, totalRequests: app.totalHits))
            return formatOne(app: app, options: options)
        }.joined(separator: "\n")

        return fileHeader(tool: displayName)
            + "\nrules:\n\n"
            + body
            + "\n\n" + fileSummaryFooter(apps: apps, allStats: allStats).components(separatedBy: "\n").map { "  \($0)" }.joined(separator: "\n") + "\n"
    }
}
