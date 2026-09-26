//
//  SignatureRepairSheet.swift
//  AppPorts
//

import SwiftUI

/// 签名被替换的应用的修复面板：四步走，全程不删除任何数据。
///
/// 1. 把该应用所有已链接的容器目录还原回本地
/// 2. 应用本体迁回本地（如果它在外置盘上）
/// 3. 从完整备份恢复签名，或由用户从官方渠道覆盖安装
/// 4. 可选：恢复后用挂载迁移把数据放回 APFS 外置盘
///
/// 顺序不能变：重装完的应用是正常的沙盒应用，读不到符号链接后面的数据，
/// 用户会误以为"重装了还是空白"。
struct SignatureRepairSheet: View {
    let app: AppItem
    let onRestoreSignature: (AppItem) -> Void
    /// 迁回本地（复用应用页的还原流程），面板会先关闭
    let onMoveBack: (AppItem) -> Void
    /// 跳到「应用数据」页并选中该应用
    let onOpenDataDirs: (AppItem) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var operationState = AppOperationState.shared

    @State private var linkedContainerItems: [DataDirItem] = []
    @State private var isScanning = true
    @State private var isRestoring = false
    @State private var restoreProgressText = ""
    @State private var errorMessage: String?
    @State private var realAppURL: URL?
    @State private var currentAuthority: String?
    @State private var signatureRestored = false

    private var appIsOnExternalDrive: Bool {
        app.status == AppStatus.linked || app.status == AppStatus.partialLinked
    }

