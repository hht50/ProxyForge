import Foundation

// MARK: - 日志条目

struct LogEntry: Identifiable, Sendable {
    let id:        UUID
    let timestamp: Date
    let level:     LogLevel
    let category:  LogCategory
    let message:   String
    let details:   String?
    let thread:    String
    let file:      String       // 源文件名（不含路径）
    let function:  String       // 函数名

    init(
        level:    LogLevel,
        category: LogCategory,
        message:  String,
        details:  String?  = nil,
        file:     String   = #file,
        function: String   = #function
    ) {
        self.id        = UUID()
        self.timestamp = Date()
        self.level     = level
        self.category  = category
        self.message   = message
        self.details   = details
        self.thread    = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg")
        self.file      = URL(fileURLWithPath: file).lastPathComponent
        self.function  = function
    }

    // ── 格式化输出（写文件用）─────────────────────────────────────────────────

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 单行格式，适合普通日志文件
    var singleLine: String {
        let ts = Self.fileDateFormatter.string(from: timestamp)
        let det = details.map { " | \($0.replacingOccurrences(of: "\n", with: " "))" } ?? ""
        return "[\(ts)] [\(level.label.padding(toLength: 7, withPad: " ", startingAt: 0))] [\(category.displayName.padding(toLength: 11, withPad: " ", startingAt: 0))] \(message)\(det) (\(file):\(function))"
    }

    /// 多行详细格式，适合错误诊断
    var multiLine: String {
        let ts  = Self.fileDateFormatter.string(from: timestamp)
        var out = "[\(ts)] \(level.emoji) \(level.label) — \(category.displayName)\n  \(message)"
        if let d = details { out += "\n  Details: \(d)" }
        out += "\n  Thread: \(thread) | \(file) \(function)"
        return out
    }
}
