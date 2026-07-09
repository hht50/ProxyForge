import Foundation

// MARK: - 规则优化等级

/// 控制导出规则时的过滤与合并策略。
enum OptimizationLevel: Int, CaseIterable {
    case raw     = 0  // 原始导出：保留所有域名/IP，不做任何过滤
    case smart   = 1  // 智能优化：过滤 Fake-IP / 私有 IP / 代理服务域名（推荐）
    case minimal = 2  // 极简规则：智能优化 + 合并至根域名（CDN 折叠）

    var displayName: String {
        switch self {
        case .raw:     return "原始"
        case .smart:   return "智能"
        case .minimal: return "极简"
        }
    }

    var helpText: String {
        switch self {
        case .raw:
            return "保留所有域名和 IP，不做任何过滤"
        case .smart:
            return "自动过滤 Fake-IP (198.18/15)、局域网 IP、代理工具自身域名"
        case .minimal:
            return "在智能优化基础上，将子域名合并为根域名（CDN 折叠），规则数量最少"
        }
    }
}

// MARK: - 规则生成选项

struct RuleOptions {
    /// 是否将子域合并为根域（api.x.com → x.com）；minimal 级别自动开启
    var mergeSub:          Bool             = false
    /// 导出规则中的策略名称；空字符串表示不附加策略
    var proxyTarget:       String           = ""
    /// 是否在规则中包含 IP-CIDR 条目
    var includeIPs:        Bool             = true
    /// 被 ≥2 个 App 使用的域名集合；formatOne 预览时将共享域名置于注释区
    var sharedDomains:     Set<String>      = []
    /// 规则优化等级：控制 Fake-IP/私有 IP 过滤与 CDN 折叠
    var optimizationLevel: OptimizationLevel = .smart
    /// 导出类型名称，用于文件头注释（"Unique Domains" / "All Domains"）
    var exportTypeName:    String           = "Unique Domains"
}
