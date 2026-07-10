import Foundation
import os.log

// MARK: - AppLogger（统一日志入口）

/// 线程安全单例。从任意线程 fire-and-forget；
/// 内部同时写入 os.log（Console.app）+ LogStore（应用内查看）+ 磁盘文件。
final class AppLogger: @unchecked Sendable {

    static let shared = AppLogger()
    private init() {}

    // ── os.log 频道（Console.app 兼容）──────────────────────────────────────
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.proxyforge"

    private lazy var osLoggers: [String: os.Logger] = {
        var d = [String: os.Logger]()
        for cat in LogCategory.allCases {
            d[cat.rawValue] = os.Logger(subsystem: subsystem, category: cat.osCategory)
        }
        return d
    }()

    private func osLogger(for category: LogCategory) -> os.Logger {
        osLoggers[category.rawValue] ?? os.Logger(subsystem: subsystem, category: category.osCategory)
    }

    // ── 公开 API ─────────────────────────────────────────────────────────────

    func debug(_ message: String, category: LogCategory = .app,
               details: String? = nil, file: String = #file, function: String = #function) {
        emit(.debug, category: category, message: message, details: details, file: file, function: function)
    }

    func info(_ message: String, category: LogCategory = .app,
              details: String? = nil, file: String = #file, function: String = #function) {
        emit(.info, category: category, message: message, details: details, file: file, function: function)
    }

    func success(_ message: String, category: LogCategory = .app,
                 details: String? = nil, file: String = #file, function: String = #function) {
        emit(.success, category: category, message: message, details: details, file: file, function: function)
    }

    func warning(_ message: String, category: LogCategory = .app,
                 details: String? = nil, file: String = #file, function: String = #function) {
        emit(.warning, category: category, message: message, details: details, file: file, function: function)
    }

    func error(_ message: String, category: LogCategory = .error,
               details: String? = nil, file: String = #file, function: String = #function) {
        emit(.error, category: category, message: message, details: details, file: file, function: function)
    }

    // ── 核心路由 ──────────────────────────────────────────────────────────────

    private func emit(_ level: LogLevel, category: LogCategory,
                      message: String, details: String?, file: String, function: String) {
        let entry = LogEntry(level: level, category: category,
                             message: message, details: details,
                             file: file, function: function)
        // 1. os.log（同步，极轻量）
        let full = details.map { "\(message) | \($0)" } ?? message
        let logger = osLogger(for: category)
        switch level {
        case .debug:   logger.debug(  "\(full, privacy: .public)")
        case .info:    logger.info(   "\(full, privacy: .public)")
        case .success: logger.notice( "\(full, privacy: .public)")
        case .warning: logger.warning("\(full, privacy: .public)")
        case .error:   logger.error(  "\(full, privacy: .public)")
        }
        // 2. LogStore（异步，不阻塞调用方）
        LogStore.shared.append(entry)
    }
}

// MARK: - 向后兼容：保留静态频道（现有 Logger.parser.xxx 形式可继续编译）

extension Logger {
    private static let _sub = Bundle.main.bundleIdentifier ?? "com.proxyforge"
    static let parser   = Logger(subsystem: _sub, category: "parser")
    static let ui       = Logger(subsystem: _sub, category: "ui")
    static let export   = Logger(subsystem: _sub, category: "export")
    static let resolver = Logger(subsystem: _sub, category: "resolver")
}
