import Foundation

// MARK: - 导出计时上下文

struct ExportTimingContext: Sendable {
    let id:        UUID        = UUID()
    let startTime: CFAbsoluteTime
    let format:    String
    let appCount:  Int
    var steps:     [(label: String, elapsed: Double)] = []

    var totalElapsed: Double { CFAbsoluteTimeGetCurrent() - startTime }

    mutating func addStep(_ label: String, from stepStart: CFAbsoluteTime) {
        steps.append((label, CFAbsoluteTimeGetCurrent() - stepStart))
    }
}

// MARK: - ExportLogger（导出专用日志辅助）

enum ExportLogger {

    // ── 开始导出 ──────────────────────────────────────────────────────────────

    @discardableResult
    static func start(
        format:   String,
        appCount: Int,
        domainCount: Int = 0
    ) -> ExportTimingContext {
        let ctx = ExportTimingContext(startTime: CFAbsoluteTimeGetCurrent(),
                                      format: format, appCount: appCount)
        AppLogger.shared.info(
            "Preparing export task",
            category: .export
        )
        AppLogger.shared.info(
            "Export source ready",
            category: .export,
            details: "Format: \(format) | Apps: \(appCount)\(domainCount > 0 ? " | Domains: \(domainCount)" : "")"
        )
        AppLogger.shared.debug(
            "Formatter: \(format)",
            category: .export
        )
        return ctx
    }

    // ── 记录一个阶段步骤 ──────────────────────────────────────────────────────

    static func step(
        _ label: String,
        elapsed: Double? = nil,
        details: String? = nil
    ) {
        let elapsedStr = elapsed.map { String(format: " (%.2fs)", $0) } ?? ""
        AppLogger.shared.debug(
            "\(label)\(elapsedStr)",
            category: .export,
            details: details
        )
    }

    // ── 导出成功 ──────────────────────────────────────────────────────────────

    static func complete(
        context:   ExportTimingContext,
        ruleCount: Int   = 0,
        fileURL:   URL?  = nil
    ) {
        let total = context.totalElapsed
        var det   = "Format: \(context.format) | Apps: \(context.appCount) | Duration: \(String(format: "%.2fs", total))"
        if ruleCount > 0       { det += " | Rules: \(ruleCount)" }
        if let url = fileURL   { det += " | File: \(url.lastPathComponent)" }
        if !context.steps.isEmpty {
            let stepsStr = context.steps.map { "\($0.label): \(String(format: "%.2fs", $0.elapsed))" }.joined(separator: ", ")
            det += " | Steps: [\(stepsStr)]"
        }

        AppLogger.shared.success(
            "Rule export completed",
            category: .export,
            details: det
        )

        // 性能日志
        AppLogger.shared.info(
            "Export performance",
            category: .performance,
            details: "Total: \(String(format: "%.2fs", total)) | Format: \(context.format) | Apps: \(context.appCount)"
        )
    }

    // ── 导出失败 ──────────────────────────────────────────────────────────────

    static func failed(
        _ err:    Error,
        context:  ExportTimingContext
    ) {
        AppLogger.shared.error(
            "Export failed",
            category: .export,
            details: "Reason: \(err.localizedDescription) | Format: \(context.format) | Apps: \(context.appCount) | Elapsed: \(String(format: "%.2fs", context.totalElapsed))"
        )
    }
}
