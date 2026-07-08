import Foundation

// MARK: - 已知应用名称静态表

/// 静态 bundleID → 显示名称映射。
/// 查询时 bundleID 统一转小写，实现大小写不敏感匹配。
enum KnownApps {

    /// 返回已知的应用显示名称，未命中返回 `nil`。
    static func displayName(for bundleID: String) -> String? {
        table[bundleID.lowercased()]
    }

    // MARK: - 主表（精确 bundleID，全部小写键）
    private static let table: [String: String] = {
        var d = [String: String]()
        d.merge(chinese)    { a, _ in a }
        d.merge(international) { a, _ in a }
        d.merge(apple)      { a, _ in a }
        d.merge(productivity) { a, _ in a }
        return d
    }()

    // MARK: 国内常用 App
    private static let chinese: [String: String] = [
        // 腾讯
        "com.tencent.xin":               "微信",
        "com.tencent.wechat":            "微信 (Mac)",
        "com.tencent.qq":                "QQ",
        "com.tencent.qqmail":            "QQ邮箱",
        "com.tencent.qqmusic":           "QQ音乐",
        "com.tencent.mqq":               "QQ",
        "com.tencent.mttlite":           "QQ浏览器",
        "com.tencent.mtt":               "QQ浏览器",
        "com.tencent.now":               "NOW直播",
        "com.tencent.pengyou":           "朋友",
        "com.tencent.qzone":             "QQ空间",
        "com.tencent.weishi":            "微视",
        "com.tencent.hunyuan":           "腾讯元宝",
        "com.tencent.tenvideo":          "腾讯视频",
        "com.tencent.tenvideolite":      "腾讯视频极速版",
        "com.tencent.wetype":            "腾讯文档",
        "com.tencent.wemeet":            "腾讯会议",
        "com.tencent.enterprise":        "企业微信",
        "com.tencent.channel":           "视频号",
        "com.tencent.qqgame":            "QQ游戏",
        "com.tencent.lolm":              "英雄联盟手游",
        "com.tencent.leagueoflegends":   "英雄联盟",
        "com.tencent.honor.of.kings":    "王者荣耀",
        "com.tencent.mobilegame":        "王者荣耀",
        "com.tencent.pubgmhd":           "和平精英",

        // 阿里
        "com.alibaba.alipay":            "支付宝",
        "com.alipay.iphoneclient":       "支付宝",
        "com.alibaba.taobao":            "淘宝",
        "com.alibaba.taobao-s":          "淘宝",
        "com.alibaba.tmall":             "天猫",
        "com.alibaba.ailabs.genie":      "天猫精灵",
        "com.alibaba.alipayhk":          "支付宝HK",
        "com.alibaba.lazada":            "Lazada",
        "com.alibaba.dingtalk":          "钉钉",
        "com.laiwang.laiwangapp":        "来往",
        "com.youku.YouKu":               "优酷",
        "com.youku.youkuipad":           "优酷HD",
        "com.alibaba.health":            "阿里健康",
        "com.alibaba.aliexpress":        "全球速卖通",
        "com.amap.maps":                 "高德地图",
        "com.autonavi.minimap":          "高德地图",

        // 字节跳动
        "com.ss.iphone.app.toutiao":     "今日头条",
        "com.ss.iphone.articles":        "今日头条",
        "com.ss.iphone.ugc.aweme":       "抖音",
        "com.zhiliaoapp.musically":      "抖音",
        "com.bytedance.pangle":          "穿山甲",
        "com.ss.iphone.imgo":            "西瓜视频",
        "com.ss.iphone.ies":             "火山小视频",
        "com.ss.iphone.lite":            "今日头条极速版",
        "com.tiktok.TikTok":             "TikTok",
        "com.ss.iphone.tiktok.ad.uk":    "TikTok",
        "com.bytedance.lark":            "飞书",
        "com.bytedance.larklight":       "飞书精简版",
        "com.bytedance.capcut":          "剪映",
        "com.lemon.video":               "剪映专业版",
        "com.bytedance.coze":            "扣子",
        "com.ss.android.article.news":   "今日头条",
        "com.bytedance.xigua":           "西瓜视频",
        "com.ss.iphone.keeta":           "Keeta",

        // 百度
        "com.baidu.BaiduMobile":         "百度",
        "com.baidu.baiduapp":            "百度",
        "com.baidu.tieba":               "百度贴吧",
        "com.baidu.baidumaps":           "百度地图",
        "com.baidu.netdisk":             "百度网盘",
        "com.baidu.BaiduInput":          "百度输入法",
        "com.baidu.baidusearch":         "百度搜索",
        "com.baidu.BaiduHD":             "百度HD",
        "com.baidu.yuedu":               "百度阅读",
        "com.baidu.ergou":               "爱奇艺",

        // 网易
        "com.netease.cloudmusic":        "网易云音乐",
        "com.netease.cloudmusicapp":     "网易云音乐",
        "com.netease.mail":              "网易邮箱",
        "com.netease.yanxuan":           "网易严选",
        "com.netease.news":              "网易新闻",
        "com.netease.kaola":             "考拉海购",
        "com.netease.tycube":            "网易有道词典",
        "com.youdao.YoudaoDict":         "有道词典",

        // 哔哩哔哩
        "tv.danmaku.bilibili":           "哔哩哔哩",
        "com.bilibili.app.main":         "哔哩哔哩",
        "com.bilibili.app.iphone":       "哔哩哔哩",
        "tv.danmaku.biliPlayer":         "哔哩哔哩",

        // 小红书
        "com.xingin.discover":           "小红书",
        "com.xiaohongshu.app":           "小红书",

        // 拼多多 / TEMU
        "com.xunmeng.pinduoduo":         "拼多多",
        "com.pinduoduo.app":             "拼多多",
        "com.temu.temu":                 "TEMU",

        // 京东
        "com.360buy.jdmobile":           "京东",
        "com.jd.jdmobile":               "京东",

        // 美团
        "com.meituan.imeituan":          "美团",
        "com.meituan.group":             "美团",
        "com.meituan.waimai":            "美团外卖",

        // 饿了么
        "me.ele.ios":                    "饿了么",
        "com.ele.me":                    "饿了么",

        // 滴滴
        "com.sdu.didi.pphone":           "滴滴出行",
        "com.didi.d4b":                  "滴滴出行",
        "com.didi.mobility":             "滴滴出行",

        // 直播 / 短视频
        "com.inke.inkelive":             "映客直播",
        "com.yy.iplive":                 "YY直播",
        "com.douyu.live":                "斗鱼直播",
        "com.huya.live":                 "虎牙直播",
        "com.kuaishou.live":             "快手",
        "com.kuaishou.nebula":           "快手极速版",

        // 酷狗 / 酷我
        "com.kugou.kugoumusic":          "酷狗音乐",
        "cn.kuwo.player":                "酷我音乐",
        "com.kugou.kugousing":           "酷狗K歌",

        // 爱奇艺 / 优酷 / 芒果
        "com.qiyi.iphone":               "爱奇艺",
        "com.iqiyi.iphone":              "爱奇艺",
        "com.hunantv.imgo":              "芒果TV",
        "com.mgtv.tv":                   "芒果TV",

        // 银行
        "com.cmbchina.cmbmob":           "招商银行",
        "com.icbc.mobilebanking":        "工商银行",
        "com.ccb.ccbmobilebanking":      "建设银行",
        "com.abchina.mobilebanking":     "农业银行",
        "com.bankofchina.mobile":        "中国银行",
        "com.pingan.paibanker":          "平安银行",
        "com.alipay.iphoneclienthd":     "支付宝HD",
        "com.unionpay.uppay":            "云闪付",

        // 其他国内
        "com.sohu.news":                 "搜狐新闻",
        "com.ifeng.news2":               "凤凰新闻",
        "com.qihoo.mobilesafe":          "360手机卫士",
        "com.zhihu.app":                 "知乎",
        "com.lagou.app":                 "拉勾招聘",
        "com.boss.zhipin":               "BOSS直聘",
        "com.ctrip.iphone":              "携程旅行",
        "com.qyer.app":                  "穷游",
        "com.mafengwo.app":              "马蜂窝",
        "com.meituan.hotel":             "美团酒店",
        "com.fliggy.app":                "飞猪旅行",
        "com.gaopeng.ios":               "高朋",
        "com.gaode.app":                 "高德地图",
        "com.didi.didilite":             "滴滴出行极速版",
        "com.sf.express.sf-express":     "顺丰速运",
        "com.jd.logistics":              "京东物流",
        "com.cainiao.cainiao":           "菜鸟",
        "com.meituan.meituanp":          "美团平台",
        "com.qianxun.fanbook":           "FANBOOK",
        "com.eastmoney.iphone":          "东方财富",
        "com.xueqiu.app":                "雪球",
        "com.futu.futuopen":             "富途牛牛",
        "com.tiger.trade":               "老虎证券",
        "com.meituan.merPay":            "美团支付",
        "com.wps.office":                "WPS Office",
        "com.xiaomi.mihome":             "米家",
        "com.mi.health":                 "运动健康",
        "com.taobao.taobao":             "淘宝",
        "com.eleme.iphone":              "饿了么",
        "com.sogou.sginput":             "搜狗输入法",
        "com.kika.keyboard":             "Kika输入法",
        "com.haier.smartliving":         "海尔智家",
        "com.hwid.hilink":               "华为智慧生活",
        "com.oplus.health":              "一加健康",
        "com.fenbi.yitixue":             "粉笔",
        "com.yuanfudao.ios":             "猿辅导",
        "com.zuoyebang.app":             "作业帮",
        "com.jzb.ios":                   "精准学",
        "com.jingdong.app.ios":          "京东",
        "com.youzan.fenbei":             "有赞",
        "com.ximalaya.ting.iphone":      "喜马拉雅",
        "com.lizhi.iphone":              "荔枝FM",
        "com.qingting.fm":               "蜻蜓FM",
        "com.dragonfly.fm":              "蜻蜓FM",
        "com.mi.car":                    "小米汽车",
        "com.nio.owner":                 "NIO蔚来",
        "com.xpeng.ios":                 "小鹏汽车",
        "com.lixiang.auto":              "理想汽车",
        "com.jidu.app":                  "极越",
        "com.byd.mycar":                 "比亚迪",
    ]

