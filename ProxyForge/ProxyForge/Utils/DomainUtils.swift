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

/// 从 Bundle ID 推导可读名称，例如 com.example.my-app → My App
func deriveName(from bundleID: String) -> String {
    guard let last = bundleID.split(separator: ".").last else { return bundleID }
    return last
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
