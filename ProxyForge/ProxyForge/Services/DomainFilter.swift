import Foundation

// MARK: - 域名 / IP 过滤器

/// 过滤代理工具、VPN、抓包软件及本地网络相关的无关域名和 IP。
/// 用于提高导出规则的准确性，排除非目标应用产生的噪音数据。

// MARK: - 已知代理 / VPN / 抓包工具 Bundle ID 列表

/// 自动过滤：这些工具自身产生的流量不属于目标应用逻辑
let proxyToolBundleIDs: Set<String> = [
    // Loon
    "org.loon.loon-ios", "com.loon.loon",
    // Surge
    "com.nssurge.surge-mac", "com.nssurge.surge",
    "me.lili.Surge4", "com.apple.Surge4",
    // Quantumult X
    "com.crossutility.quantumult-x",
    // Shadowrocket
    "com.liguangming.Shadowrocket",
    // Stash
    "com.nfbits.Stash",
    // Clash Verge / ClashX
    "com.zzzz.clash-verge", "com.metacubex.clash.verge",
    "io.dreamacro.clashx", "io.dreamacro.clash-premium",
    // Proxyman
    "com.proxyman.NSProxy", "com.ProxymanApp.proxyman",
    // Charles
    "com.xk72.charles",
    // Wireshark
    "org.wireshark.Wireshark",
    // Cloudflare WARP
    "com.cloudflare.1dot1dot1dot1",
    // VPN 类
    "com.nordvpn.macos", "com.nordvpn.NordVPN",
    "com.expressvpn.expressvpn",
    "com.privateinternetaccess.ios.PIA-VPN",
    "com.privateinternetaccess.vpn",
    "net.openvpn.connect.app",
    "com.kape.vpn",
    // WireGuard
    "com.wireguard.ios", "com.wireguard.macos",
]

// MARK: - 私有 / 保留 IP 检测

/// 返回 true 表示该地址为本地网络、回环、链路本地或 CGNAT 等无需代理的保留地址。
func isPrivateIP(_ address: String) -> Bool {
    if address.contains(":") { return isPrivateIPv6(address) }
    return isPrivateIPv4(address)
}

private func isPrivateIPv4(_ address: String) -> Bool {
    let octets = address.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    let (a, b) = (octets[0], octets[1])
    switch a {
    case 10:        return true                       // 10.0.0.0/8
    case 127:       return true                       // 127.0.0.0/8 loopback
    case 169:       return b == 254                   // 169.254.0.0/16 link-local
    case 172:       return (16...31).contains(b)      // 172.16.0.0/12
    case 192:       return b == 168                   // 192.168.0.0/16
    case 100:       return (64...127).contains(b)     // 100.64.0.0/10 CGNAT
    case 0:         return true                       // 0.0.0.0/8 保留
    case 240...255: return true                       // 240.0.0.0/4 保留
    default:        return false
    }
}

// MARK: - Fake-IP 检测（198.18.0.0/15）

/// Clash / Mihomo / Surge Fake-IP 地址段（198.18.0.0/15 = 198.18.x.x + 198.19.x.x）。
/// 这些 IP 由代理客户端在本地虚拟生成，写入规则集完全无意义。
func isFakeIP(_ address: String) -> Bool {
    guard !address.contains(":") else { return false }   // 仅 IPv4
    let octets = address.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else { return false }
    return octets[0] == 198 && (octets[1] == 18 || octets[1] == 19)
}

private func isPrivateIPv6(_ address: String) -> Bool {
    let lower = address.lowercased()
    return lower == "::1"             // loopback
        || lower.hasPrefix("fe80")    // fe80::/10 link-local
        || lower.hasPrefix("fc")      // fc00::/7 unique local
        || lower.hasPrefix("fd")
        || lower == "::"              // 未指定地址
}

// MARK: - 代理工具域名检测

/// 已知代理 / VPN 服务域名后缀
private let proxyServiceDomainSuffixes: [String] = [
    "cloudflare-dns.com", "cloudflare.com",
    "courier.push.apple.com",
    "wireguard.com",
]

/// 返回 true 表示该域名疑似来自代理工具自身流量，应过滤
func isProxyServiceDomain(_ domain: String) -> Bool {
    let lower = domain.lowercased()
    return proxyServiceDomainSuffixes.contains { lower == $0 || lower.hasSuffix(".\($0)") }
}

// MARK: - 优化等级过滤入口

/// 判断域名/IP 是否应根据指定优化等级被过滤掉。
/// - `.raw`  → 永不过滤
/// - `.smart` / `.minimal` → 过滤私有 IP + Fake-IP + 代理服务域名
func shouldFilter(_ entry: String, level: OptimizationLevel) -> Bool {
    guard level != .raw else { return false }
    if isIPAddress(entry) {
        return isPrivateIP(entry) || isFakeIP(entry)
    }
    return isProxyServiceDomain(entry)
}
