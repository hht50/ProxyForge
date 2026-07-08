import SwiftUI

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

            // 规则文本
            ScrollView([.horizontal, .vertical]) {
                Text(vm.ruleText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }
}
