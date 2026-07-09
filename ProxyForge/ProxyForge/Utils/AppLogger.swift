import Foundation
import os.log

// MARK: - 应用日志

/// 按功能分类的日志频道，可在 Console.app 中按 category 过滤。
///
/// 用法：
///   Logger.parser.info("开始解析 \(url.lastPathComponent)")
///   Logger.export.error("导出失败: \(error.localizedDescription)")
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.proxyforge"

    /// 文件解析相关日志
    static let parser = Logger(subsystem: subsystem, category: "parser")

    /// UI 交互相关日志（选择、过滤切换等）
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// 导出 / 剪贴板操作日志
    static let export = Logger(subsystem: subsystem, category: "export")

    /// AppIdentityResolver 缓存与解析日志（🟢 内存命中 / 🔵 磁盘命中 / 🔴 NSWorkspace 解析）
    static let resolver = Logger(subsystem: subsystem, category: "resolver")
}
