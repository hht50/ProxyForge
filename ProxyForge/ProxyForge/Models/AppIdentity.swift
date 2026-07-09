import Foundation
import AppKit

// MARK: - Resolution Source

/// 记录应用身份是从哪一级解析出来的，便于调试和置信度展示。
enum ResolutionSource: String, Codable, CustomStringConvertible {
    case userOverride    = "用户自定义"
    case knownApps       = "内置数据库"
    case launchServices  = "系统查询"
    case bundleDictionary = "关键词推断"
    case camelCase       = "名称解析"
    case fallback        = "原始ID"

    var description: String { rawValue }

    /// 置信度：0.0 ~ 1.0
    var confidence: Double {
        switch self {
        case .userOverride:     return 1.00
        case .knownApps:        return 0.99
        case .launchServices:   return 0.97
        case .bundleDictionary: return 0.82
        case .camelCase:        return 0.58
        case .fallback:         return 0.20
        }
    }

    /// 置信度 ≥ 0.80 视为"已识别"，无需额外提示。
    var isIdentified: Bool { confidence >= 0.80 }

    /// UI 状态图标
    var sfSymbol: String {
        switch self {
        case .userOverride:     return "person.badge.key"
        case .knownApps:        return "checkmark.seal"
        case .launchServices:   return "checkmark.circle"
        case .bundleDictionary: return "questionmark.circle"
        case .camelCase:        return "questionmark.circle"
        case .fallback:         return "exclamationmark.triangle"
        }
    }
}

// MARK: - App Category

/// 应用分类，用于将来的分组、过滤和统计。
enum AppCategory: String, Codable, CaseIterable {
    case social         = "社交"
    case messaging      = "通讯"
    case video          = "视频"
    case music          = "音乐"
    case shopping       = "购物"
    case finance        = "金融"
    case travel         = "出行"
    case news           = "新闻"
    case productivity   = "效率"
    case development    = "开发"
    case browser        = "浏览器"
    case security       = "安全"
    case utilities      = "工具"
    case entertainment  = "娱乐"
    case health         = "健康"
    case education      = "教育"
    case system         = "系统"
    case unknown        = "未知"
}

// MARK: - Resolved App Identity

/// 应用完整身份，包含显示名称、开发者、分类、图标、来源和置信度。
/// 这是整个 App Identity Resolution 系统的核心数据结构。
///
/// 创建后不可变（所有字段 let），保证多线程安全。
struct ResolvedAppIdentity: @unchecked Sendable {

    // ── 身份 ──────────────────────────────────────────────────────────────────

    /// 规范化后的 Bundle ID（已剥离 .helper/.xpc 等进程后缀）。
    let canonicalBundleID: String

    /// 用户可见的显示名称（中文优先，若不适用则英文）。
    let displayName: String

    // ── 元数据（可选，KnownApps 或 LaunchServices 来源时填充）────────────────

    /// 开发者 / 发行商名称，例如"腾讯"、"Google"。
    let developer: String?

    /// 应用分类。
    let category: AppCategory?

    /// 应用图标（从本机 App Bundle 加载；未安装的 App 为 nil）。
    let icon: NSImage?

    // ── 解析质量 ──────────────────────────────────────────────────────────────

    /// 解析来源（决定置信度）。
    let source: ResolutionSource

    /// 置信度：0.0（完全猜测）~ 1.0（用户自定义，确定无误）。
    var confidence: Double { source.confidence }

    /// 是否已被可靠识别（置信度 ≥ 0.80）。
    var isIdentified: Bool { source.isIdentified }

    // ── 初始化 ────────────────────────────────────────────────────────────────

    init(
        canonicalBundleID: String,
        displayName:       String,
        developer:         String?      = nil,
        category:          AppCategory? = nil,
        icon:              NSImage?     = nil,
        source:            ResolutionSource
    ) {
        self.canonicalBundleID = canonicalBundleID
        self.displayName       = displayName
        self.developer         = developer
        self.category          = category
        self.icon              = icon
        self.source            = source
    }

    // ── 工厂方法（便于各解析层构造）──────────────────────────────────────────

    static func userOverride(bundleID: String, name: String) -> ResolvedAppIdentity {
        ResolvedAppIdentity(canonicalBundleID: bundleID, displayName: name, source: .userOverride)
    }

    static func fallback(bundleID: String) -> ResolvedAppIdentity {
        ResolvedAppIdentity(canonicalBundleID: bundleID, displayName: bundleID, source: .fallback)
    }
}
