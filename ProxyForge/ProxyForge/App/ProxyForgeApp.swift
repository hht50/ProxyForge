import SwiftUI

// MARK: - 应用入口

@main
struct ProxyForgeApp: App {
    @StateObject private var settings = UserSettings()

    // ViewModel 依赖 settings，使用 lazy init 避免 @StateObject 的循环
    @StateObject private var vm: ContentViewModel

    init() {
        let s = UserSettings()
        _settings = StateObject(wrappedValue: s)
        _vm       = StateObject(wrappedValue: ContentViewModel(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(vm)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }  // 隐藏"新建"菜单项
        }
    }
}
