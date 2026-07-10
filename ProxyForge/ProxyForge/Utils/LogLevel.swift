import Foundation
import SwiftUI

// MARK: - 日志等级

enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    case debug   = 0
    case info    = 1
    case success = 2
    case warning = 3
    case error   = 4

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .success: return "SUCCESS"
        case .warning: return "WARNING"
        case .error:   return "ERROR"
        }
    }

    var emoji: String {
        switch self {
        case .debug:   return "◎"
        case .info:    return "●"
        case .success: return "✓"
        case .warning: return "⚠"
        case .error:   return "✕"
        }
    }

    var color: Color {
        switch self {
        case .debug:   return .secondary
        case .info:    return .primary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

// MARK: - 日志分类

enum LogCategory: String, CaseIterable, Sendable {
    case app         = "App"
    case `import`    = "Import"
    case parser      = "Parser"
    case resolver    = "Resolver"
    case cache       = "Cache"
    case export      = "Export"
    case ui          = "UI"
    case performance = "Performance"
    case error       = "Error"

    var displayName: String { rawValue }

    /// 对应 os.log 的 subsystem category 名称
    var osCategory: String {
        switch self {
        case .parser:   return "parser"
        case .resolver: return "resolver"
        case .export:   return "export"
        case .ui:       return "ui"
        default:        return rawValue.lowercased()
        }
    }
}
