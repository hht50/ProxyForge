import Foundation
import os.log

// MARK: - 内部聚合结构
//
// 解析过程中只聚合原始数据（domains 字典），不预先推导名称或 identity。
// 所有 AppEntry 的构建都通过 buildAppEntries(from:) 统一走 AppIdentityResolver，
// 避免单文件 / 多文件两条路径产生不一致。

private struct AppSlot {
    var domains: [String: DomainInfo]
}

// MARK: - 统一 AppEntry 构建出口（并发解析 identity）

/// 将 bundleID → AppSlot 字典转换为按 totalHits 降序排列的 AppEntry 数组。
///
/// identity 解析使用 TaskGroup 并发执行：
/// - L1/L2 缓存命中时开销极低（μs 级）
/// - L3 NSWorkspace 冷路径时并发查询，100 个 App 约 50ms（vs 串行 ~1s）
private func buildAppEntries(from acc: [String: AppSlot]) async -> [AppEntry] {
    let bundleIDs = Array(acc.keys)

    // 并发解析所有 bundleID 的 identity
    let identities: [String: ResolvedAppIdentity] = await withTaskGroup(
        of: (String, ResolvedAppIdentity).self
    ) { group in
        for bid in bundleIDs {
            group.addTask {
                (bid, AppIdentityResolver.shared.resolveIdentity(bid))
            }
        }
        var result = [String: ResolvedAppIdentity](minimumCapacity: bundleIDs.count)
        for await (bid, identity) in group {
            result[bid] = identity
        }
        return result
    }

    return acc.map { bid, slot in
        let totalHits = slot.domains.values.reduce(0) { $0 + $1.hits }
        // identities[bid] は必ず存在するが safety fallback を残す
        let identity  = identities[bid] ?? AppIdentityResolver.shared.resolveIdentity(bid)
        return AppEntry(
            id:        bid,
            name:      identity.displayName,
            domains:   slot.domains,
            totalHits: totalHits,
            identity:  identity
        )
    }.sorted(by: >)
}

// MARK: - 单文件解析

/// 从 Apple App Privacy Report NDJSON 文件中解析 networkActivity 记录，
/// 并按 bundleID 聚合为 AppEntry 数组。
///
/// - Parameters:
///   - url:          指向 `App_Privacy_Report_v4_*.ndjson` 文件的 URL
///   - filterSystem: 若为 `true`，则跳过所有 `com.apple.*` 条目
/// - Returns: 按 totalHits 降序排列的 AppEntry 数组
/// - Throws: 文件读取或内容为空时抛出错误
func parseReport(url: URL, filterSystem: Bool) async throws -> [AppEntry] {
    Logger.parser.info("开始解析: \(url.lastPathComponent, privacy: .public)")

    let content = try String(contentsOf: url, encoding: .utf8)

    struct RawRecord: Decodable {
        let type:        String
        let bundleID:    String?
        let domain:      String?
        let hits:        Int?
        let domainOwner: String?
        let domainType:  Int?
    }

    let decoder = JSONDecoder()
    var acc: [String: AppSlot] = [:]
    var skipped = 0

    for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
        guard
            let data = String(line).data(using: .utf8),
            let rec  = try? decoder.decode(RawRecord.self, from: data),
            rec.type == "networkActivity",
            let bid  = rec.bundleID,
            let dom  = rec.domain, !dom.isEmpty
        else { skipped += 1; continue }

        // 规范化：剥离 .helper/.xpc/.service 等进程后缀，实现同 App 多进程自动合并
        let normalizedBID = AppIdentityResolver.shared.normalize(bid)

        if filterSystem && normalizedBID.hasPrefix("com.apple.") { continue }

        let hits = rec.hits ?? 1
        let info = DomainInfo(
            hits:       hits,
            domainType: rec.domainType ?? 0,
            owner:      rec.domainOwner ?? ""
        )

        var slot = acc[normalizedBID] ?? AppSlot(domains: [:])
        slot.domains[dom] = info
        acc[normalizedBID] = slot
    }

    // 并发解析所有 identity（L1→L2→L3 三级缓存，冷路径 NSWorkspace 并行执行）
    let result = await buildAppEntries(from: acc)

    Logger.parser.info("解析完成: \(result.count, privacy: .public) 个应用, \(skipped, privacy: .public) 行跳过")
    return result
}

// MARK: - 多文件并发解析 + 合并

/// 并发解析多个 NDJSON 文件，将结果按 bundleID 合并：
/// - 相同 bundleID + domain 的 hits **求和**
/// - totalHits 由合并后的 domains 字典重新推导，保证一致性
/// - identity 经 buildAppEntries 统一并发解析，与单文件路径行为一致
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
            group.addTask { try await parseReport(url: url, filterSystem: filterSystem) }
        }
        var collected: [[AppEntry]] = []
        collected.reserveCapacity(urls.count)
        for try await batch in group { collected.append(batch) }
        return collected
    }

    // ── 2. 合并：按 bundleID 聚合，domain hits 求和 ──────────────────────────
    var acc: [String: AppSlot] = Dictionary(minimumCapacity: partials.reduce(0) { $0 + $1.count })

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
                acc[entry.bundleID] = AppSlot(domains: entry.domains)
            }
        }
    }

    // ── 3. 统一出口：并发解析 identity（L1缓存命中为主，极低开销）─────────
    let result = await buildAppEntries(from: acc)

    Logger.parser.info("合并完成: \(result.count, privacy: .public) 个应用 (来自 \(urls.count, privacy: .public) 个文件)")
    return result
}
