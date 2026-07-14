//
//  StatusBadge.swift
//  AppPorts
//
//  Created by shimoko.com on 2026/2/6.
//

import SwiftUI

// MARK: - 状态徽章组件

/// 应用状态徽章视图
///
/// 以胶囊形状的徽章显示应用的当前状态，包括：
/// - ✅ 已链接（绿色）：应用已迁移到外部存储并创建了符号链接
/// - ▶️ 运行中（紫色）：应用当前正在运行
/// - 🔒 系统（灰色）：macOS 系统应用
/// - 📱 非原生（粉色）：iOS/iPadOS 应用（通过 Apple Silicon 运行）
/// - 🏪 商店（蓝色）：Mac App Store 应用
/// - 📀 未链接（橙色）：应用在外部存储但未链接回本地
/// - 💻 本地（次要色）：普通本地应用
///
/// ## 设计特点
/// - 使用 SF Symbols 图标增强视觉识别
/// - 颜色编码快速传达状态信息
/// - 圆角胶囊形状现代简洁
/// - 半透明背景和边框提升层次感
///
/// - Note: 自动支持无障碍功能（Accessibility）
private enum BadgeID: Hashable {
    case migrationLock
    case linked
    case partialLinked
    case orphanedLink
    case unlinked
    case external
    case pendingMoveOut
    case sparkle
    case electron
    case running
    case system
    case nonNative
    case appStore
    case local
    case resigned
}

private struct BadgeConfig: Identifiable {
    let id: BadgeID
    let text: String
    let icon: String
    let color: Color
    let isTappable: Bool
}

private func localizedStatusBadgeText(_ text: String) -> String {
    switch text {
    case AppStatus.local, AppStatus.linked, AppStatus.unlinked, AppStatus.partialLinked, AppStatus.orphanedLink, AppStatus.external, AppStatus.pendingMoveOut:
        return AppStatus.localized(text)
    case "锁定迁移":
        return "锁定迁移".localized
    case "非锁定迁移":
        return "非锁定迁移".localized
    case "运行中":
        return "运行中".localized
    case "系统":
        return "系统".localized
    case "非原生":
        return "非原生".localized
    case "商店":
        return "商店".localized
    case "已重签名":
        return "已重签名".localized
    default:
        return text
    }
}

struct StatusBadge: View {
    /// 应用项目数据
    let app: AppItem

    /// 所有适用的标签列表
    private var badges: [BadgeConfig] {
        var result: [BadgeConfig] = []

        // 1. 链接状态标签
        if app.status == AppStatus.linked {
            if app.needsLock {
                let locked = app.isExternalAppLocked
                result.append(BadgeConfig(
                    id: .migrationLock,
                    text: locked ? "锁定迁移" : "非锁定迁移",
                    icon: locked ? "lock.fill" : "lock.open",
                    color: locked ? .green : .orange,
                    isTappable: true
                ))
            } else if app.hasSelfUpdater {
                // 原生自更新 app（Chrome、Edge 等）不加锁，显示"已链接"
                result.append(BadgeConfig(id: .linked, text: AppStatus.linked, icon: "link", color: .green, isTappable: false))
            } else {
                result.append(BadgeConfig(id: .linked, text: AppStatus.linked, icon: "link", color: .green, isTappable: false))
            }
        } else if app.status == AppStatus.partialLinked {
            result.append(BadgeConfig(id: .partialLinked, text: AppStatus.partialLinked, icon: "link.badge.plus", color: .yellow, isTappable: false))
        } else if app.status == AppStatus.orphanedLink {
            result.append(BadgeConfig(id: .orphanedLink, text: AppStatus.orphanedLink, icon: "link.badge.exclamationmark", color: .red, isTappable: false))
        } else if app.status == AppStatus.unlinked {
            result.append(BadgeConfig(id: .unlinked, text: AppStatus.unlinked, icon: "externaldrive.badge.xmark", color: .orange, isTappable: false))
        } else if app.status == AppStatus.external {
            result.append(BadgeConfig(id: .external, text: AppStatus.external, icon: "externaldrive", color: .orange, isTappable: false))
        } else if app.status == AppStatus.pendingMoveOut {
            result.append(BadgeConfig(id: .pendingMoveOut, text: AppStatus.pendingMoveOut, icon: "arrow.up.right.circle", color: .cyan, isTappable: false))
        }

        // 2. 框架标签（独立于链接状态）
        if app.isSparkleApp {
            result.append(BadgeConfig(id: .sparkle, text: "Sparkle", icon: "arrow.triangle.2.circlepath", color: .teal, isTappable: true))
        }
        if app.isElectronApp {
            result.append(BadgeConfig(id: .electron, text: "Electron", icon: "atom", color: .indigo, isTappable: true))
        }

        // 3. 类型标签
        if app.isRunning {
            result.append(BadgeConfig(id: .running, text: "运行中", icon: "play.fill", color: .purple, isTappable: false))
        } else if app.isSystemApp {
            result.append(BadgeConfig(id: .system, text: "系统", icon: "lock.fill", color: .gray, isTappable: false))
        } else if app.isIOSApp {
            result.append(BadgeConfig(id: .nonNative, text: "非原生", icon: "iphone", color: .pink, isTappable: false))
        } else if app.isAppStoreApp {
            result.append(BadgeConfig(id: .appStore, text: "商店", icon: "applelogo", color: .blue, isTappable: AppMigrationService.isMASExternalInstallSupported))
        }

        // 5. MAS 外部安装标签（复用商店标签，附加外部安装说明）
        if app.isMASExternal && !app.isAppStoreApp {
            result.append(BadgeConfig(id: .appStore, text: "商店", icon: "applelogo", color: .blue, isTappable: true))
        }

        // 4. 如果没有任何标签，显示"本地"
        if result.isEmpty {
            result.append(BadgeConfig(id: .local, text: AppStatus.local, icon: "macmini", color: .secondary, isTappable: false))
        }

        return result
    }
    
