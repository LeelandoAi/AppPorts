//
//  AppRowView.swift
//  AppPorts
//
//  Created by shimoko.com on 2026/2/6.
//

import SwiftUI
import AppKit

/// 列表行视图
struct AppRowView: View {
    let app: AppItem
    let isSelected: Bool
    let showDeleteLinkButton: Bool
    let showMoveBackButton: Bool
    let onDeleteLink: (AppItem) -> Void
    let onMoveBack: (AppItem) -> Void
    let onResign: ((AppItem) -> Void)?
    let onRestoreSignature: ((AppItem) -> Void)?
    var onMoveOutWholeSymlink: ((AppItem) -> Void)? = nil
    var onRepairDock: ((AppItem) -> Void)? = nil
    /// 签名被替换的应用：打开修复面板
    var onRepairSignature: ((AppItem) -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 14) {
            AppIconView(url: app.displayURL)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 8) {
                    StatusBadge(app: app, onRepairSignature: onRepairSignature)
                    
                    if let size = app.size {
                        Text(size)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    } else {
                        Text("计算中...".localized)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(app.displayName) + Text(", ") +
                Text(AppStatus.localized(app.status)) +
                (app.size.map { Text(", \($0)") } ?? Text(verbatim: ""))
            )
            
            Spacer()

            // 签名被替换的应用：把修复入口直接摆在行末。多数用户不会去右键菜单里找。
            if app.signatureReplaced, let onRepairSignature {
                Button(action: { onRepairSignature(app) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("修复".localized)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看修复步骤".localized)
                .help("查看修复步骤".localized)
            }
            
            if showDeleteLinkButton && (app.status == AppStatus.linked || app.status == AppStatus.orphanedLink) {
                Button(action: { onDeleteLink(app) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.red.opacity(0.1))
                .clipShape(Circle())
                .accessibilityLabel("断开此链接并删除文件".localized)
                .help("断开此链接并删除文件".localized)
            }
            
            if showMoveBackButton {
                Button(action: { onMoveBack(app) }) {
                    Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
                .accessibilityLabel("将应用迁移回本地".localized)
                .help("将应用迁移回本地".localized)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isHovered = hovering
            }
        }
        // 保留行内按钮，VoiceOver 可以分别选择应用信息和操作。
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("在 Finder 中显示".localized) {
                NSWorkspace.shared.activateFileViewerSelecting([app.path])
            }

            if app.status == AppStatus.linked || app.status == AppStatus.partialLinked,
               let onRepairDock {
                Divider()
                Button("修复 Dock 图标".localized) {
                    onRepairDock(app)
                }
            }

            if (app.status == AppStatus.local || app.status == AppStatus.pendingMoveOut) && !app.isSystemApp, let onMoveOutWholeSymlink {
                Divider()
                Button("使用传统链接迁移".localized) {
                    onMoveOutWholeSymlink(app)
                }
            }

            if app.status == AppStatus.orphanedLink {
                Divider()
                Button("删除孤立链接".localized) {
                    onDeleteLink(app)
                }
            }

            if app.signatureReplaced, let onRepairSignature {
                Divider()
                Button("查看修复步骤".localized) {
                    onRepairSignature(app)
                }
            }

            // 应用本体迁移后弹「已损坏」时的兜底；签名已被替换的应用再签只会更糟，不提供。
            if !app.isFolder,
               !app.isSystemApp,
               !app.signatureReplaced,
               app.status != AppStatus.orphanedLink,
               app.displayURL.pathExtension.lowercased() == "app",
               let onResign {
                Divider()
                Button("重签名此应用".localized) {
                    onResign(app)
                }
                .disabled(app.isRunning)
            }

            if let onRestoreSignature, app.isResigned {
                Divider()
                Button("恢复原始签名".localized) {
                    onRestoreSignature(app)
                }
            }
        }
    }
}