    private var stepOneDone: Bool { !isScanning && linkedContainerItems.isEmpty }
    private var stepTwoDone: Bool { !appIsOnExternalDrive }
    private var stepThreeDone: Bool { signatureRestored }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                AppIconView(url: app.displayURL, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "修复「%@」的签名".localized, app.displayName))
                        .font(.title3.bold())
                    Text("AppPorts 曾用 Ad-hoc 签名替换了它的开发者签名。在 macOS 27 上这样的应用可能无法打开。按下面的顺序处理，数据不会丢失；能正常打开的应用可以跳过第 3 步。".localized)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            stepRow(
                number: 1,
                title: "还原容器数据".localized,
                done: stepOneDone,
                detail: isScanning
                    ? "正在检查容器目录…".localized
                    : (linkedContainerItems.isEmpty
                        ? "容器里没有指向外置盘的链接。".localized
                        : String(format: "还有 %lld 个容器目录指向外置盘。重装前必须先还原，否则重装后应用仍读不到数据。".localized, Int64(linkedContainerItems.count)))
            ) {
                if !stepOneDone {
                    Button(isRestoring ? "正在还原…".localized : "全部还原".localized) {
                        restoreAllContainerItems()
                    }
                    .disabled(isRestoring || isScanning || operationState.isBusy)
                }
            }
            if isRestoring, !restoreProgressText.isEmpty {
                Text(restoreProgressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 34)
            }

            stepRow(
                number: 2,
                title: "应用本体迁回本地".localized,
                done: stepTwoDone,
                detail: stepTwoDone
                    ? "应用本体在本地。".localized
                    : "应用本体在外置盘上，本地只是启动壳。直接覆盖安装会把壳盖掉，外置副本变成孤儿，先迁回来。".localized
            ) {
                if !stepTwoDone {
                    Button("迁回本地".localized) {
                        onDismiss()
                        onMoveBack(app)
                    }
                    .disabled(!stepOneDone || operationState.isBusy)
                }
            }

            stepRow(
                number: 3,
                title: "恢复原始签名或从官方渠道重装".localized,
                done: stepThreeDone,
                detail: stepThreeDone
                    ? String(format: "签名已恢复：%@".localized, currentAuthority ?? "")
                    : String(format: "当前签名：%@。退出应用后，可从完整备份恢复原始签名；旧备份需要选择同版本官方原版。也可以从 App Store 或官网下载重装。应用数据目录不会被替换。".localized, currentAuthority ?? "Ad-hoc")
            ) {
                if !stepThreeDone {
                    Button("恢复原始签名".localized) {
                        onDismiss()
                        onRestoreSignature(app)
                    }
                    .disabled(!stepOneDone || operationState.isBusy || app.isRunning)
                    if app.isAppStoreApp {
                        Button("打开 App Store".localized) {
                            openAppStore()
                        }
                    } else {
                        Button("在 Finder 中显示".localized) {
                            NSWorkspace.shared.activateFileViewerSelecting([realAppURL ?? app.displayURL])
                        }
                    }
                    Button("重新检查".localized) {
                        refreshSignatureState()
                    }
                }
            }
            if let bundleID = realAppURL.flatMap(CodeSigner.bundleIdentifier(at:)), !stepThreeDone {
                Text(String(format: "Bundle ID：%@".localized, bundleID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 34)
            }

            stepRow(
                number: 4,
                title: "可选：用挂载迁移把数据放回外置盘".localized,
                done: false,
                detail: "恢复签名或重装后，在「应用数据」页使用「挂载迁移」。需要 APFS 外置盘，第一次打开应用时点允许授权框。".localized
            ) {
                Button("前往应用数据".localized) {
                    onDismiss()
                    onOpenDataDirs(app)
                }
                .disabled(!(stepOneDone && stepTwoDone && stepThreeDone))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Link("查看完整说明".localized, destination: DocumentationLink.url(page: "macos-27"))
                    .font(.caption)
                Spacer()
                Button("关闭".localized) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            refreshSignatureState()
            scanContainerItems()
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private func stepRow<Actions: View>(
        number: Int,
        title: String,
        done: Bool,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(done ? .secondary : .primary)
                Text(detail)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { actions() }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 状态刷新

    private func refreshSignatureState() {
        let url = (try? CodeSigner.resolveAppURL(at: app.displayURL)) ?? app.displayURL
        realAppURL = url
        Task.detached(priority: .userInitiated) {
            let signer = CodeSigner()
            let authority = await signer.getSigningIdentity(appURL: url)
            let status = await signer.verify(appURL: url)
            let adHoc = authority == nil || status == .adHoc
            await MainActor.run {
                currentAuthority = authority ?? "Ad-hoc"
                signatureRestored = !adHoc && status == .valid
            }
        }
    }

    private func scanContainerItems() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let items = await DataDirScanner().scanLibraryDirs(for: app)
            let linked = items.filter {
                ($0.type == .containers || $0.type == .groupContainers)
                    && [DataDirStatus.linked, DataDirStatus.needsNormalization, DataDirStatus.existingSymlink].contains($0.status)
                    && $0.linkedDestination != nil
            }
            await MainActor.run {
                linkedContainerItems = linked
                isScanning = false
            }
        }
    }

    // MARK: - 动作

    private func restoreAllContainerItems() {
        let workflow = SignatureRepairRestoreWorkflow(
            appURL: app.displayURL,
            runningApplications: {
                NSWorkspace.shared.runningApplications.map {
                    AppRunningState.RunningApplication(bundleURL: $0.bundleURL, bundleIdentifier: $0.bundleIdentifier)
                }
            }
        )
        let token: UUID
        switch workflow.begin(operationState: AppOperationState.shared) {
        case .started(let operationToken):
            token = operationToken
        case .appRunning:
            showAppRunningRestoreError()
            return
        case .busy:
            return
        }
        isRestoring = true
        errorMessage = nil
        let items = linkedContainerItems
        AppLogger.shared.logContext(
            "修复面板：批量还原容器目录",
            details: [("app_name", app.displayName), ("count", String(items.count))]
        )
        Task { @MainActor in
            defer {
                isRestoring = false
                AppOperationState.shared.finish(token)
                scanContainerItems()
            }
            let mover = DataDirMover()
            let outcome = await workflow.run(items: items) { item, index in
                restoreProgressText = String(format: "正在还原 %lld / %lld：%@".localized, Int64(index + 1), Int64(items.count), item.name)
                try await mover.restore(item: item) { progress in
                    await MainActor.run {
                        restoreProgressText = String(
                            format: "正在还原 %lld / %lld：%@（%@）".localized,
                            Int64(index + 1), Int64(items.count), item.name,
                            LocalizedByteCountFormatter.string(fromByteCount: progress.copiedBytes)
                        )
                    }
                }
            }
            switch outcome {
            case .completed:
                break
            case .appRunning:
                showAppRunningRestoreError()
            case .restoreFailed(let item, let error):
                AppLogger.shared.logError(
                    "修复面板：还原容器目录失败",
                    error: error,
                    errorCode: "SIGNATURE-REPAIR-RESTORE-FAILED",
                    context: [("app_name", app.displayName), ("item_name", item.name)],
                    relatedURLs: [("local", item.path)]
                )
                errorMessage = String(format: "「%@」还原失败：%@".localized, item.name, error.localizedDescription)
            }
        }
    }

    private func showAppRunningRestoreError() {
        errorMessage = String(format: "「%@」正在运行中，请先关闭该应用后再还原其数据目录。".localized, app.displayName)
        AppLogger.shared.logContext(
            "修复面板：拒绝还原正在运行的应用数据",
            details: [("app_name", app.displayName), ("app_path", app.displayURL.path)],
            level: "WARN"
        )
    }

    private func openAppStore() {
        if let url = URL(string: "macappstore://apps.apple.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 修复面板的批量还原边界。保存的是进程查询，而不是查询结果；开始批次和每个目录动手前都重新读取。
@MainActor
struct SignatureRepairRestoreWorkflow {
    enum StartResult: Equatable {
        case started(UUID)
        case appRunning
        case busy
    }

    enum Outcome {
        case completed
        case appRunning
        case restoreFailed(item: DataDirItem, error: Error)
    }

    let appURL: URL
    let runningApplications: @MainActor () -> [AppRunningState.RunningApplication]

    /// 同步申请令牌，保持按钮点击与进入忙碌状态之间没有异步空隙。
    func begin(operationState: AppOperationState) -> StartResult {
        guard !appIsRunning else { return .appRunning }
        guard let token = operationState.begin() else { return .busy }
        return .started(token)
    }

    func run(
        items: [DataDirItem],
        restore: @MainActor (DataDirItem, Int) async throws -> Void
    ) async -> Outcome {
        for (index, item) in items.enumerated() {
            // 上一个目录还原期间应用可能重新启动，不能复用批次开始时的检查结果。
            guard !appIsRunning else { return .appRunning }
            do {
                try await restore(item, index)
            } catch {
                return .restoreFailed(item: item, error: error)
            }
        }
        return .completed
    }

    private var appIsRunning: Bool {
        AppRunningState.isRunning(appURL: appURL, applications: runningApplications())
    }
}
