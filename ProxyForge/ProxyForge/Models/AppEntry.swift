import Foundation

// MARK: - 数据模型

struct DomainInfo: Equatable {
    let hits:       Int
    let domainType: Int    // 1 = 第一方, 2 = 第三方
    let owner:      String
}

struct AppEntry: Identifiable, Equatable, Comparable {
    let id:    String             // 规范化 bundleID（已剥离 .helper/.xpc 等后缀）
    var name:  String
    var domains: [String: DomainInfo]
    var totalHits: Int

    /// 完整应用身份（包含开发者、分类、图标、置信度等），由 ReportParser 填充。
    var identity: ResolvedAppIdentity?

    var bundleID:    String { id }
    var domainCount: Int    { domains.count }
    var ipCount:     Int    { domains.keys.filter { $0.contains(":") || $0.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil }.count }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    static func <  (lhs: Self, rhs: Self) -> Bool { lhs.totalHits < rhs.totalHits }
}