    /// 点击标签时显示的说明文字
    private func badgeInfoMessage(for badge: BadgeConfig) -> String? {
        switch badge.text {
        case "Sparkle":
            return "此应用使用 Sparkle 框架自动更新。迁移到外部存储后，应用内更新可能导致外部应用丢失。建议使用锁定迁移保护数据安全。".localized
        case "Electron":
            return "此应用基于 Electron 框架，支持自动更新。迁移到外部存储后，应用内更新可能导致外部应用丢失。建议使用锁定迁移保护数据安全。".localized
        case "锁定迁移":
            return "此应用已被迁移到外部存储并锁定。锁定状态可防止应用内更新破坏外部应用。如需更新，请通过 AppPorts 迁回本地后再更新。".localized
        case "非锁定迁移":
            return "此应用已迁移到外部存储但未锁定。应用内更新可能删除外部应用。建议迁回本地后重新迁移并选择锁定模式。".localized
        case "商店" where app.isMASExternal:
            return "此应用位于外部磁盘的 Applications 目录，由 macOS 原生管理（macOS 15.1+ 功能）。App Store 可直接在此目录进行增量更新，无需通过 AppPorts 迁回。".localized
        default:
            return nil
        }
    }

    /// 单个标签胶囊
    private func badgeView(for badge: BadgeConfig) -> some View {
        HStack(spacing: 4) {
            Image(systemName: badge.icon)
                .font(.system(size: 9, weight: .bold))
            Text(localizedStatusBadgeText(badge.text))
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(badge.color)
        .background(badge.color.opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(badge.color.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges) { badge in
                if badge.isTappable, let message = badgeInfoMessage(for: badge) {
                    TappableBadge(badge: badge, message: message)
                } else {
                    badgeView(for: badge)
                }
            }

            if app.isResigned {
                badgeView(for: BadgeConfig(id: .resigned, text: "已重签名", icon: "seal.fill", color: .teal, isTappable: false))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 可点击标签（独立 popover，避免 race condition）
private struct TappableBadge: View {
    let badge: BadgeConfig
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: badge.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(localizedStatusBadgeText(badge.text))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(badge.color)
            .background(badge.color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(badge.color.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedStatusBadgeText(badge.text))
        .accessibilityHint(message)
        .help(message)
        .popover(isPresented: $isPresented) {
            Text(message)
                .font(.system(size: 12))
                .padding(12)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
