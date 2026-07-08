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

// MARK: - 共用域名/IP 规则构建

private func buildRules(
    app:          AppEntry,
    options:      RuleOptions,
    domainPrefix: String,
    ipv4Prefix:   String,
    ipv6Prefix:   String
) -> [String] {
    var domainRules: [String] = []
    var ipRules:     [(String, Int)] = []

    if options.mergeSub {
        var rootHits: [String: Int] = [:]
        for (dom, info) in app.domains {
            if isIPAddress(dom) {
                ipRules.append((dom, info.hits))
            } else {
                rootHits[rootDomain(dom), default: 0] += info.hits
            }
        }
        domainRules = rootHits
            .sorted { $0.value > $1.value }
            .map    { "\(domainPrefix),\($0.key)" }
    } else {
        for (dom, info) in app.domains.sorted(by: { $0.value.hits > $1.value.hits }) {
            if isIPAddress(dom) { ipRules.append((dom, info.hits)) }
            else { domainRules.append("\(domainPrefix),\(dom)") }
        }
    }

    guard options.includeIPs else { return domainRules }

    let ipLines = ipRules.sorted { $0.1 > $1.1 }.map { ip, _ in
        ip.contains(":") ? "\(ipv6Prefix),\(ip)/128" : "\(ipv4Prefix),\(ip)/32"
    }
    return domainRules + ipLines
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

// MARK: - Loon

struct LoonFormatter: RuleFormatter {
    let displayName   = "Loon"
    let fileExtension = "conf"

    func formatOne(app: AppEntry, options: RuleOptions) -> String {
        let t = options.proxyTarget
        var lines = [
            "# ── \(app.name)  (\(app.bundleID))",
            "# 域名数: \(app.domainCount)   总访问: \(app.totalHits) 次",
        ]
        lines += buildRules(app: app, options: options,
                            domainPrefix: "DOMAIN-SUFFIX",
                            ipv4Prefix:   "IP-CIDR",
                            ipv6Prefix:   "IP-CIDR6")
                 .map { "\($0),\(t)" }
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
        let t = options.proxyTarget.lowercased()
        var lines = ["# \(app.name) (\(app.bundleID))"]

        if options.mergeSub {
            var rootSet = Set<String>()
            for dom in app.domains.keys where !isIPAddress(dom) { rootSet.insert(rootDomain(dom)) }
            lines += rootSet.sorted().map { "host-suffix, \($0), \(t)" }
        } else {
            for dom in app.domains.keys.sorted() where !isIPAddress(dom) {
                lines.append("host-suffix, \(dom), \(t)")
            }
        }

        if options.includeIPs {
            for dom in app.domains.keys where isIPAddress(dom) {
                lines.append(dom.contains(":")
                    ? "ip6-cidr, \(dom)/128, \(t)"
                    : "ip-cidr, \(dom)/32, \(t)")
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
        let t = options.proxyTarget
        var lines = ["  # \(app.name) (\(app.bundleID))"]

        if options.mergeSub {
            var rootSet = Set<String>()
            for dom in app.domains.keys where !isIPAddress(dom) { rootSet.insert(rootDomain(dom)) }
            lines += rootSet.sorted().map { "  - DOMAIN-SUFFIX,\($0),\(t)" }
        } else {
            for dom in app.domains.keys.sorted() where !isIPAddress(dom) {
                lines.append("  - DOMAIN-SUFFIX,\(dom),\(t)")
            }
        }

        if options.includeIPs {
            for dom in app.domains.keys where isIPAddress(dom) {
                lines.append(dom.contains(":")
                    ? "  - IP-CIDR6,\(dom)/128,\(t)"
                    : "  - IP-CIDR,\(dom)/32,\(t)")
            }
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
