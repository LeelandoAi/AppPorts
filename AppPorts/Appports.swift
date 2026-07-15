//
//  AppPorts.swift
//  AppPorts
//
//  Created by shimoko.com on 2025/11/19.
//

import SwiftUI

// MARK: - 应用入口

/// AppPorts 应用的主入口点
///
/// 负责应用的初始化和主窗口配置。主要功能：
/// - 🚀 应用启动时记录系统诊断信息
/// - 🌐 全局语言管理（20+ 语言支持）
/// - 📝 自定义菜单栏（关于、语言、日志）
/// - 👋 首次启动欢迎界面
///
/// ## 应用流程
/// 1. 启动 -> 记录系统信息
/// 2. 显示欢迎界面（首次启动）
/// 3. 用户确认权限 -> 进入主界面
///
/// - Note: 使用 `@main` 标记为 SwiftUI 应用的入口点
/// App 生命周期代理
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct AppMoverApp: App {
    /// 全局语言管理器
    @StateObject private var languageManager = LanguageManager.shared

    /// 记录首次引导是否已经完成
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showAboutSheet = false
    @State private var showClearLogConfirmation = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // 应用启动时记录系统诊断信息
        AppLogger.shared.logLaunchSession()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    WelcomeView(hasCompletedOnboarding: $hasCompletedOnboarding)
                } else {
                    ContentView()
                }
            }

            .environment(\.locale, languageManager.locale)

            .id(languageManager.language)
            
            // 关于页面弹窗
            .sheet(isPresented: $showAboutSheet) {
                AboutView()
                    // 确保弹出的 Sheet 也能收到语言更新
                    .environment(\.locale, languageManager.locale)
                    .id(languageManager.language)
            }
            .confirmationDialog(
                "清空日志".localized,
                isPresented: $showClearLogConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空日志".localized, role: .destructive) {
                    AppLogger.shared.clearLog()
                }
                Button("取消".localized, role: .cancel) { }
            }
            .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 720)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AppSearchCommands()

            // 原有的关于菜单
            CommandGroup(replacing: .appInfo) {
                Button("关于 AppPorts...".localized) {
                    showAboutSheet = true
                }
            }
            
            CommandMenu("语言".localized) {
                Button(AppLanguageCatalog.systemOptionTitle) { languageManager.language = "system" }
                .keyboardShortcut("0", modifiers: [.command, .option])
                
                Divider()
                
                ForEach(AppLanguageCatalog.primaryLanguages) { option in
                    if let shortcut = option.keyboardShortcut {
                        Button(option.menuTitle) { languageManager.language = option.code }
                            .keyboardShortcut(shortcut, modifiers: [.command, .option])
                    } else {
                        Button(option.menuTitle) { languageManager.language = option.code }
                    }
                }

                Divider()
                Text(AppLanguageCatalog.aiSectionTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(AppLanguageCatalog.aiTranslatedLanguages) { option in
                    Button(option.menuTitle) { languageManager.language = option.code }
                }
            }
            
            // 日志管理菜单
            CommandMenu("日志".localized) {
                Button("在 Finder 中查看日志".localized) {
                    AppLogger.shared.openLogInFinder()
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])

                Button("导出诊断包（菜单）".localized) {
                    AppLogger.shared.exportDiagnosticPackageInteractively()
                }
                
                Button("设置日志位置...".localized) {
                    let panel = NSOpenPanel()
                    panel.prompt = "选择日志保存位置".localized
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        let logFile = url.appendingPathComponent("AppPorts_Log.txt")
                        AppLogger.shared.setLogPath(logFile)
                    }
                }
                
                Divider()
                
                // 日志开关
                Button(AppLogger.shared.isLoggingEnabled ? "✅ " + "启用日志记录".localized : "启用日志记录".localized) {
                    AppLogger.shared.isLoggingEnabled.toggle()
                }
                
                // 日志大小设置
                Menu("最大日志大小".localized) {
                    let currentSize = AppLogger.shared.maxLogSize
                    
                    Button(currentSize == 1 * 1024 * 1024 ? "✅ 1 MB" : "1 MB") {
                        AppLogger.shared.maxLogSize = 1 * 1024 * 1024
                    }
                    Button(currentSize == 5 * 1024 * 1024 ? "✅ 5 MB" : "5 MB") {
                        AppLogger.shared.maxLogSize = 5 * 1024 * 1024
                    }
                    Button(currentSize == 10 * 1024 * 1024 ? "✅ 10 MB" : "10 MB") {
                        AppLogger.shared.maxLogSize = 10 * 1024 * 1024
                    }
                    Button(currentSize == 50 * 1024 * 1024 ? "✅ 50 MB" : "50 MB") {
                        AppLogger.shared.maxLogSize = 50 * 1024 * 1024
                    }
                    Button(currentSize == 100 * 1024 * 1024 ? "✅ 100 MB" : "100 MB") {
                        AppLogger.shared.maxLogSize = 100 * 1024 * 1024
                    }
                }
                
                Divider()
                
                Text(String(format: "当前大小: %@".localized, AppLogger.shared.getLogSizeString()))
                    .font(.caption)
                
                Button("清空日志".localized, role: .destructive) {
                    showClearLogConfirmation = true
                }
            }
            
            // 帮助菜单 — 添加文档入口
            CommandGroup(after: .help) {
                Button("用户文档".localized) {
                    if let url = URL(string: "https://docs-appports.shimoko.com/") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        #if os(macOS)
        Settings {
            AppStoreSettingsView()
                .environment(\.locale, languageManager.locale)
                .id(languageManager.language)
        }
        #endif
    }
}
