import SwiftUI
import AppKit

// MARK: - 应用列表

/// 展示已解析的 AppEntry 列表，支持多选、列标题排序、App 图标和置信度标记。
struct AppTableView: View {
    @EnvironmentObject private var vm: ContentViewModel
    let apps: [AppEntry]

    /// 右键重命名：当前正在编辑的 App
    @State private var renamingApp:   AppEntry? = nil
    @State private var renameInput:   String    = ""
    @State private var showRenameSheet = false

    var body: some View {
        Table(apps, selection: $vm.selectedIDs, sortOrder: $vm.sortOrder) {

            // ── 应用名称列 ─────────────────────────────────────────────────────
            TableColumn("应用名称", value: \.name) { app in
                HStack(spacing: 5) {
                    // App 图标（本机已安装时有图标，否则用系统占位图）
                    AppIconView(identity: app.identity)

                    // 共享域名标记
                    if vm.appsWithSharedDomains.contains(app.id) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                            .foregroundStyle(.tint)
                            .help("含共享域名")
                    }

                    Text(app.name).fontWeight(.medium)

                    // 低置信度标记（仅 camelCase 或 fallback 级别显示）
                    if let identity = app.identity, !identity.isIdentified {
                        Image(systemName: identity.source.sfSymbol)
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                            .help("识别来源：\(identity.source.description)（置信度 \(Int(identity.confidence * 100))%）")
                    }
                }
            }
            .width(min: 120, ideal: 160)

            // ── Bundle ID 列 ────────────────────────────────────────────────────
            TableColumn("Bundle ID", value: \.bundleID) { app in
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.bundleID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(app.bundleID.hasPrefix("com.apple.") ? .tertiary : .secondary)

                    // 开发者信息（如果有）
                    if let dev = app.identity?.developer {
                        Text(dev)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .width(min: 180, ideal: 240)

            // ── 域名 ─────────────────────────────────────────────────────────
            TableColumn("域名", value: \.domainCount) { app in
                Text("\(app.domainCount)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(52)

            // ── 访问次数 ──────────────────────────────────────────────────────
            TableColumn("访问", value: \.totalHits) { app in
                Text("\(app.totalHits)")
                    .monospacedDigit()
                    .foregroundStyle(hitColor(app.totalHits))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(64)

            // ── IP ───────────────────────────────────────────────────────────
            TableColumn("IP", value: \.ipCount) { app in
                Text(app.ipCount > 0 ? "\(app.ipCount)" : "—")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(app.ipCount > 0 ? Color.orange : Color.secondary)
            }
            .width(44)
        }
        .onChange(of: vm.selectedIDs) { _ in vm.refreshPreview() }
        .contextMenu(forSelectionType: AppEntry.ID.self) { ids in
            // 右键菜单：只在单选时显示"重命名"
            if ids.count == 1, let id = ids.first,
               let app = apps.first(where: { $0.id == id }) {
                Button {
                    renamingApp  = app
                    renameInput  = app.name
                    showRenameSheet = true
                } label: {
                    Label("重命名「\(app.name)」…", systemImage: "pencil")
                }

                // 如果已有用户覆盖，提供恢复选项
                if AppIdentityResolver.shared.allUserOverrides[app.id] != nil {
                    Button {
                        AppIdentityResolver.shared.removeUserOverride(bundleID: app.id)
                        vm.reloadCurrentIdentities()
                    } label: {
                        Label("还原自动识别名称", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } primaryAction: { _ in }
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
    }

    // MARK: - 重命名 Sheet

    private var renameSheet: some View {
        VStack(spacing: 16) {
            Text("重命名应用")
                .font(.headline)

            if let app = renamingApp {
                HStack(spacing: 8) {
                    AppIconView(identity: app.identity, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.bundleID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TextField("显示名称", text: $renameInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack(spacing: 12) {
                Button("取消") { showRenameSheet = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Button("保存") {
                    let trimmed = renameInput.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, let app = renamingApp {
                        AppIdentityResolver.shared.setUserOverride(bundleID: app.id, name: trimmed)
                        vm.reloadCurrentIdentities()
                    }
                    showRenameSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(minWidth: 340)
    }

    // MARK: - 工具函数

    private func hitColor(_ hits: Int) -> Color {
        switch hits {
        case ..<100:  return .primary
        case ..<1000: return .orange
        default:      return .red
        }
    }
}

// MARK: - App 图标视图

/// 显示 App 图标。有 identity.icon 时用真实图标，否则用系统默认文件图标占位。
struct AppIconView: View {
    let identity: ResolvedAppIdentity?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let icon = identity?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                // 未安装或未识别时的占位图标
                Image(systemName: categorySymbol)
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var categorySymbol: String {
        switch identity?.category {
        case .social:        return "person.2"
        case .messaging:     return "message"
        case .video:         return "film"
        case .music:         return "music.note"
        case .shopping:      return "cart"
        case .finance:       return "creditcard"
        case .travel:        return "car"
        case .news:          return "newspaper"
        case .productivity:  return "doc.text"
        case .development:   return "hammer"
        case .browser:       return "globe"
        case .security:      return "lock.shield"
        case .utilities:     return "wrench.and.screwdriver"
        case .entertainment: return "gamecontroller"
        case .health:        return "heart"
        case .education:     return "book"
        case .system:        return "gearshape"
        default:             return "app"
        }
    }
}
