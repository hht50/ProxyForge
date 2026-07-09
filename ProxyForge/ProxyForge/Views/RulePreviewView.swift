import SwiftUI
import AppKit

// MARK: - 规则预览面板

/// 右侧主面板：标题/选中信息 + 操作按钮 + NSTextView 规则预览。
struct RulePreviewView: View {
    @EnvironmentObject private var vm: ContentViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
    }

    // ── 顶部标题 + 操作按钮 ───────────────────────────────────────────────────

    private var headerBar: some View {
        HStack(spacing: 8) {
            // 标题：反映当前选中状态
            selectionTitle
                .font(.headline)
                .foregroundStyle(.tint)

            // 当前格式 badge
            Text(vm.formatter.displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(.tint)

            // 规则统计 badge（有内容时显示）
            if !vm.selectedIDs.isEmpty, ruleLineCount > 0 {
                RuleStatBadge(rules: ruleLineCount, domains: domainLineCount)
            }

            Spacer()

            // 复制区
            HStack(spacing: 4) {
                Button {
                    vm.copySelected()
                } label: {
                    Label("复制选中", systemImage: "doc.on.doc")
                }
                .help("复制当前预览的规则文本 ⌘⇧C")
                .disabled(vm.selectedIDs.isEmpty)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    vm.copyAll()
                } label: {
                    Label("复制全部", systemImage: "doc.on.clipboard")
                }
                .help("复制全部应用的合并规则")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider().frame(height: 16)

            // 导出区
            HStack(spacing: 4) {
                exportSelectedButton
                    .controlSize(.small)

                Button {
                    vm.exportAll()
                } label: {
                    Label("导出全部", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("将全部应用的规则导出为单个文件")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // ── 规则行数计算（从当前 ruleText 实时统计）────────────────────────────────

    /// DOMAIN-SUFFIX / DOMAIN / DOMAIN-KEYWORD / IP-CIDR 行数之和
    private var ruleLineCount: Int {
        vm.ruleText.components(separatedBy: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.hasPrefix("DOMAIN") || t.hasPrefix("IP-CIDR") || t.hasPrefix("IP-ASN")
            }.count
    }

    /// 仅 DOMAIN 类行数（不含 IP）
    private var domainLineCount: Int {
        vm.ruleText.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("DOMAIN") }
            .count
    }

    // ── 选中标题（动态内容）─────────────────────────────────────────────────

    @ViewBuilder
    private var selectionTitle: some View {
        let count = vm.selectedIDs.count
        if count == 0 {
            Label("规则预览", systemImage: "doc.text")
        } else if count == 1 {
            Label(vm.selectedApp?.name ?? "规则预览", systemImage: "doc.text")
        } else {
            Label("已选 \(count) 个应用", systemImage: "doc.on.doc.fill")
        }
    }

    // ── 内容区：空状态 / 未选 / 规则文本 ─────────────────────────────────────

    @ViewBuilder
    private var contentArea: some View {
        if vm.apps.isEmpty {
            emptyFileState
        } else if vm.selectedIDs.isEmpty {
            noSelectionState
        } else {
            MonoTextView(text: vm.ruleText)
                .background(Color(NSColor.textBackgroundColor))
        }
    }

    // ── 空状态：未加载文件 ────────────────────────────────────────────────────

    private var emptyFileState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("尚未加载任何报告")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("点击工具栏「打开文件」导入，或将文件拖入窗口")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── 空状态：已加载但未选择 ────────────────────────────────────────────────

    private var noSelectionState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("点击左侧应用查看规则")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "command")
                    Text("+  点击可多选")
                }
                .font(.callout)
                .foregroundStyle(.tertiary)
                Text("多选后可批量导出为 ZIP 压缩包")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── 导出选中按钮（动态标签 + ⌘E 快捷键）────────────────────────────────────

    private var exportSelectedButton: some View {
        let count   = vm.selectedIDs.count
        let isMulti = count > 1
        let label   = isMulti
            ? "导出选中 (\(count)) .zip"
            : "导出选中 .\(vm.formatter.fileExtension)"
        let icon    = isMulti ? "archivebox" : "square.and.arrow.up"
        let tip     = isMulti
            ? "将 \(count) 个选中应用分别生成规则文件，打包为 ZIP ⌘E"
            : "将选中应用的规则导出为 .\(vm.formatter.fileExtension) 文件 ⌘E"

        return Button {
            vm.exportSelected()
        } label: {
            Label(label, systemImage: icon)
        }
        .buttonStyle(.borderedProminent)
        .disabled(count == 0)
        .help(tip)
        .keyboardShortcut("e")
    }
}

// MARK: - 规则统计 Badge

private struct RuleStatBadge: View {
    let rules:   Int
    let domains: Int

    var body: some View {
        HStack(spacing: 6) {
            statItem(value: rules,   label: "rules")
            if domains < rules {
                statItem(value: domains, label: "domains")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }

    private func statItem(value: Int, label: String) -> some View {
        HStack(spacing: 2) {
            Text(value.formatted())
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - NSTextView 包装（Cmd+F 搜索 / 横向滚动 / 大文本高性能 / 无切换闪烁）

struct MonoTextView: NSViewRepresentable {
    let text: String

    // 字体/颜色提取为常量，makeNSView 和 updateNSView 共用
    private static let monoFont    = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let textAttrs: [NSAttributedString.Key: Any] = [
        .font:            monoFont,
        .foregroundColor: NSColor.labelColor
    ]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // 使视图不透明，防止背景色短暂显示为白色
        textView.drawsBackground   = true
        textView.backgroundColor   = NSColor.textBackgroundColor
        textView.textColor         = NSColor.labelColor
        textView.font              = Self.monoFont
        textView.isEditable        = false
        textView.isSelectable      = true
        textView.isRichText        = false   // 保持 false；我们通过 NSTextStorage 手动设置属性
        textView.usesFindBar       = true    // Cmd+F 全文搜索

        // 横向滚动：禁用宽度跟随，允许长行横向展开
        textView.isVerticallyResizable               = true
        textView.isHorizontallyResizable             = true
        textView.autoresizingMask                    = [.width]
        textView.textContainer?.widthTracksTextView  = false
        textView.textContainer?.containerSize        = NSSize(
            width:  CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers    = true

        // 初始内容
        Self.replaceContent(of: textView, with: text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }   // 内容相同时跳过

        Self.replaceContent(of: textView, with: text)
        // 切换 App 时滚动回顶部
        textView.scroll(.zero)
    }

    // ── 原子替换内容（避免整行 glyph 重算引起的空白帧）────────────────────────

    private static func replaceContent(of textView: NSTextView, with newText: String) {
        guard let storage = textView.textStorage else {
            textView.string = newText   // 兜底
            return
        }
        let newAttr = NSAttributedString(string: newText, attributes: textAttrs)
        // beginEditing / endEditing 确保一次 layout pass，不产生中间空白帧
        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: 0, length: storage.length),
            with: newAttr
        )
        storage.endEditing()
    }
}
