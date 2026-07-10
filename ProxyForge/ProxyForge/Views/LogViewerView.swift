import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 日志查看器

struct LogViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LogStore.shared
    @State private var selectedCategory: LogCategory? = nil
    @State private var minLevel:         LogLevel     = .debug
    @State private var searchText:       String       = ""
    @State private var isExporting:      Bool         = false
    @State private var exportError:      String?      = nil
    @State private var showExportAlert:  Bool         = false
    @State private var selectedEntry:    LogEntry.ID? = nil

    private var filtered: [LogEntry] {
        store.filtered(category: selectedCategory, minLevel: minLevel, search: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logTable
            Divider()
            bottomBar
        }
        .frame(minWidth: 780, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .alert("导出失败", isPresented: $showExportAlert) {
            Button("好") { }
        } message: {
            Text(exportError ?? "未知错误")
        }
    }

    // ── 顶部过滤栏 ────────────────────────────────────────────────────────────

    private var filterBar: some View {
        HStack(spacing: 8) {
            // 分类 tab
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    categoryChip(nil, label: "全部")
                    ForEach(LogCategory.allCases, id: \.self) { cat in
                        categoryChip(cat, label: cat.displayName)
                    }
                }
                .padding(.horizontal, 2)
            }

            Divider().frame(height: 18)

            // 等级筛选
            Picker("等级", selection: $minLevel) {
                Text("全部").tag(LogLevel.debug)
                Text("Info+").tag(LogLevel.info)
                Text("Warning+").tag(LogLevel.warning)
                Text("Error").tag(LogLevel.error)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 90)
            .controlSize(.small)

            Divider().frame(height: 18)

            // 搜索
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).imageScale(.small)
                TextField("Search logs…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .frame(width: 160)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary).imageScale(.small)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func categoryChip(_ cat: LogCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = cat }
        } label: {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                            in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // ── 日志列表 ──────────────────────────────────────────────────────────────

    private var logTable: some View {
        Table(filtered, selection: $selectedEntry) {
            TableColumn("时间") { entry in
                Text(timeString(entry.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("等级") { entry in
                HStack(spacing: 4) {
                    Text(entry.level.emoji)
                    Text(entry.level.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(entry.level.color)
                }
            }
            .width(70)

            TableColumn("分类") { entry in
                Text(entry.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .width(82)

            TableColumn("内容") { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.message)
                        .font(.callout)
                        .foregroundStyle(entry.level.color)
                        .lineLimit(1)
                    if let det = entry.details {
                        Text(det)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    // ── 底部操作栏 ────────────────────────────────────────────────────────────

    private var bottomBar: some View {
        HStack {
            Text("\(filtered.count) 条 / 共 \(store.entries.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button(role: .destructive) {
                store.clear()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                copyLogs()
            } label: {
                Label("复制全部", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filtered.isEmpty)

            Button {
                Task { await exportLogs() }
            } label: {
                if isExporting {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("导出中…")
                    }
                } else {
                    Label("Export Logs", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isExporting || store.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // ── 操作 ──────────────────────────────────────────────────────────────────

    private func copyLogs() {
        let text = filtered.map(\.singleLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        AppLogger.shared.info("已复制 \(filtered.count) 条日志", category: .ui)
    }

    private func exportLogs() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let zipURL = try await LogExporter.exportZip()
            // 用 NSSavePanel 让用户选择保存位置
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = zipURL.lastPathComponent
                if let t = UTType(filenameExtension: "zip") { panel.allowedContentTypes = [t] }
                if panel.runModal() == .OK, let dst = panel.url {
                    try? FileManager.default.copyItem(at: zipURL, to: dst)
                    try? FileManager.default.removeItem(at: zipURL)
                }
            }
        } catch {
            exportError   = error.localizedDescription
            showExportAlert = true
        }
    }

    // ── 工具 ──────────────────────────────────────────────────────────────────

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    private func timeString(_ date: Date) -> String { Self.timeFmt.string(from: date) }
}