    // MARK: 国际主流 App
    private static let international: [String: String] = [
        // Google
        "com.google.chrome":             "Chrome",
        "com.google.gmail":              "Gmail",
        "com.google.maps":               "Google Maps",
        "com.google.translate":          "Google Translate",
        "com.google.youtube":            "YouTube",
        "com.google.photos":             "Google Photos",
        "com.google.drive":              "Google Drive",
        "com.google.docs":               "Google Docs",
        "com.google.sheets":             "Google Sheets",
        "com.google.slides":             "Google Slides",
        "com.google.meet":               "Google Meet",
        "com.google.calendar":           "Google Calendar",
        "com.google.googlemobile":       "Google",
        "com.google.search":             "Google",
        "com.google.clock":              "Google Clock",

        // Meta
        "com.facebook.facebook":         "Facebook",
        "com.facebook.messenger":        "Messenger",
        "com.instagram.instagram":       "Instagram",
        "com.facebook.whatsapp":         "WhatsApp",
        "com.whatsapp.whatsapp":         "WhatsApp",
        "com.facebook.meta.reality":     "Meta Horizon",
        "com.facebook.threads":          "Threads",

        // Twitter / X
        "com.twitter.twitter":           "X (Twitter)",
        "com.atebits.tweetie2":          "X (Twitter)",

        // Microsoft
        "com.microsoft.teams":           "Microsoft Teams",
        "com.microsoft.office.outlook":  "Outlook",
        "com.microsoft.office.word":     "Word",
        "com.microsoft.office.excel":    "Excel",
        "com.microsoft.office.powerpoint": "PowerPoint",
        "com.microsoft.onenote":         "OneNote",
        "com.microsoft.onedrive":        "OneDrive",
        "com.microsoft.sharepoint":      "SharePoint",
        "com.microsoft.to-do":           "Microsoft To Do",
        "com.microsoft.bingnews":        "Bing",
        "com.microsoft.edge":            "Edge",
        "com.microsoft.copilot":         "Copilot",
        "com.microsoft.azuredatastudio": "Azure Data Studio",

        // Amazon
        "com.amazon.mobile.shopping.wood": "Amazon",
        "com.amazon.prime.video":        "Prime Video",
        "com.amazon.audible":            "Audible",
        "com.amazon.kindle":             "Kindle",
        "com.amazon.echo":               "Amazon Alexa",

        // Streaming
        "com.netflix.netflix":           "Netflix",
        "com.spotify.client":            "Spotify",
        "com.apple.tv":                  "Apple TV",
        "com.hulu.plus":                 "Hulu",
        "com.disneyplus.disneyplus":     "Disney+",
        "com.hbo.max":                   "Max (HBO)",
        "com.youtube.youtube":           "YouTube",
        "com.twitch.twitch":             "Twitch",
        "com.plex.plex":                 "Plex",

        // Communication
        "org.telegram.telegram":         "Telegram",
        "org.telegram.telegrammac":      "Telegram",
        "com.skype.skype":               "Skype",
        "com.discord.discord":           "Discord",
        "com.viber.viber":               "Viber",
        "jp.naver.line":                 "LINE",
        "com.signal.ios":                "Signal",
        "com.kakao.talk":                "KakaoTalk",
        "com.zoom.us":                   "Zoom",
        "us.zoom.videomeetings":         "Zoom",
        "com.slack.slack":               "Slack",

        // Apple第三方相关
        "com.dropbox.dropbox":           "Dropbox",
        "com.box.box":                   "Box",
        "com.evernote.evernote":         "Evernote",
        "com.notion.id":                 "Notion",
        "com.figma.figma":               "Figma",
        "com.linear.linear":             "Linear",
        "com.github.github":             "GitHub",
        "io.gitlab.gitlab":              "GitLab",

        // 出行 / 地图
        "com.uber.uberfleet":            "Uber",
        "com.lyft.ios":                  "Lyft",
        "com.airbnb.app":                "Airbnb",
        "com.booking.booking":           "Booking.com",
        "com.tripadvisor.tripadvisor":   "TripAdvisor",
        "com.expedia.expedia":           "Expedia",

        // 金融
        "com.paypal.here":               "PayPal",
        "com.squareup.cash":             "Cash App",
        "com.venmo.venmo":               "Venmo",
        "com.coinbase.coinbase":         "Coinbase",
        "com.robinhood.stocks":          "Robinhood",

        // 健康 / 运动
        "com.nike.nikeplus-gps":         "Nike Run Club",
        "com.adidas.runtastic":          "adidas Running",
        "com.strava.ios":                "Strava",
        "com.peloton.app":               "Peloton",
        "com.fitbit.fitbit":             "Fitbit",
        "com.garmin.connect.mobile":     "Garmin Connect",

        // 其他
        "com.linkedin.linkedin":         "LinkedIn",
        "com.pinterest.pinterest":       "Pinterest",
        "com.snapchat.snapchat":         "Snapchat",
        "com.reddit.reddit":             "Reddit",
        "com.tumblr.tumblr":             "Tumblr",
        "com.tinder.tinder":             "Tinder",
        "com.bumble.app":                "Bumble",
        "com.shopify.shopify":           "Shopify",
        "com.openai.chatgpt":            "ChatGPT",
        "com.anthropic.claude":          "Claude",
        "com.1password.1password":       "1Password",
        "com.lastpass.lastpass":         "LastPass",
        "com.nordvpn.macos":             "NordVPN",
        "com.expressvpn.expressvpn":     "ExpressVPN",
    ]

