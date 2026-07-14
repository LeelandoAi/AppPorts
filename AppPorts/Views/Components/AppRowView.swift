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
    
    @State private var isHovered = false
    @State private var showDeleteLinkConfirmation = false
    
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
                    StatusBadge(app: app)
                    
                    if let size = app.size {
                        Text(size)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    } else {
                        Text("计算中...".localized)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                            .transition(.opacity)
                    }
                }
            }
            
            Spacer()
            
            if showDeleteLinkButton,
               (app.status == AppStatus.linked || app.status == AppStatus.orphanedLink),
               (isHovered || isSelected) {
                Button(role: .destructive, action: { showDeleteLinkConfirmation = true }) {
                    Image(systemName: "link.badge.minus")
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.red.opacity(0.1))
                .clipShape(Circle())
                .help("断开此链接并保留外部文件夹".localized)
                .accessibilityLabel("断开链接".localized)
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
        // Accessibility: Combine row into single element
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text(app.displayName) + Text(", ") +
            Text(AppStatus.localized(app.status)) +
            (app.size.map { Text(", \($0)") } ?? Text(""))
        )
        .contextMenu {
            Button("在 Finder 中显示".localized) {
                NSWorkspace.shared.activateFileViewerSelecting([app.path])
            }

            if (app.status == AppStatus.local || app.status == AppStatus.pendingMoveOut) && !app.isSystemApp, let onMoveOutWholeSymlink {
                Divider()
                Button("使用传统链接迁移".localized) {
                    onMoveOutWholeSymlink(app)
                }
            }

            if app.status == AppStatus.orphanedLink {
                Divider()
                Button("删除孤立链接".localized, role: .destructive) {
                    showDeleteLinkConfirmation = true
                }
            } else if app.status == AppStatus.linked {
                Divider()
                Button("断开链接".localized, role: .destructive) {
                    showDeleteLinkConfirmation = true
                }
            }

            if app.status == AppStatus.linked {
                Divider()

                if let onResign {
                    Button("重签名此应用".localized) {
                        onResign(app)
                    }
                }
            }

            if let onRestoreSignature, app.isResigned {
                Divider()
                Button("恢复原始签名".localized) {
                    onRestoreSignature(app)
                }
            }
        }
        .confirmationDialog(
            "断开链接".localized,
            isPresented: $showDeleteLinkConfirmation,
            titleVisibility: .visible
        ) {
            Button("断开".localized, role: .destructive) {
                onDeleteLink(app)
            }
            Button("取消".localized, role: .cancel) { }
        } message: {
            Text("断开此链接并保留外部文件夹".localized)
        }
    }
}
