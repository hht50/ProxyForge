import Foundation
import os.log

// MARK: - 报告解析器

/// 从 Apple App Privacy Report NDJSON 文件中解析 networkActivity 记录，
/// 并按 bundleID 聚合为 AppEntry 数组。
///
/// - Parameters:
///   - url:          指向 `App_Privacy_Report_v4_*.ndjson` 文件的 URL
///   - filterSystem: 若为 `true`，则跳过所有 `com.apple.*` 条目
/// - Returns: 按 totalHits 降序排列的 AppEntry 数组
/// - Throws: 文件读取或内容为空时抛出错误
func parseReport(url: URL, filterSystem: Bool) throws -> [AppEntry] {
    Logger.parser.info("开始解析: \(url.lastPathComponent, privacy: .public)")

    let content = try String(contentsOf: url, encoding: .utf8)

    // 与 NDJSON 中每行 JSON 对应的原始结构
    struct RawRecord: Decodable {
        let type:        String
        let bundleID:    String?
        let domain:      String?
        let hits:        Int?
        let domainOwner: String?
        let domainType:  Int?
    }

    struct Accumulator {
        var name:      String
        var domains:   [String: DomainInfo]
        var totalHits: Int
    }

    let decoder = JSONDecoder()
    var acc: [String: Accumulator] = [:]
    var skipped = 0

    for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
        guard
            let data = String(line).data(using: .utf8),
            let rec  = try? decoder.decode(RawRecord.self, from: data),
            rec.type == "networkActivity",
            let bid  = rec.bundleID,
            let dom  = rec.domain, !dom.isEmpty
        else { skipped += 1; continue }

        if filterSystem && bid.hasPrefix("com.apple.") { continue }

        let hits = rec.hits ?? 1
        let info = DomainInfo(
            hits:       hits,
            domainType: rec.domainType ?? 0,
            owner:      rec.domainOwner ?? ""
        )

        var entry = acc[bid] ?? Accumulator(name: deriveName(from: bid), domains: [:], totalHits: 0)
        entry.domains[dom]  = info
        entry.totalHits    += hits
        acc[bid] = entry
    }

    let result = acc.map { bid, a in
        AppEntry(id: bid, name: a.name, domains: a.domains, totalHits: a.totalHits)
    }.sorted(by: >)

    Logger.parser.info("解析完成: \(result.count, privacy: .public) 个应用, \(skipped, privacy: .public) 行跳过")
    return result
}
