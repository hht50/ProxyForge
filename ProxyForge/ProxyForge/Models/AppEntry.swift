import Foundation

// MARK: - 数据模型

struct DomainInfo: Equatable {
    let hits:       Int
    let domainType: Int    // 1 = 第一方, 2 = 第三方
    let owner:      String
}

struct AppEntry: Identifiable, Equatable, Comparable {
    let id:    String             // bundleID 作为唯一标识
    var name:  String
    var domains: [String: DomainInfo]
    var totalHits: Int

    var bundleID:    String { id }
    var domainCount: Int    { domains.count }
    var ipCount:     Int    { domains.keys.filter { $0.contains(":") || $0.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil }.count }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    static func <  (lhs: Self, rhs: Self) -> Bool { lhs.totalHits < rhs.totalHits }
}
