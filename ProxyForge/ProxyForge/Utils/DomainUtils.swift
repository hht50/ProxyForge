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
/// 优先级：① 静态查表（KnownApps） → ② CamelCase 拆分 → ③ 原始末段首字母大写
func deriveName(from bundleID: String) -> String {
    // ① 静态表命中（精确匹配，大小写不敏感）
    if let known = KnownApps.displayName(for: bundleID) { return known }

    // ② 取最后一个分段，去掉常见冗余后缀/前缀
    let segments = bundleID.split(separator: ".")
    // 跳过纯数字末段（如 com.company.app.1234）
    let raw: String
    if let last = segments.last, !last.allSatisfy(\.isNumber) {
        raw = String(last)
    } else if segments.count >= 2 {
        raw = String(segments[segments.count - 2])
    } else {
        return bundleID
    }

    // ③ 预处理：连字符 / 下划线 → 空格
    let spaced = raw
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")

    // ④ CamelCase 拆分：在小写→大写边界插入空格
    //    例：MyGreatApp → My Great App
    var expanded = ""
    var prevWasLower = false
    for ch in spaced {
        if ch.isUppercase && prevWasLower && !expanded.isEmpty && expanded.last != " " {
            expanded.append(" ")
        }
        expanded.append(ch)
        prevWasLower = ch.isLowercase
    }

    // ⑤ 每个单词首字母大写，过滤空串
    let words = expanded
        .split(separator: " ", omittingEmptySubsequences: true)
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }

    return words.isEmpty ? bundleID : words.joined(separator: " ")
}
