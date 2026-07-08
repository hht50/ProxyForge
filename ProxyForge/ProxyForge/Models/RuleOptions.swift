import Foundation

// MARK: - 规则生成选项

struct RuleOptions {
    /// 是否将子域合并为根域（api.x.com → DOMAIN-SUFFIX,x.com）
    var mergeSub:     Bool        = false
    /// 导出规则中的策略名称；空字符串表示不附加策略
    var proxyTarget:  String      = ""
    /// 是否在规则中包含 IP-CIDR 条目
    var includeIPs:   Bool        = true
    /// 被 ≥2 个 App 使用的域名集合；非空时 formatOne 将共享域名置于注释区
    var sharedDomains: Set<String> = []
}
