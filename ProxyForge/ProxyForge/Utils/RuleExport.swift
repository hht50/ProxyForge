import Foundation

// MARK: - 导出格式（独立于预览格式）

/// 可供导出的规则格式，rawValue 直接索引 `allFormatters`。
/// 与 UserSettings.formatterIdx（预览）完全解耦，持久化于 UserSettings.exportFormatIdx。
enum ExportFormat: Int, CaseIterable, Identifiable {
    case loon         = 0
    case surge        = 1
    case quantumultX  = 2
    case clash        = 3

    var id: Int { rawValue }

    var formatter: any RuleFormatter { allFormatters[rawValue] }
    var displayName:   String { formatter.displayName   }
    var fileExtension: String { formatter.fileExtension }
}

// MARK: - 导出范围

/// 描述一次导出操作所覆盖的应用范围。
enum ExportScope {
    /// 指定的一批应用（可为1个或多个）
    case selected([AppEntry])
    /// 当前加载的全部应用
    case all
}