    // MARK: Apple 系统 & 第一方 App
    private static let apple: [String: String] = [
        "com.apple.mobilesafari":        "Safari",
        "com.apple.safari":              "Safari",
        "com.apple.mobilemail":          "邮件",
        "com.apple.mail":                "邮件",
        "com.apple.mobilecalendar":      "日历",
        "com.apple.calendar":            "日历",
        "com.apple.mobilenotes":         "备忘录",
        "com.apple.notes":               "备忘录",
        "com.apple.mobilephone":         "电话",
        "com.apple.mobilefacetime":      "FaceTime",
        "com.apple.facetime":            "FaceTime",
        "com.apple.mobilemessages":      "信息",
        "com.apple.maps":                "地图",
        "com.apple.music":               "音乐",
        "com.apple.podcasts":            "播客",
        "com.apple.news":                "新闻",
        "com.apple.arcade":              "Arcade",
        "com.apple.fitness":             "健身",
        "com.apple.health":              "健康",
        "com.apple.mobileslideshow":     "照片",
        "com.apple.photos":              "照片",
        "com.apple.mobilecamera":        "相机",
        "com.apple.weather":             "天气",
        "com.apple.stocks":              "股市",
        "com.apple.mobiletimer":         "时钟",
        "com.apple.reminders":           "提醒事项",
        "com.apple.shortcuts":           "快捷指令",
        "com.apple.appstore":            "App Store",
        "com.apple.mobilemeservice":     "iMessage",
        "com.apple.icloud.drive":        "iCloud Drive",
        "com.apple.cloudphotos":         "iCloud 照片",
        "com.apple.findmy":              "查找",
        "com.apple.mobiletv":            "Apple TV",
        "com.apple.webapp":              "Web App",
    ]

