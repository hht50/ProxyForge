import SwiftUI
import AppKit

// MARK: - 规则预览面板

/// 下半区域：显示选中应用或全部应用的格式化规则，提供复制和导出按钮。
struct RulePreviewView: View {
    @EnvironmentObject private var vm: ContentViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 + 操作按钮
            HStack {
                Label("规则预览  (\(vm.formatter.displayName))", systemImage: "doc.text")
                    .font(.headline)
                    .foregroundStyle(.tint)

                Spacer()

                Button("复制选中") { vm.copySelected() }.buttonStyle(.bordered)
                Button("复制全部") { vm.copyAll()     }.buttonStyle(.bordered)
                Button("导出 .\(vm.formatter.fileExtension)") { vm.exportFile() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // 规则文本：使用 NSTextView 包装实现大文本高性能懒加载渲染
            MonoTextView(text: vm.ruleText)
                .background(Color(NSColor.textBackgroundColor))
        }
    }
}

// MARK: - NSTextView 包装（支持选中、横向滚动、大文本高性能）

struct MonoTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        // 外观
        textView.font             = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor  = NSColor.textBackgroundColor
        textView.textColor        = NSColor.labelColor
        textView.isEditable       = false
        textView.isSelectable     = true
        textView.isRichText       = false
        textView.usesFindBar      = true   // Cmd+F 搜索

        // 横向滚动：关闭宽度自动跟随，使长行可横向滚动
        textView.isVerticallyResizable                    = true
        textView.isHorizontallyResizable                  = true
        textView.autoresizingMask                         = [.width]
        textView.textContainer?.widthTracksTextView       = false
        textView.textContainer?.containerSize             = NSSize(
            width:  CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers    = true

        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 仅在内容变化时更新，避免无谓的重排版
        if textView.string != text {
            textView.string = text
        }
    }
}
