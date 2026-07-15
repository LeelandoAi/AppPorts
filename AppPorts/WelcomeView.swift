//
//  WelcomeView.swift
//  AppPort
//
//  Created by shimoko.com on 2025/11/18.
//

import SwiftUI

// MARK: - 欢迎界面

/// 应用首次启动的欢迎引导界面
///
/// 展示应用的核心功能、权限说明，并提供语言选择。主要功能：
/// - 🎨 精美的渐变背景和动画效果
/// - 📱 三大核心功能展示（应用瘦身、无感链接、随时还原）
/// - 🔐 完全磁盘访问权限检查和引导
/// - 🌐 多语言切换（20+ 语言支持）
///
/// ## 界面布局
/// 从上到下包含：
/// 1. **应用图标和标题**：带有缩放入场动画
/// 2. **功能特性列表**：三个主要功能说明卡片
/// 3. **权限提示卡片**：如果未授权则显示
/// 4. **开始使用按钮**：进入主界面
///
/// - Note: 界面使用弹性动画，提升用户体验
struct WelcomeView: View {
    /// 首次引导完成状态
    @Binding var hasCompletedOnboarding: Bool
    
    /// 语言管理器，用于多语言切换
    @ObservedObject private var languageManager = LanguageManager.shared
    
    /// 控制入场动画状态
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // MARK: - Ambient Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.blue.opacity(0.05),
                    Color.orange.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                // MARK: - Header Section
                VStack(spacing: 20) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 110, height: 110)
                        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                        .scaleEffect(isAnimating ? 1 : 0.9)
                        .opacity(isAnimating ? 1 : 0)
                        
                    VStack(spacing: 8) {
                        Text("欢迎使用 AppPorts".localized)
                            .font(.largeTitle.bold())
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .primary.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("您的应用，随处安家。".localized)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: isAnimating ? 0 : 10)
                    .opacity(isAnimating ? 1 : 0)
                }
                .padding(.top, 32)
                .padding(.bottom, 28)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                
                // MARK: - Features List
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "externaldrive.fill.badge.plus",
                        color: .orange,
                        title: "应用瘦身".localized,
                        description: "将庞大的应用程序一键迁移至外部移动硬盘，释放宝贵的 Mac 本地空间。".localized
                    )
                    
                    FeatureRow(
                        icon: "link",
                        color: .green,
                        title: "无感链接".localized,
                        description: "在原位置自动创建符号链接，系统和 Launchpad 依然能正常识别应用。".localized
                    )
                    
                    FeatureRow(
                        icon: "arrow.uturn.backward.circle.fill",
                        color: .blue,
                        title: "随时还原".localized,
                        description: "需要时，可随时将应用一键完整迁回本地 /Applications 目录。".localized
                    )
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 640)
                .offset(y: isAnimating ? 0 : 20)
                .opacity(isAnimating ? 1 : 0)
                
                Spacer(minLength: 32)
                
                // MARK: - Permission & Action
                VStack(spacing: 24) {
                    // Permission Card
                    if !hasAppManagementPermission {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                                .accessibilityHidden(true)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("需要 App 管理权限".localized)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("AppPorts 需要「App 管理」权限才能迁移应用数据。请在系统设置中勾选 AppPorts，然后重启应用。".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button(action: openAppManagementSettings) {
                                    HStack(spacing: 4) {
                                        Text("打开系统设置".localized).fontWeight(.semibold)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 10))
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.link)
                                .padding(.top, 2)
                                .accessibilityHint("双击打开系统设置".localized)
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
                        .accessibilityElement(children: .contain)
                    }
                    
                    // Main CTA
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            hasCompletedOnboarding = true
                        }
                    }) {
                        HStack {
                            Text(hasAppManagementPermission ? "开始使用".localized : "稍后设置并继续".localized)
                            Image(systemName: "arrow.right")
                                .accessibilityHidden(true)
                        }
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .clipShape(.rect(cornerRadius: 12))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .frame(maxWidth: 600)
                .offset(y: isAnimating ? 0 : 30)
                .opacity(isAnimating ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            LanguageSwitcher(languageManager: languageManager)
                .padding(20)
        }
        .onAppear {
            checkPermission()
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermission()
        }
    }
    
    @State private var hasAppManagementPermission = false
    
    func checkPermission() {
        let testFile = URL(fileURLWithPath: "/Applications/.appports-permission-test")
        do {
            try Data().write(to: testFile, options: .atomic)
            try FileManager.default.removeItem(at: testFile)
            hasAppManagementPermission = true
        } catch {
            hasAppManagementPermission = false
        }
    }
    
    func openAppManagementSettings() {
        let venturaURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement")
        let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")

        if #available(macOS 13.0, *), let url = venturaURL, NSWorkspace.shared.open(url) { return }
        if let url = legacyURL { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Components

struct LanguageSwitcher: View {
    @ObservedObject var languageManager: LanguageManager
    
    var body: some View {
        Menu {
            Button(AppLanguageCatalog.systemOptionTitle) {
                withAnimation { languageManager.language = "system" }
            }
            
            ForEach(AppLanguageCatalog.primaryLanguages) { option in
                Button(option.menuTitle) {
                    withAnimation { languageManager.language = option.code }
                }
            }
            
            Divider()
            Section(AppLanguageCatalog.aiSectionTitle) {
                ForEach(AppLanguageCatalog.aiTranslatedLanguages) { option in
                    Button(option.menuTitle) {
                        withAnimation { languageManager.language = option.code }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLanguageFlag).font(.subheadline)
                Text(currentLanguageName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .menuStyle(.borderlessButton)
        .focusable(false)
    }
    
    var currentLanguageOption: AppLanguageOption? {
        AppLanguageCatalog.option(for: languageManager.language)
    }

    var currentLanguageFlag: String {
        currentLanguageOption?.flag ?? "🌐"
    }

    var currentLanguageName: String {
        currentLanguageOption?.selectionTitle ?? AppLanguageCatalog.automaticSelectionTitle
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        )
        .onHover { mirroring in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = mirroring
            }
        }
        .accessibilityElement(children: .combine)
    }
}
