import Foundation
import Combine

// MARK: - 用户设置（持久化）

/// 封装所有用户偏好，通过 UserDefaults 跨启动持久化。
/// 作为 @EnvironmentObject 注入整个 View 层级。
final class UserSettings: ObservableObject {

    // ── 持久化字段 ────────────────────────────────────────────────────────────

    @Published var filterSystem: Bool {
        didSet { save(filterSystem, forKey: .filterSystem) }
    }
    @Published var mergeSub: Bool {
        didSet { save(mergeSub, forKey: .mergeSub) }
    }
    @Published var proxyName: String {
        didSet { save(proxyName, forKey: .proxyName) }
    }
    @Published var formatterIdx: Int {
        didSet { save(formatterIdx, forKey: .formatterIdx) }
    }
    @Published var includeIPs: Bool {
        didSet { save(includeIPs, forKey: .includeIPs) }
    }
    /// 规则预览 / 导出时只保留该 App 独占的域名（共享域名不输出）
    @Published var exclusiveOnly: Bool {
        didSet { save(exclusiveOnly, forKey: .exclusiveOnly) }
    }

    // ── 初始化（从 UserDefaults 读取，不存在则用默认值）──────────────────────

    init() {
        let d = UserDefaults.standard
        filterSystem  = d.object(forKey: Key.filterSystem.rawValue)  as? Bool   ?? true
        mergeSub      = d.object(forKey: Key.mergeSub.rawValue)      as? Bool   ?? false
        proxyName     = d.string(forKey: Key.proxyName.rawValue)                ?? ""
        formatterIdx  = d.object(forKey: Key.formatterIdx.rawValue)  as? Int    ?? 0
        includeIPs    = d.object(forKey: Key.includeIPs.rawValue)    as? Bool   ?? true
        exclusiveOnly = d.object(forKey: Key.exclusiveOnly.rawValue) as? Bool   ?? false
    }

    // ── 键名枚举 ──────────────────────────────────────────────────────────────

    private enum Key: String {
        case filterSystem, mergeSub, proxyName, formatterIdx, includeIPs, exclusiveOnly
    }

    private func save<T>(_ value: T, forKey key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}
