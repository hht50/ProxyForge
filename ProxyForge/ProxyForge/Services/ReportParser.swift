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

// MARK: - 多文件并发解析 + 合并

/// 并发解析多个 NDJSON 文件，将结果按 bundleID 合并：
/// - 相同 bundleID + domain 的 hits **求和**
/// - totalHits 由合并后的 domains 字典重新推导，保证一致性
///
/// - Parameters:
///   - urls:         指向多个 `App_Privacy_Report_v4_*.ndjson` 文件的 URL 数组
///   - filterSystem: 若为 `true`，则跳过所有 `com.apple.*` 条目
/// - Returns: 按 totalHits 降序排列的合并结果
func parseReports(urls: [URL], filterSystem: Bool) async throws -> [AppEntry] {
    guard !urls.isEmpty else { return [] }
    Logger.parser.info("并发解析 \(urls.count, privacy: .public) 个文件")

    // ── 1. 并发解析，每个文件在独立任务中运行 ──────────────────────────────
    let partials: [[AppEntry]] = try await withThrowingTaskGroup(of: [AppEntry].self) { group in
        for url in urls {
            group.addTask { try parseReport(url: url, filterSystem: filterSystem) }
        }
        var collected: [[AppEntry]] = []
        collected.reserveCapacity(urls.count)
        for try await batch in group { collected.append(batch) }
        return collected
    }

    // ── 2. 合并：按 bundleID 聚合，domain hits 求和 ──────────────────────────
    // 用元组做可变的中间结构，避免额外的 class 分配
    struct Slot {
        var name:    String
        var domains: [String: DomainInfo]
    }
    var acc: [String: Slot] = Dictionary(minimumCapacity: partials.reduce(0) { $0 + $1.count })

    for entries in partials {
        for entry in entries {
            if var slot = acc[entry.bundleID] {
                // 合并 domains：相同域名 hits 相加，其余字段取最新非空值
                for (dom, info) in entry.domains {
                    if let existing = slot.domains[dom] {
                        slot.domains[dom] = DomainInfo(
                            hits:       existing.hits + info.hits,
                            domainType: info.domainType != 0 ? info.domainType : existing.domainType,
                            owner:      info.owner.isEmpty   ? existing.owner  : info.owner
                        )
                    } else {
                        slot.domains[dom] = info
                    }
                }
                acc[entry.bundleID] = slot
            } else {
                acc[entry.bundleID] = Slot(name: entry.name, domains: entry.domains)
            }
        }
    }

    // ── 3. 转换为 AppEntry，totalHits 由合并后的 domains 重新推导 ───────────
    let result = acc.map { bid, slot in
        let totalHits = slot.domains.values.reduce(0) { $0 + $1.hits }
        return AppEntry(id: bid, name: slot.name, domains: slot.domains, totalHits: totalHits)
    }.sorted(by: >)

    Logger.parser.info("合并完成: \(result.count, privacy: .public) 个应用 (来自 \(urls.count, privacy: .public) 个文件)")
    return result
}
