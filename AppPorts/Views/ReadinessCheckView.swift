//
//  ReadinessCheckView.swift
//  AppPorts
//
//  迁移前的准备情况：权限是否齐全、外部存储格式是否满足要求。
//

import SwiftUI

// MARK: - 准备情况列表

/// 迁移前的准备情况检查。
///
/// 欢迎屏第二屏与「设置」里共用同一组设置页风格的卡片，
/// 只有刷新入口的位置不同：欢迎屏放在卡片下方（让两屏的卡片从同一高度开始），
/// 「设置」里放在卡片上方。
struct ReadinessCheckView: View {
    /// 刷新入口相对卡片的位置
    enum RefreshPlacement {
        /// 卡片上方（「设置」弹窗里使用）
        case top
        /// 卡片下方，可与左侧脚注并排（欢迎屏使用）
        case bottom
    }

    /// 刷新入口的位置
    var refreshPlacement: RefreshPlacement = .top

    /// 放在刷新入口左侧的说明文字，仅 `refreshPlacement == .bottom` 时显示
    var footnote: String?

    @State private var items: [LaunchReadinessChecker.Item] = []
    @State private var isChecking = false

    init(refreshPlacement: RefreshPlacement = .top, footnote: String? = nil) {
        self.refreshPlacement = refreshPlacement
        self.footnote = footnote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if refreshPlacement == .top {
                refreshRow
            }

            if items.isEmpty {
                loadingCard
            } else {
                ForEach(items) { item in
                    ReadinessCard(item: item) { action in
                        openSettings(for: action)
                    }
                }
            }

            if refreshPlacement == .bottom {
                refreshRow
            }
        }
        .onAppear(perform: refresh)
        // 去系统设置改完权限切回来，自动重新检查一次。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    /// 一行刷新入口：左侧是可选脚注，右侧是「重新检查」。
    private var refreshRow: some View {
        HStack(spacing: 8) {
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Button(action: refresh) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("重新检查".localized)
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .disabled(isChecking)
        }
        .padding(.top, refreshPlacement == .bottom ? 2 : 0)
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在检查…".localized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .settingsCardBackground()
    }

    /// 重新执行三项检查。外部存储格式要问 diskutil，所以是异步的。
    private func refresh() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let result = await LaunchReadinessChecker().check()
            await MainActor.run {
                items = result
                isChecking = false
            }
        }
    }

    private func openSettings(for action: LaunchReadinessChecker.Item.Action) {
        for url in action.settingsURLs where NSWorkspace.shared.open(url) {
            return
        }
    }
}

// MARK: - 准备情况弹窗

/// 「设置」里点「检查」后弹出的准备情况面板。
struct ReadinessCheckSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "checkmark.shield")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("准备情况".localized)
                    .font(.title2.bold())

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("关闭".localized)
            }

            ReadinessCheckView()

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 420)
    }
}

// MARK: - 卡片

/// 准备情况里的一张卡片，缺权限时右侧是可点击的「去授权」。
private struct ReadinessCard: View {
    let item: LaunchReadinessChecker.Item
    let onAction: (LaunchReadinessChecker.Item.Action) -> Void

    var body: some View {
        SettingsStyleCard(
            icon: symbolName,
            iconColor: statusColor,
            title: item.title,
            detail: item.detail
        ) {
            if let action = item.action {
                Button(action: { onAction(action) }) {
                    HStack(spacing: 3) {
                        Text("去授权".localized)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("去设置授予权限".localized)
            } else {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
            }
        }
    }

    private var symbolName: String {
        switch item.level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var statusText: String {
        switch item.level {
        case .ok: return "已就绪".localized
        case .warning: return "注意".localized
        case .failed: return "需要授权".localized
        }
    }

    private var statusColor: Color {
        switch item.level {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

// MARK: - 设置页风格的卡片

/// 设置页统一的卡片容器：淡底色 + 圆角 + 内边距。
extension View {
    func settingsCardBackground() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
    }
}

/// 设置页风格的卡片：彩色图标 + 标题，下面是说明，右侧可选控件。
struct SettingsStyleCard<Accessory: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let accessory: Accessory

    init(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)

                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            accessory
        }
        .settingsCardBackground()
    }
}

extension SettingsStyleCard where Accessory == EmptyView {
    init(icon: String, iconColor: Color, title: String, detail: String) {
        self.init(icon: icon, iconColor: iconColor, title: title, detail: detail) {
            EmptyView()
        }
    }
}
