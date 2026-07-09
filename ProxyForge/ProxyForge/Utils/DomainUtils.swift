import Foundation

// MARK: - 域名工具函数

/// 判断字符串是否为 IP 地址（IPv4 或 IPv6）
func isIPAddress(_ s: String) -> Bool {
    let ipv4 = s.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
    return ipv4 || s.contains(":")
}

/// 提取根域名，例如 api.example.com → example.com
func rootDomain(_ domain: String) -> String {
    let parts = domain.split(separator: ".")
    guard parts.count >= 2 else { return domain }
    return parts.suffix(2).joined(separator: ".")
}

/// 从 Bundle ID 推导可读名称。
/// 委托给 AppIdentityResolver，解析链：
///   用户覆盖 → KnownApps → NSWorkspace → Info.plist → 段词典 → CamelCase → 原始 bundleID
func deriveName(from bundleID: String) -> String {
    AppIdentityResolver.shared.resolve(bundleID)
}
