# ProxyForge

基于 **iOS App 隐私报告**（App Privacy Report）分析应用网络访问记录，一键生成 Loon / Surge / Quantumult X / Clash 分流规则的 macOS 原生应用。

---

## 功能特性

- 解析 iPhone 导出的 `App_Privacy_Report_v4_*.ndjson` 文件
- 按访问次数聚合，可排序的应用列表
- 支持四种主流代理格式：**Loon**、**Surge**、**Quantumult X**、**Clash**
- 合并子域（`api.x.com` → `DOMAIN-SUFFIX,x.com`）
- 可选是否包含 IP-CIDR 规则
- 自定义策略名称（默认 `Proxy`）
- 过滤系统应用（`com.apple.*`）
- 复制单个应用规则 / 复制全部规则 / 导出为文件
- 偏好设置跨启动持久化（UserDefaults）
- 结构化日志，可在 Console.app 中按 `parser` / `ui` / `export` 分类过滤

---

## 如何获取隐私报告

1. iPhone → **设置** → **隐私与安全性** → **App 隐私报告**
2. 开启记录后等待数据积累（建议 7 天以上）
3. 点击右上角分享图标 → **导出 App 隐私报告**
4. 将导出的 `.ndjson` 文件传输到 Mac

---

## 项目结构

```
ProxyForge/
├── proxy_forge.py                     # Python / tkinter 原型（已弃用）
└── ProxyForge/ProxyForge/
    ├── App/
    │   └── ProxyForgeApp.swift        # @main 应用入口，注入全局依赖
    ├── Models/
    │   ├── AppEntry.swift             # DomainInfo、AppEntry 数据结构
    │   └── RuleOptions.swift          # 规则生成选项（mergeSub、proxyTarget、includeIPs）
    ├── Services/
    │   ├── ReportParser.swift         # NDJSON 逐行解析，按 bundleID 聚合
    │   └── RuleFormatters.swift       # 全部格式化器（Loon / Surge / QX / Clash）
    ├── ViewModels/
    │   └── ContentViewModel.swift     # 业务逻辑：加载、刷新、复制、导出
    ├── Views/
    │   ├── ContentView.swift          # 主布局协调器
    │   ├── OptionsBarView.swift       # 顶部控制条
    │   ├── AppTableView.swift         # 可排序的应用列表
    │   └── RulePreviewView.swift      # 规则预览 + 操作按钮
    └── Utils/
        ├── AppLogger.swift            # os.Logger 三频道封装
        ├── DomainUtils.swift          # isIPAddress、rootDomain、deriveName
        └── UserSettings.swift         # 偏好持久化（@Published + UserDefaults）
```

---

## 技术栈

| 层级 | 技术 |
|------|------|
| UI 框架 | SwiftUI |
| 状态管理 | `@StateObject` / `@EnvironmentObject` / `@Published` |
| 持久化 | UserDefaults（通过 `UserSettings` 封装） |
| 并发 | Swift Concurrency（`Task.detached`，`@MainActor`） |
| 日志 | `os.Logger`（subsystem: bundle ID，三个 category） |
| 最低系统要求 | macOS 13 Ventura |
| 语言 | Swift 5.9+ |

---

## 在 Xcode 中构建

> 项目源文件已就绪，需手动创建 Xcode 工程并添加文件。

1. 打开 **Xcode** → **File** → **New** → **Project**
2. 选择 **macOS** → **App**，填写：
   - Product Name: `ProxyForge`
   - Bundle Identifier: `com.yourname.ProxyForge`（可自定义）
   - Interface: **SwiftUI**，Language: **Swift**
3. 创建后，**删除** Xcode 自动生成的 `ContentView.swift` 和 `AppNameApp.swift`
4. 在 Finder 中，将 `ProxyForge/ProxyForge/ProxyForge/` 下的所有子文件夹（`App/`、`Models/` 等）拖入 Xcode 的 Project Navigator
5. 勾选 **Copy items if needed** + **Create groups**，确认 Target 已选中
6. **Product** → **Run**（⌘R）即可编译运行

---

## 日志查看

打开 **Console.app**，在搜索框中过滤：

```
subsystem: com.yourname.ProxyForge
```

或按 category 过滤：

| Category | 内容 |
|----------|------|
| `parser` | 文件解析进度与结果统计 |
| `ui`     | 用户交互（文件选择、预览刷新） |
| `export` | 复制/导出操作记录 |

---

## 导出格式示例

### Loon / Surge
```
# ── WeChat  (com.tencent.xin)
# 域名数: 12   总访问: 3842 次
DOMAIN-SUFFIX,wechat.com,Proxy
DOMAIN-SUFFIX,weixin.qq.com,Proxy
IP-CIDR,203.205.254.0/32,Proxy
```

### Quantumult X
```
# WeChat (com.tencent.xin)
host-suffix, wechat.com, proxy
host-suffix, weixin.qq.com, proxy
ip-cidr, 203.205.254.0/32, proxy
```

### Clash
```yaml
rules:
  # WeChat (com.tencent.xin)
  - DOMAIN-SUFFIX,wechat.com,Proxy
  - DOMAIN-SUFFIX,weixin.qq.com,Proxy
  - IP-CIDR,203.205.254.0/32,Proxy
```

---

## License

MIT
