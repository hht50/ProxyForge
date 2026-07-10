import Foundation
import AppKit

// MARK: - LogExporter（将日志打包成 ZIP 供用户导出）

enum LogExporter {

    /// 生成 ProxyForge_Log_日期.zip，内含 5 个文件
    static func exportZip() async throws -> URL {
        let fm      = FileManager.default
        let tmpDir  = fm.temporaryDirectory.appendingPathComponent("PFLog_\(UUID().uuidString)")
        let subDir  = tmpDir.appendingPathComponent("ProxyForge_Log")
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let store = await LogStore.shared.entries

        // 1. application.log — 全部日志
        try writeLog(entries: store, to: subDir.appendingPathComponent("application.log"))

        // 2. export.log — 仅 Export 分类
        let exportEntries = store.filter { $0.category == .export }
        try writeLog(entries: exportEntries, to: subDir.appendingPathComponent("export.log"))

        // 3. error.log — 仅 error/warning 等级
        let errorEntries = store.filter { $0.level >= .warning }
        try writeLog(entries: errorEntries, to: subDir.appendingPathComponent("error.log"))

        // 4. system.txt
        let systemText = await buildSystemText()
        try systemText.write(to: subDir.appendingPathComponent("system.txt"),
                             atomically: true, encoding: .utf8)

        // 5. metadata.json
        let meta = await buildMetadata(logCount: store.count)
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
        try metaData.write(to: subDir.appendingPathComponent("metadata.json"))

        // 打包 ZIP
        let fmt     = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let zipName = "ProxyForge_Log_\(fmt.string(from: Date())).zip"
        let zipURL  = fm.temporaryDirectory.appendingPathComponent(zipName)
        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = tmpDir
        process.arguments = ["-r", zipURL.path, "ProxyForge_Log"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ProxyForge.LogExport", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "zip 返回错误码 \(process.terminationStatus)"])
        }

        AppLogger.shared.success("日志导出成功", category: .export,
                                 details: zipURL.lastPathComponent)
        return zipURL
    }

    // ── 辅助 ──────────────────────────────────────────────────────────────────

    private static func writeLog(entries: [LogEntry], to url: URL) throws {
        let text = entries.map(\.singleLine).joined(separator: "\n")
        try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func buildSystemText() -> String {
        let info     = ProcessInfo.processInfo
        let mem      = info.physicalMemory / (1024 * 1024 * 1024)
        let version  = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build    = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let osVer    = info.operatingSystemVersionString
        let cpuCount = info.processorCount

        return """
        ProxyForge System Report
        ========================
        App Version    : \(version) (\(build))
        macOS Version  : \(osVer)
        CPU Cores      : \(cpuCount)
        RAM (total)    : \(mem) GB
        Bundle ID      : \(Bundle.main.bundleIdentifier ?? "—")
        Generated      : \(ISO8601DateFormatter().string(from: Date()))
        """
    }

    @MainActor
    private static func buildMetadata(logCount: Int) -> [String: Any] {
        let info    = ProcessInfo.processInfo
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return [
            "appVersion":  version,
            "macOS":       info.operatingSystemVersionString,
            "model":       getModelIdentifier(),
            "exportTime":  ISO8601DateFormatter().string(from: Date()),
            "logCount":    logCount,
            "bundleID":    Bundle.main.bundleIdentifier ?? "—"
        ]
    }

    private static func getModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
