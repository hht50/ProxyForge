import Foundation

// MARK: - 规则生成选项

struct RuleOptions {
    /// 是否将子域合并为根域（api.x.com → DOMAIN-SUFFIX,x.com）
    var mergeSub:    Bool   = true
    /// 导出规则中的策略名称（例如 "Proxy" / "PROXY"）
    var proxyTarget: String = "Proxy"
    /// 是否在规则中包含 IP-CIDR 条目
    var includeIPs:  Bool   = true
}
