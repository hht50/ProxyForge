import Foundation
import SwiftUI

// MARK: - 文件写入 Actor（后台线程安全 I/O）

private actor FileWriteActor {

    private let logsDir: URL
    private let maxFileSizeBytes: Int = 10 * 1024 * 1024   // 10 MB
    private let retentionDays:    Int = 30

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        logsDir = appSupport
            .appendingPathComponent("ProxyForge", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir,
                                                  withIntermediateDirectories: true)
    }

    // ── 日期滚动文件 URL ──────────────────────────────────────────────────────

    private func logFileURL(for date: Date = Date()) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return logsDir.appendingPathComponent("\(fmt.string(from: date)).log")
    }

    // ── 写入单条日志 ──────────────────────────────────────────────────────────

    func write(_ entry: LogEntry) {
        let url  = logFileURL()
        let line = entry.singleLine + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            // 检查文件大小
            let size = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size >= maxFileSizeBytes {
                // 按时间戳追加后缀滚动
                let ts  = Int(Date().timeIntervalSince1970)
                let dst = logsDir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)_\(ts).log")
                try? FileManager.default.moveItem(at: url, to: dst)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    // ── 清理旧日志（30天前）────────────────────────────────────────────────────

    func pruneOldLogs() {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        guard let items = try? FileManager.default
            .contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey])
        else { return }
        for item in items where item.pathExtension == "log" {
            let created = (try? item.resourceValues(forKeys: [.creationDateKey])
                .creationDate) ?? Date()
            if created < cutoff { try? FileManager.default.removeItem(at: item) }
        }
    }

    // ── 读取所有当日日志（供导出）──────────────────────────────────────────────

    func readAllLogFiles() -> [URL] {
        (try? FileManager.default
            .contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        ) ?? []
    }

    var logsDirectory: URL { logsDir }
}

// MARK: - LogStore（MainActor，SwiftUI 直接绑定）

@MainActor
final class LogStore: ObservableObject {

    static let shared = LogStore()

    /// 内存缓冲区（最多 2000 条，超出后裁剪前 500 条）
    @Published private(set) var entries: [LogEntry] = []

    private let fileActor = FileWriteActor()
    private let maxEntries = 2000
    private let trimCount  = 500

    private init() {
        // 启动时清理旧日志（后台异步，不阻塞 UI）
        Task.detached(priority: .background) { [weak self] in
            await self?.fileActor.pruneOldLogs()
        }
    }

    // ── 追加日志（可从任意线程调用）──────────────────────────────────────────

    nonisolated func append(_ entry: LogEntry) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.trimCount)
            }
        }
        Task.detached(priority: .background) { [weak self] in
            await self?.fileActor.write(entry)
        }
    }

    // ── 清空内存日志 ──────────────────────────────────────────────────────────

    func clear() { entries.removeAll() }

    // ── 过滤 ──────────────────────────────────────────────────────────────────

    func filtered(
        category: LogCategory? = nil,
        minLevel: LogLevel     = .debug,
        search:   String       = ""
    ) -> [LogEntry] {
        entries.filter { e in
            (category == nil || e.category == category!)
                && e.level >= minLevel
                && (search.isEmpty
                    || e.message.localizedCaseInsensitiveContains(search)
                    || (e.details?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    // ── 导出用原始文件 URL 列表 ───────────────────────────────────────────────

    func logFileURLs() async -> [URL] {
        await fileActor.readAllLogFiles()
    }

    var logsDirectoryURL: URL {
        get async { await fileActor.logsDirectory }
    }
}