    // MARK: 生产力 / 开发工具
    private static let productivity: [String: String] = [
        "com.sublimetext.4":             "Sublime Text",
        "com.microsoft.vscodium":        "VSCodium",
        "com.microsoft.vscode":          "VS Code",
        "com.jetbrains.intellij":        "IntelliJ IDEA",
        "com.jetbrains.pycharm":         "PyCharm",
        "com.jetbrains.webstorm":        "WebStorm",
        "com.jetbrains.clion":           "CLion",
        "com.jetbrains.goland":          "GoLand",
        "com.jetbrains.rubymine":        "RubyMine",
        "com.jetbrains.appcode":         "AppCode",
        "com.github.atom":               "Atom",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.anthropic.claude":          "Claude",
        "com.openai.chatgpt":            "ChatGPT",
        "com.obsidian.md":               "Obsidian",
        "md.obsidian":                   "Obsidian",
        "com.adobe.reader":              "Adobe Reader",
        "com.adobe.illustrator":         "Illustrator",
        "com.adobe.photoshop":           "Photoshop",
        "com.adobe.premiere":            "Premiere Pro",
        "com.adobe.aftereffects":        "After Effects",
        "com.adobe.lightroom":           "Lightroom",
        "com.sketch.sketch":             "Sketch",
        "com.bohemiancoding.sketch3":    "Sketch",
        "com.figma.desktop":             "Figma",
        "com.postmanlabs.postman":       "Postman",
        "io.tableplus.tableplus":        "TablePlus",
        "com.sequelpro.SequelPro":       "Sequel Pro",
        "com.tinyapp.tableplus":         "TablePlus",
        "com.docker.docker":             "Docker",
        "com.proxyman.proxymandebug":    "Proxyman",
        "com.charlesproxy.charles":      "Charles",
        "com.burpsuite.ce":              "Burp Suite",
        "com.alfred.alfred":             "Alfred",
        "com.raycast.macos":             "Raycast",
        "com.nulana.remotixmac":         "Remotix",
        "com.microsoft.remotedesktop":   "Remote Desktop",
        "org.mozilla.firefox":           "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox Developer Edition",
        "com.operasoftware.opera":       "Opera",
        "com.vivaldi.vivaldi":           "Vivaldi",
        "com.brave.browser":             "Brave",
        "com.arc.app":                   "Arc",
        "com.apple.dt.xcode":            "Xcode",
        "com.apple.simulator":           "Simulator",
        "com.apple.instruments":         "Instruments",
        "com.termius.app":               "Termius",
        "com.panic.nova":                "Nova",
        "com.panic.coda":                "Coda",
        "com.transmit5.transmit":        "Transmit",
        "com.agilebits.onepassword-osx": "1Password",
        "com.bitwarden.desktop":         "Bitwarden",
        "com.tailscale.macos":           "Tailscale",
        "com.wireguard.macos":           "WireGuard",
        "com.parallels.desktop":         "Parallels Desktop",
        "com.vmware.fusion":             "VMware Fusion",
        "com.oracle.virtualbox":         "VirtualBox",
        "com.bartycrouch.app":           "BartyCrouch",
        "com.apple.iterm2":              "iTerm2",
        "com.googlecode.iterm2":         "iTerm2",
        "io.alacritty.alacritty":        "Alacritty",
        "com.nteligen.warp":             "Warp",
        "dev.warp.warp-stable":          "Warp",
    ]
}
