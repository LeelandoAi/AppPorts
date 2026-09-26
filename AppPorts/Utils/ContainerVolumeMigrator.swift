//
//  ContainerVolumeMigrator.swift
//  AppPorts
//

import Darwin
import Foundation

// MARK: - 容器数据挂载迁移器

/// 沙盒应用容器数据的挂载迁移器。
///
/// 与 `DataDirMover` 的符号链接策略并列：沙盒应用无法透过符号链接访问容器外路径
/// （内核按解析后的真实路径判定），这里改为在外置盘的 APFS 容器中新建一个卷，
/// 把它挂载到容器内的原目录上。路径不离开容器，应用签名与 entitlements 不做任何修改。
///
/// ## 操作流程
/// - **迁移**：建卷 → 临时挂载并复制 → 卸载 → 原目录改名为安全备份 → 在原路径挂载 → 写记录 → 清理备份
/// - **还原**：确保已挂载 → 复制到暂存目录 → 卸载 → 暂存目录改回原路径 → 删卷 → 删记录
/// - **挂载 / 卸载**：只处理已有记录。未挂载期间挂载点保持 000 权限，
///   应用在盘不在时只会看到空目录，不会把新数据写进本地形成分叉。
actor ContainerVolumeMigrator {

    enum MigrationError: LocalizedError {
        case sourceNotDirectory(URL)
        case alreadyManaged(URL)
        case externalNotAPFS(URL)
        case encryptedDestination
        case unexpectedMountedVolume(URL)
        case volumeCreationFailed(String)
        case mountFailed(URL, String)
        case mountVerificationFailed(URL)
        case mountPointNotEmpty(URL)
        case unmountFailed(URL, String)
        case volumeUnavailable(String)
        case insufficientSpace(required: Int64, available: Int64)
        case copyFailed(Error)
        case switchFailed(Error)
        case rollbackIncomplete(backup: URL, volumeName: String, volumeUUID: String, underlying: Error)
        /// 还原时本地副本已复制好，但没能换到原路径。外置卷和记录保持不变。
        case restoreIncomplete(staging: URL, underlying: Error)
        case restoreRecordRecovery(staging: URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceNotDirectory(let url):
                return String(format: "该路径不是真实目录，无法挂载迁移：%@".localized, url.lastPathComponent)
            case .alreadyManaged(let url):
                return String(format: "该目录已经是挂载迁移项：%@".localized, url.lastPathComponent)
            case .externalNotAPFS(let url):
                return String(format: "外部存储不是 APFS 格式，无法创建挂载卷：%@".localized, url.path)
            case .encryptedDestination:
                return "所选 APFS 卷已加密，新建数据卷不会继承它的密码。为避免降低数据保护，当前版本不支持向此位置挂载迁移；原数据未改动，可以继续保留现状。".localized
            case .unexpectedMountedVolume(let url):
                return String(format: "此目录挂载的卷与迁移记录不一致，已停止操作并保留数据：%@".localized, url.path)
            case .volumeCreationFailed(let output):
                return String(format: "创建外置卷失败：%@".localized, output)
            case .mountFailed(let url, let output):
                return String(format: "挂载到容器目录失败：%@\n%@".localized, url.path, output)
            case .mountVerificationFailed(let url):
                return String(format: "挂载后校验失败，该路径不是挂载点：%@".localized, url.path)
            case .mountPointNotEmpty(let url):
                return String(format: "挂载点目录不为空，为避免覆盖数据已停止操作：%@".localized, url.path)
            case .unmountFailed(let url, let output):
                return String(format: "卸载失败，可能有应用正在使用该目录：%@\n%@".localized, url.path, output)
            case .volumeUnavailable(let name):
                return String(format: "找不到外置卷「%@」，请确认外部存储已连接".localized, name)
            case .insufficientSpace(let required, let available):
                return String(
                    format: "空间不足：需要约 %@ 可用空间，目前只有 %@。未做任何改动。".localized,
                    LocalizedByteCountFormatter.string(fromByteCount: required),
                    LocalizedByteCountFormatter.string(fromByteCount: available)
                )
            case .copyFailed(let error):
                return String(format: "复制失败：%@".localized, error.localizedDescription)
            case .switchFailed(let error):
                return String(format: "切换挂载点失败，数据已紧急还原：%@".localized, error.localizedDescription)
            case .rollbackIncomplete(let backup, let volumeName, let volumeUUID, let error):
                return String(
                    format: "挂载迁移未完成，原数据保留在「%@」，未覆盖当前路径。外置卷「%@」（%@）也已保留。请检查挂载点后再恢复。%@".localized,
                    backup.path, volumeName, volumeUUID, error.localizedDescription
                )
            case .restoreIncomplete(let staging, let error):
                return String(
                    format: "还原没有完成：外置卷上的数据和迁移记录保持不变，已复制到本机的副本保留在「%@」。%@".localized,
                    staging.path,
                    error.localizedDescription
                )
            case .restoreRecordRecovery(let staging, let error):
                return String(
                    format: "还原未完成，已复制的本地数据保留在「%@」，外置卷也已保留。请检查迁移记录和挂载状态后重试。%@".localized,
                    staging.path, error.localizedDescription
                )
            }
        }
    }

    struct MigrationResult: Sendable {
        let record: ContainerMountRecord
        let cleanupWarning: CleanupWarning?
    }

    /// 主操作已完成，副本或记录清理尚未完成；调用方须按部分成功呈现。
    struct CleanupWarning: Sendable {
        let cleanup: ContainerCleanupRecord
        let details: String
        var needsRecordUpdateOnly = false

        var message: String {
            if needsRecordUpdateOnly {
                return String(format: "数据操作和副本清理已完成，但清理记录尚未更新。请稍后重试。%@".localized, details)
            }
            switch cleanup.kind {
            case .migrationBackup:
                return String(
                    format: "挂载迁移已完成，但本地安全备份仍保留在「%@」。可稍后重试清理；当前挂载数据不受影响。%@".localized,
                    cleanup.localPath, details
                )
            case .restoredVolume:
                return String(
                    format: "数据已还原到「%@」，但外置卷「%@」（%@）的清理尚未完成。该卷不会再自动挂载，请稍后重试清理。%@".localized,
                    cleanup.localPath, cleanup.mountRecord.volumeName, cleanup.mountRecord.volumeUUID, details
                )
            }
        }
    }

    /// 卷现在挂在哪 —— 决定挂载前要不要先把它从别处卸下来。
    enum KnownMountPoint: Equatable {
        /// 还没查过，需要一次 `diskutil info`（开机时这条要一秒上下）。
        case unknown
        /// 查过，卷没挂在任何地方。
        case unmounted
        /// 卷挂在别的位置（多半是系统自动挂到了 `/Volumes`）。
        case mounted(at: URL)
    }

    struct RemountOutcome: Sendable {
        enum State: Equatable, Sendable {
            case alreadyMounted
            case mounted
            case unavailable
            case failed(String)
        }

        let record: ContainerMountRecord
        let state: State
    }

    static let volumeMarkerFileName = ".appports-mount-metadata.plist"
    /// 系统自动挂载外置卷的位置：`/Volumes/<卷名>`。挂载前先看一眼这里能省掉一次 diskutil 查询。
    static let autoMountRoot = "/Volumes"
    /// 卷根的防索引标记：系统会把挂到容器路径上的卷当成普通外置卷索引，
    /// 两个微信卷实测留下过合计约 110 MB 的 `.Spotlight-V100`。空文件放在卷根，
    /// mds 就会跳过整个卷；标记写在卷上，跟着卷走，不需要任何系统设置。
    static let neverIndexFileName = ".metadata_never_index"
    private static let managedIdentifier = "com.shimoko.AppPorts"
    private static let lockedMountPointMode: mode_t = 0o000
    private static let openMountPointMode: mode_t = 0o700
    /// 挂载动作的尝试轮数：命令报告成功但挂载点没出现时（被系统自动挂载抢先）重来。
    static let maximumMountAttempts = 3
    /// 两次挂载尝试之间的间隔，给自动挂载留出落地时间。
    private static let mountRetrySettleNanoseconds: UInt64 = 500_000_000
    /// 卷根目录上由系统创建、不属于应用数据的条目，还原时不带回本地。
    private static let volumeSystemArtifacts: Set<String> = [
        volumeMarkerFileName, neverIndexFileName, ".fseventsd", ".Spotlight-V100", ".Trashes", ".TemporaryItems",
        ".DocumentRevisions-V100", ".PKInstallSandboxManager", ".PKInstallSandboxManager-SystemSoftware"
    ]

    /// 复制这么多数据需要预留的可用空间：数据本身加 5% 余量，至少多留 256 MB 给文件系统元数据。
    static func requiredFreeBytes(forDataBytes bytes: Int64) -> Int64 {
        bytes + max(bytes / 20, 256 * 1024 * 1024)
    }

    private struct VolumeMarker: Codable {
        let schemaVersion: Int
        let managedBy: String
        let mountPointPath: String
        let volumeUUID: String
        let dataDirType: String
        let appName: String
        let createdAt: Date
    }

    private let fileManager = FileManager.default
    private let disk: DiskUtility
    private let store: ContainerMountStore
    private let isMountPoint: @Sendable (URL) -> Bool
    private let mountedVolumePath: @Sendable (URL) -> String?
    private let mountedVolumeUUID: @Sendable (URL) -> String?
    /// 读卷根迁移标记里的 Volume UUID。挂载前用它确认 `/Volumes/<卷名>` 上挂的就是我们要的卷，
    /// 测试注入假实现，避免真去读磁盘。
    private let volumeUUIDMarker: @Sendable (URL) -> String?
    /// 记录增删后同步登录代理的安装状态；测试注入空实现，避免动真实 LaunchAgents。
    private let synchronizeAgent: @Sendable (ContainerMountStore) -> Void
    /// 路径所在卷的可用空间；返回 nil 表示查不到，此时不拦截。测试注入固定值。
    private let availableCapacity: @Sendable (URL) -> Int64?
    /// 挂载点的挂载标志，用来发现早期版本挂上、仍会显示在 Finder 里的卷。测试注入固定值。
    private let mountFlags: @Sendable (URL) -> UInt32?
    private let stagingMountRootURL: URL
    private let removeMigrationBackup: @Sendable (URL) throws -> Void

    init(
        disk: DiskUtility = DiskUtility(),
        store: ContainerMountStore = .shared,
        stagingMountRootURL: URL? = nil,
        isMountPoint: @escaping @Sendable (URL) -> Bool = { DiskUtility.isMountPoint($0) },
        mountedVolumePath: @escaping @Sendable (URL) -> String? = { DiskUtility.mountedVolumePath(containing: $0) },
        mountedVolumeUUID: @escaping @Sendable (URL) -> String? = { DiskUtility.mountedVolumeUUID(at: $0) },
        volumeUUIDMarker: @escaping @Sendable (URL) -> String? = { ContainerVolumeMigrator.readVolumeMarkerUUID(at: $0) },
        synchronizeAgent: @escaping @Sendable (ContainerMountStore) -> Void = { ContainerMountAgentInstaller.installIfNeeded(store: $0) },
        availableCapacity: @escaping @Sendable (URL) -> Int64? = { DiskUtility.availableCapacity(at: $0) },
        mountFlags: @escaping @Sendable (URL) -> UInt32? = { DiskUtility.mountFlags(at: $0) },
        removeMigrationBackup: @escaping @Sendable (URL) throws -> Void = { try FileCopier.removeCopy(at: $0) }
    ) {
        self.disk = disk
        self.store = store
        self.isMountPoint = isMountPoint
        self.mountedVolumePath = mountedVolumePath
        self.mountedVolumeUUID = mountedVolumeUUID
        self.volumeUUIDMarker = volumeUUIDMarker
        self.synchronizeAgent = synchronizeAgent
        self.availableCapacity = availableCapacity
        self.mountFlags = mountFlags
        self.removeMigrationBackup = removeMigrationBackup
        self.stagingMountRootURL = stagingMountRootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AppPorts/mounts")
    }

    // MARK: - 迁移

    /// 把容器内目录迁移到外置盘上的新 APFS 卷，并挂载回原路径。
    ///
    /// - Parameters:
    ///   - item: 要迁移的容器内目录（必须是真实目录，不能是符号链接或挂载点）
    ///   - externalRootURL: 用户选择的外部存储根目录，用来定位外置盘的 APFS 容器
    ///   - appName: 关联应用显示名
    ///   - bundleIdentifier: 关联应用 Bundle ID
    ///   - progressHandler: 复制进度回调
    /// - Returns: 已保存的挂载记录，以及需要向用户显示的清理提示。
    @discardableResult
    func migrate(
        item: DataDirItem,
        externalRootURL: URL,
        appName: String,
        bundleIdentifier: String?,
        progressHandler: FileCopier.ProgressHandler?
    ) async throws -> MigrationResult {
        let source = item.path.standardizedFileURL
        let operationID = AppLogger.shared.makeOperationID(prefix: "container-mount-migrate")
        let startedAt = Date()
        var operationResult = "failed"
        var operationErrorCode: String?
        var createdVolume = ""

        defer {
            AppLogger.shared.logOperationSummary(
                category: "container_mount_migrate",
                operationID: operationID,
                result: operationResult,
                startedAt: startedAt,
                errorCode: operationErrorCode,
                details: [
                    ("item_name", item.name),
                    ("type", item.type.rawValue),
                    ("source_path", source.path),
                    ("external_root", externalRootURL.path),
                    ("volume", createdVolume)
                ]
            )
        }

        AppLogger.shared.log("===== 开始挂载迁移容器数据目录 =====")
        AppLogger.shared.logContext(
            "挂载迁移上下文",
            details: [
                ("operation_id", operationID),
                ("item_name", item.name),
                ("type", item.type.rawValue),
                ("status", item.status),
                ("source_path", source.path),
                ("external_root", externalRootURL.path),
                ("app_name", appName),
                ("bundle_id", bundleIdentifier)
            ]
        )
        AppLogger.shared.logPathState("挂载迁移前-本地源[\(operationID)]", url: source)

        // 1. 预检：真实目录、未被管理、外置盘是 APFS
        guard existingRealDirectory(at: source) else {
            operationErrorCode = "CONTAINER-MOUNT-SOURCE-INVALID"
            throw MigrationError.sourceNotDirectory(source)
        }
        guard store.record(forMountPoint: source) == nil, !isMountPoint(source) else {
            operationErrorCode = "CONTAINER-MOUNT-ALREADY-MANAGED"
            throw MigrationError.alreadyManaged(source)
        }

        // diskutil 只认卷的挂载点或设备，不认卷内子目录。
        let externalVolumePath = mountedVolumePath(externalRootURL) ?? externalRootURL.standardizedFileURL.path
        let externalInfo: DiskUtility.VolumeInfo
        do {
            externalInfo = try await disk.volumeInfo(for: externalVolumePath)
        } catch {
            operationErrorCode = "CONTAINER-MOUNT-EXTERNAL-INFO-FAILED"
            throw MigrationError.volumeCreationFailed(error.localizedDescription)
        }
        guard externalInfo.isAPFS, let container = externalInfo.apfsContainerReference else {
            AppLogger.shared.logError(
                "外部存储不是 APFS，无法挂载迁移",
                errorCode: "CONTAINER-MOUNT-EXTERNAL-NOT-APFS",
                context: [
                    ("operation_id", operationID),
                    ("filesystem", externalInfo.filesystemType ?? "unknown"),
                    ("device", externalInfo.deviceIdentifier)
                ],
                relatedURLs: [("external_root", externalRootURL)]
            )
            operationErrorCode = "CONTAINER-MOUNT-EXTERNAL-NOT-APFS"
            throw MigrationError.externalNotAPFS(externalRootURL)
        }
        guard !externalInfo.isEncrypted else {
            operationErrorCode = "CONTAINER-MOUNT-ENCRYPTED-DESTINATION"
            throw MigrationError.encryptedDestination
        }
        // 同一 APFS 容器里的卷共享剩余空间；空间不够时在建卷前就停下，不留半截的卷。
        if item.sizeBytes > 0, let available = availableCapacity(externalRootURL) {
            let required = Self.requiredFreeBytes(forDataBytes: item.sizeBytes)
            guard available >= required else {
                operationErrorCode = "CONTAINER-MOUNT-INSUFFICIENT-SPACE"
                throw MigrationError.insufficientSpace(required: required, available: available)
            }
        }

        // 2. 在外置盘的 APFS 容器中新建卷（与其它卷共享空间）
        let volumeName = DiskUtility.makeVolumeName(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            directoryName: source.lastPathComponent
        )
        AppLogger.shared.log("步骤1: 创建外置卷 \(volumeName) @ \(container)")
        await progressHandler?(FileCopier.Progress(copiedBytes: 0, totalBytes: item.sizeBytes, currentFile: "正在创建外置卷...".localized))
        let device: String
        do {
            device = try await disk.createAPFSVolume(inContainer: container, name: volumeName)
        } catch {
            operationErrorCode = "CONTAINER-MOUNT-VOLUME-CREATE-FAILED"
            throw MigrationError.volumeCreationFailed(error.localizedDescription)
        }
        createdVolume = device

        let volumeUUID: String
        do {
            let info = try await disk.volumeInfo(for: device)
            guard let uuid = info.volumeUUID else {
                throw DiskUtility.Failure.unexpectedOutput(command: "diskutil info", output: device)
            }
            // 新卷通常被自动挂到 /Volumes 下；先卸载，稍后挂到暂存目录复制。
            if let autoMountPoint = info.mountPoint, !autoMountPoint.isEmpty {
                let mountPoint = URL(fileURLWithPath: autoMountPoint)
                try await requireExpectedVolume(uuid, at: mountPoint)
                try await disk.unmount(mountPoint: mountPoint)
            }
            volumeUUID = uuid
        } catch {
            await deleteVolumeQuietly(device, operationID: operationID)
            operationErrorCode = "CONTAINER-MOUNT-VOLUME-INFO-FAILED"
            throw MigrationError.volumeCreationFailed(error.localizedDescription)
        }
        createdVolume = "\(device) (\(volumeUUID))"

        // 3. 临时挂载到暂存目录并复制数据
        let staging = stagingMountRootURL.appendingPathComponent(volumeUUID)
        AppLogger.shared.log("步骤2: 临时挂载到 \(staging.path) 并复制数据...")
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try await disk.mount(volume: volumeUUID, at: staging)
            guard isMountPoint(staging) else { throw MigrationError.mountVerificationFailed(staging) }
            try await requireExpectedVolume(volumeUUID, at: staging)
        } catch {
            await cleanupStaging(staging, expectedVolumeUUID: volumeUUID, operationID: operationID)
            await deleteVolumeQuietly(volumeUUID, operationID: operationID)
            operationErrorCode = "CONTAINER-MOUNT-STAGING-MOUNT-FAILED"
            throw MigrationError.mountFailed(staging, error.localizedDescription)
        }

        let totalBytes: Int64
        do {
            let copier = FileCopier()
            totalBytes = try await copier.copyDirectory(
                from: source,
                to: staging,
                estimatedTotalBytes: item.sizeBytes,
                progressHandler: progressHandler
            )
            try writeVolumeMarker(
                at: staging,
                mountPointPath: source.path,
                volumeUUID: volumeUUID,
                dataDirType: item.type.rawValue,
                appName: appName
            )
            writeNeverIndexMarkerIfNeeded(at: staging, operationID: operationID)
            AppLogger.shared.log("步骤2: 复制完成")
        } catch {
            AppLogger.shared.logError(
                "步骤2: 复制到外置卷失败，删除新卷",
                error: error,
                errorCode: "CONTAINER-MOUNT-COPY-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("source", source), ("staging", staging)]
            )
            await cleanupStaging(staging, expectedVolumeUUID: volumeUUID, operationID: operationID)
            await deleteVolumeQuietly(volumeUUID, operationID: operationID)
            operationErrorCode = "CONTAINER-MOUNT-COPY-FAILED"
            throw MigrationError.copyFailed(error)
        }

        await progressHandler?(FileCopier.Progress(copiedBytes: totalBytes, totalBytes: totalBytes, currentFile: "正在切换本地入口...".localized))
        do {
            try await requireExpectedVolume(volumeUUID, at: staging)
            try await disk.unmount(mountPoint: staging)
            removeEmptyDirectoryQuietly(at: staging)
        } catch {
            await cleanupStaging(staging, expectedVolumeUUID: volumeUUID, operationID: operationID)
            await deleteVolumeQuietly(volumeUUID, operationID: operationID)
            operationErrorCode = "CONTAINER-MOUNT-STAGING-UNMOUNT-FAILED"
            throw MigrationError.unmountFailed(staging, error.localizedDescription)
        }

        // 4. 原目录改名为同卷安全备份，在原路径挂载新卷
        AppLogger.shared.log("步骤3: 将原目录移动到本地安全备份并挂载新卷...")
        let backupURL = makeMigrationBackupURL(for: source)
        do {
            try fileManager.moveItem(at: source, to: backupURL)
        } catch {
            AppLogger.shared.logError(
                "步骤3: 移动原目录到本地安全备份失败，删除新卷",
                error: error,
                errorCode: "CONTAINER-MOUNT-SOURCE-BACKUP-MOVE-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("source", source), ("backup", backupURL)]
            )
            await deleteVolumeQuietly(volumeUUID, operationID: operationID)
            operationErrorCode = "CONTAINER-MOUNT-SOURCE-BACKUP-MOVE-FAILED"
            throw MigrationError.switchFailed(error)
        }

        let record = ContainerMountRecord(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            dataDirType: item.type.rawValue,
            mountPointPath: source.path,
            volumeUUID: volumeUUID,
            volumeName: volumeName,
            externalRootPath: externalRootURL.standardizedFileURL.path
        )
        let cleanup = ContainerCleanupRecord(kind: .migrationBackup, mountRecord: record, localPath: backupURL.path)
        do {
            try await mountVolume(volumeUUID, at: source, operationID: operationID)
            try store.recordMigration(record, cleanup: cleanup)
            synchronizeAgent(store)
        } catch {
            AppLogger.shared.logError(
                "步骤3: 在原路径挂载或写入记录失败，尝试恢复本地安全备份",
                error: error,
                errorCode: "CONTAINER-MOUNT-SWITCH-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("source", source), ("backup", backupURL)]
            )
            await unmountQuietly(source, expectedVolumeUUID: volumeUUID, operationID: operationID)
            removeEmptyDirectoryQuietly(at: source)
            operationErrorCode = "CONTAINER-MOUNT-SWITCH-FAILED"
            guard restoreMigrationBackup(backupURL, to: source, operationID: operationID) else {
                // 路径被其它卷或新数据占用时，两份副本都保留，不能声称已经还原。
                throw MigrationError.rollbackIncomplete(backup: backupURL, volumeName: volumeName, volumeUUID: volumeUUID, underlying: error)
            }
            await deleteVolumeQuietly(volumeUUID, operationID: operationID)
            throw MigrationError.switchFailed(error)
        }
        AppLogger.shared.logPathState("挂载迁移步骤3后-挂载点[\(operationID)]", url: source)

        // 5. 清理本地安全备份
        let cleanupWarning = await performCleanup(cleanup)
        if let cleanupWarning {
            AppLogger.shared.logError(
                "挂载迁移已完成，但本地安全备份清理失败",
                errorCode: "CONTAINER-MOUNT-BACKUP-CLEANUP-FAILED",
                context: [("operation_id", operationID), ("error", cleanupWarning.details)],
                relatedURLs: [("backup", backupURL)]
            )
            operationResult = "success_with_warning"
            operationErrorCode = "CONTAINER-MOUNT-BACKUP-CLEANUP-FAILED"
        }

        AppLogger.shared.log("===== 挂载迁移完成 =====")
        invalidateSizeCache(for: source)
        if operationResult != "success_with_warning" {
            operationResult = "success"
        }
        return MigrationResult(record: record, cleanupWarning: cleanupWarning)
    }

    // MARK: - 挂载 / 卸载

    /// 把记录对应的卷重新挂到容器内挂载点上；已挂载则直接返回。
    func mount(record: ContainerMountRecord) async throws {
        let mountPoint = record.mountPointURL
        if isMountPoint(mountPoint) {
            try await requireExpectedVolume(record.volumeUUID, at: mountPoint)
            await hideFromFinderIfNeeded(mountPoint)
            return
        }
        let operationID = AppLogger.shared.makeOperationID(prefix: "container-mount")
        let hint = try await knownMountPoint(for: record, operationID: operationID)
        try await mountVolume(record.volumeUUID, at: mountPoint, operationID: operationID, knownMountPoint: hint)
        invalidateSizeCache(for: mountPoint)
        AppLogger.shared.logContext(
            "容器卷已挂载",
            details: [("operation_id", operationID), ("volume", record.volumeName), ("mount_point", mountPoint.path)]
        )
    }

    /// 卷现在挂在哪。
    ///
    /// 先试**零成本**的快路径：开机和插盘时系统几乎总是先把卷挂到 `/Volumes/<卷名>`，
    /// 用 `statfs` 看一眼这个路径、再读一次卷根标记就能确认是不是我们要的卷
    /// —— 2026-09-23 开机实测那次 `diskutil info` 花了 **9 秒**（登录后系统正忙），
    /// 是整条挂载链路上最贵的一步，能省就省。
    /// 认不出来（卷名被系统改名、标记缺失、卷根本没挂上）才退回一次 `diskutil` 查询，
    /// 那一次同时回答「卷在不在线」和「现在挂在哪」。
    private func knownMountPoint(for record: ContainerMountRecord, operationID: String) async throws -> KnownMountPoint {
        if let autoMounted = autoMountedPath(for: record) {
            AppLogger.shared.logContext(
                "卷已由系统挂在自动挂载点，直接切换",
                details: [
                    ("operation_id", operationID),
                    ("volume", record.volumeName),
                    ("current_mount_point", autoMounted.path),
                    ("mount_point", record.mountPointPath)
                ],
                level: "TRACE"
            )
            return .mounted(at: autoMounted)
        }
        guard let info = try? await disk.volumeInfo(for: record.volumeUUID) else {
            AppLogger.shared.logContext(
                "挂载失败：外置卷不在线",
                details: [("operation_id", operationID), ("volume", record.volumeName), ("uuid", record.volumeUUID), ("mount_point", record.mountPointPath)],
                level: "WARN"
            )
            throw MigrationError.volumeUnavailable(record.volumeName)
        }
        guard let current = info.mountPoint, !current.isEmpty else { return .unmounted }
        return .mounted(at: URL(fileURLWithPath: current))
    }

    /// `/Volumes/<卷名>` 上挂的是不是这个记录的卷。是就返回那个路径，否则 nil。
    private func autoMountedPath(for record: ContainerMountRecord) -> URL? {
        let candidate = URL(fileURLWithPath: Self.autoMountRoot).appendingPathComponent(record.volumeName)
        guard isMountPoint(candidate) else { return nil }
        // 只看"挂上了"还不够：得确认挂的就是我们的卷（卷名可能被系统改名，也可能撞上别的盘）。
        guard volumeUUIDMarker(candidate) == record.volumeUUID else { return nil }
        guard mountedVolumeUUID(candidate)?.caseInsensitiveCompare(record.volumeUUID) == .orderedSame else { return nil }
        return candidate
    }

    /// 卸载记录对应的卷，并把空挂载点重新锁住。
    func unmount(record: ContainerMountRecord, force: Bool = false) async throws {
        let mountPoint = record.mountPointURL
        guard isMountPoint(mountPoint) else {
            setMode(Self.lockedMountPointMode, at: mountPoint)
            return
        }
        let operationID = AppLogger.shared.makeOperationID(prefix: "container-unmount")
        try await requireExpectedVolume(record.volumeUUID, at: mountPoint)
        do {
            try await disk.unmount(mountPoint: mountPoint, force: force)
        } catch {
            AppLogger.shared.logError(
                "卸载容器卷失败",
                error: error,
                errorCode: "CONTAINER-UNMOUNT-FAILED",
                context: [("operation_id", operationID), ("volume", record.volumeName)],
                relatedURLs: [("mount_point", mountPoint)]
            )
            throw MigrationError.unmountFailed(mountPoint, error.localizedDescription)
        }
        setMode(Self.lockedMountPointMode, at: mountPoint)
        invalidateSizeCache(for: mountPoint)
        AppLogger.shared.logContext(
            "容器卷已卸载",
            details: [("operation_id", operationID), ("volume", record.volumeName), ("mount_point", mountPoint.path)]
        )
    }

    /// 重挂载所有在线但尚未挂载的记录。启动、插盘和后台代理都走这里。
    func remountAvailableRecords() async -> [RemountOutcome] {
        var outcomes: [RemountOutcome] = []
        for record in store.records() {
            do {
                let alreadyMounted = isMountPoint(record.mountPointURL)
                // 在线检查放在 mount(record:) 里，和「当前挂载点」共用同一次 diskutil 查询。
                try await mount(record: record)
                outcomes.append(RemountOutcome(record: record, state: alreadyMounted ? .alreadyMounted : .mounted))
            } catch let error as MigrationError {
                if case .volumeUnavailable = error {
                    outcomes.append(RemountOutcome(record: record, state: .unavailable))
                } else {
                    outcomes.append(RemountOutcome(record: record, state: .failed(error.localizedDescription)))
                }
            } catch {
                outcomes.append(RemountOutcome(record: record, state: .failed(error.localizedDescription)))
            }
        }
        return outcomes
    }

    // MARK: - 还原

    /// 把卷上的数据复制回本地，删除卷和记录。
    @discardableResult
    func restore(
        record: ContainerMountRecord,
        estimatedTotalBytes: Int64,
        progressHandler: FileCopier.ProgressHandler?
    ) async throws -> CleanupWarning? {
        let mountPoint = record.mountPointURL
        let operationID = AppLogger.shared.makeOperationID(prefix: "container-mount-restore")
        let startedAt = Date()
        var operationResult = "failed"
        var operationErrorCode: String?

        defer {
            AppLogger.shared.logOperationSummary(
                category: "container_mount_restore",
                operationID: operationID,
                result: operationResult,
                startedAt: startedAt,
                errorCode: operationErrorCode,
                details: [
                    ("mount_point", mountPoint.path),
                    ("volume", record.volumeName),
                    ("uuid", record.volumeUUID)
                ]
            )
        }

        AppLogger.shared.log("===== 开始还原挂载迁移目录 =====")
        AppLogger.shared.logContext(
            "挂载还原上下文",
            details: [
                ("operation_id", operationID),
                ("mount_point", mountPoint.path),
                ("volume", record.volumeName),
                ("uuid", record.volumeUUID)
            ]
        )

        // 1. 确保卷已挂载
        do {
            try await mount(record: record)
        } catch {
            operationErrorCode = "CONTAINER-RESTORE-VOLUME-UNAVAILABLE"
            throw error
        }

        // 数据要整份复制回本机；本机空间不够时现在就停下，外置卷原样保留。
        if estimatedTotalBytes > 0, let available = availableCapacity(mountPoint.deletingLastPathComponent()) {
            let required = Self.requiredFreeBytes(forDataBytes: estimatedTotalBytes)
            guard available >= required else {
                operationErrorCode = "CONTAINER-RESTORE-INSUFFICIENT-SPACE"
                throw MigrationError.insufficientSpace(required: required, available: available)
            }
        }

        // 2. 复制到同目录的隐藏暂存路径（逐项复制，跳过卷根上的系统条目）
        let stagingName = ".appports-restore-staging-\(UUID().uuidString)"
        let staging = mountPoint.deletingLastPathComponent().appendingPathComponent(stagingName)
        AppLogger.shared.log("步骤1: 复制数据到暂存目录 \(stagingName)...")
        do {
            try await copyVolumeContents(from: mountPoint, to: staging, estimatedTotalBytes: estimatedTotalBytes, progressHandler: progressHandler)
            AppLogger.shared.log("步骤1: 复制完成")
        } catch {
            AppLogger.shared.logError(
                "步骤1: 复制到暂存目录失败",
                error: error,
                errorCode: "CONTAINER-RESTORE-COPY-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("mount_point", mountPoint), ("staging", staging)]
            )
            try? FileCopier.removeCopy(at: staging)
            operationErrorCode = "CONTAINER-RESTORE-COPY-FAILED"
            throw MigrationError.copyFailed(error)
        }

        // 3. 卸载卷，把暂存目录改回原路径
        AppLogger.shared.log("步骤2: 卸载卷并切换回本地目录...")
        await progressHandler?(FileCopier.Progress(copiedBytes: estimatedTotalBytes, totalBytes: estimatedTotalBytes, currentFile: "正在切换本地入口...".localized))
        do {
            try await requireExpectedVolume(record.volumeUUID, at: mountPoint)
        } catch {
            try? FileCopier.removeCopy(at: staging)
            operationErrorCode = "CONTAINER-RESTORE-VOLUME-MISMATCH"
            throw error
        }
        // 卷根的权限就是迁移前原目录的权限，换回本地目录后沿用。
        let originalPermissions = (try? fileManager.attributesOfItem(atPath: mountPoint.path))?[.posixPermissions]
        let cleanup = ContainerCleanupRecord(
            kind: .restoredVolume, mountRecord: record,
            localPath: mountPoint.path, restoreStagingPath: staging.path
        )
        // 必须先持久化取消自动挂载；写入失败时不切换本地目录、不删除外置卷。
        do {
            try store.beginRestore(cleanup)
        } catch {
            operationErrorCode = "CONTAINER-RESTORE-RECORD-UPDATE-FAILED"
            throw MigrationError.restoreRecordRecovery(staging: staging, underlying: error)
        }
        do {
            try await requireExpectedVolume(record.volumeUUID, at: mountPoint)
            try await disk.unmount(mountPoint: mountPoint)
        } catch {
            do { try store.cancelRestore(cleanup) }
            catch {
                operationErrorCode = "CONTAINER-RESTORE-RECORD-RECOVERY-FAILED"
                throw MigrationError.restoreRecordRecovery(staging: staging, underlying: error)
            }
            try? FileCopier.removeCopy(at: staging)
            operationErrorCode = "CONTAINER-RESTORE-UNMOUNT-FAILED"
            throw MigrationError.unmountFailed(mountPoint, error.localizedDescription)
        }
        do {
            try removeEmptyMountPoint(at: mountPoint)
            try fileManager.moveItem(at: staging, to: mountPoint)
            if let originalPermissions {
                try? fileManager.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: mountPoint.path)
            }
        } catch {
            AppLogger.shared.logError(
                "步骤2: 切换本地目录失败，尝试重新挂载卷；暂存目录保留供手动恢复",
                error: error,
                errorCode: "CONTAINER-RESTORE-SWITCH-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("mount_point", mountPoint), ("staging", staging)]
            )
            do { try store.cancelRestore(cleanup) }
            catch {
                operationErrorCode = "CONTAINER-RESTORE-RECORD-RECOVERY-FAILED"
                throw MigrationError.restoreRecordRecovery(staging: staging, underlying: error)
            }
            try? await mountVolume(record.volumeUUID, at: mountPoint, operationID: operationID)
            operationErrorCode = "CONTAINER-RESTORE-SWITCH-FAILED"
            throw MigrationError.restoreIncomplete(staging: staging, underlying: error)
        }
        AppLogger.shared.logPathState("挂载还原步骤2后-本地路径[\(operationID)]", url: mountPoint)

        // 4. 活动记录已移除；清理失败时仍保留专用记录，但不会再自动挂载。
        synchronizeAgent(store)
        AppLogger.shared.log("步骤3: 删除外置卷...")
        await progressHandler?(FileCopier.Progress(copiedBytes: estimatedTotalBytes, totalBytes: estimatedTotalBytes, currentFile: "正在清理外部存储...".localized))
        let cleanupWarning = await performCleanup(cleanup)
        if let cleanupWarning {
            AppLogger.shared.logError(
                "删除外置卷失败（本地还原已完成，可在磁盘工具中手动删除）",
                errorCode: "CONTAINER-RESTORE-VOLUME-DELETE-FAILED",
                context: [("operation_id", operationID), ("volume", record.volumeName), ("uuid", record.volumeUUID), ("error", cleanupWarning.details)]
            )
            operationResult = "success_with_warning"
            operationErrorCode = "CONTAINER-RESTORE-VOLUME-DELETE-FAILED"
        }

        AppLogger.shared.log("===== 挂载迁移目录还原完成 =====")
        invalidateSizeCache(for: mountPoint)
        if operationResult != "success_with_warning" {
            operationResult = "success"
        }
        return cleanupWarning
    }

    /// 用户明确重试时才清理；不经过自动挂载入口，也不重复复制已经还原的数据。
    func retryCleanup(_ warning: CleanupWarning) async -> CleanupWarning? {
        await performCleanup(warning.cleanup, recordUpdateOnly: warning.needsRecordUpdateOnly)
    }

    /// 用户明确确认后仅移除清理记录，保留所有副本；用于无法分辨卷已删除还是已断开的情况。
    /// 未完成的本地切换仍需保留恢复信息，不能通过此入口遗忘。
    func discardCleanupRecord(_ cleanup: ContainerCleanupRecord) throws {
        guard try store.pendingCleanups().contains(where: { $0.id == cleanup.id }) else { return }
        if cleanup.kind == .restoredVolume {
            let localURL = URL(fileURLWithPath: cleanup.localPath)
            guard existingRealDirectory(at: localURL), !isMountPoint(localURL),
                  cleanup.restoreStagingPath.map({ !fileManager.fileExists(atPath: $0) }) ?? true else {
                throw MigrationError.sourceNotDirectory(localURL)
            }
        }
        try store.finishCleanup(cleanup.id)
        AppLogger.shared.logContext(
            "用户仅移除清理记录，保留副本",
            details: [("cleanup_id", cleanup.id.uuidString), ("local_path", cleanup.localPath),
                      ("volume_uuid", cleanup.mountRecord.volumeUUID)],
            level: "WARN"
        )
    }

    private func performCleanup(_ cleanup: ContainerCleanupRecord, recordUpdateOnly: Bool = false) async -> CleanupWarning? {
        var copyRemoved = recordUpdateOnly
        do {
            // 必须仍有持久化的清理记录；损坏或失踪时不凭旧 UI 状态删除副本。
            guard try store.pendingCleanups().contains(where: { $0.id == cleanup.id }) else { return nil }
            let localURL = URL(fileURLWithPath: cleanup.localPath)
            if !recordUpdateOnly {
                switch cleanup.kind {
                case .migrationBackup:
                    guard !isMountPoint(localURL), !isSymbolicLink(at: localURL),
                          localURL.lastPathComponent.hasPrefix(".appports-migration-backup-"),
                          localURL.deletingLastPathComponent() == cleanup.mountRecord.mountPointURL.deletingLastPathComponent() else {
                        throw MigrationError.unexpectedMountedVolume(localURL)
                    }
                    let source = cleanup.mountRecord.mountPointURL
                    if let active = store.record(forMountPoint: source) {
                        guard active.volumeUUID == cleanup.mountRecord.volumeUUID else {
                            throw MigrationError.unexpectedMountedVolume(source)
                        }
                        // 外置副本不在线时保留安全备份，不能删掉用户仅有的可用副本。
                        try await requireExpectedVolume(active.volumeUUID, at: source)
                    } else {
                        // 用户可能已完成还原，再来清理早先留下的本地安全备份。
                        guard existingRealDirectory(at: source), !isMountPoint(source) else {
                            throw MigrationError.sourceNotDirectory(source)
                        }
                    }
                    if fileManager.fileExists(atPath: localURL.path) {
                        try removeMigrationBackup(localURL)
                    }
                case .restoredVolume:
                    // 原路径必须已切换为本地目录，暂存副本不能仍在等待就位。
                    guard existingRealDirectory(at: localURL), !isMountPoint(localURL),
                          cleanup.restoreStagingPath.map({ !fileManager.fileExists(atPath: $0) }) ?? true else {
                        throw MigrationError.sourceNotDirectory(localURL)
                    }
                    guard !store.records().contains(where: { $0.volumeUUID == cleanup.mountRecord.volumeUUID }) else {
                        throw MigrationError.alreadyManaged(localURL)
                    }
                    let info = try await disk.volumeInfo(for: cleanup.mountRecord.volumeUUID)
                    guard info.volumeUUID?.caseInsensitiveCompare(cleanup.mountRecord.volumeUUID) == .orderedSame else {
                        throw MigrationError.unexpectedMountedVolume(localURL)
                    }
                    // 不替用户卸载已经重新被使用的卷。保留副本，等待用户检查后再试。
                    if let mountedPath = info.mountPoint, !mountedPath.isEmpty {
                        throw MigrationError.unexpectedMountedVolume(URL(fileURLWithPath: mountedPath))
                    }
                    try await disk.deleteAPFSVolume(cleanup.mountRecord.volumeUUID)
                }
                copyRemoved = true
            }
            try store.finishCleanup(cleanup.id)
            return nil
        } catch {
            return CleanupWarning(cleanup: cleanup, details: error.localizedDescription, needsRecordUpdateOnly: copyRemoved)
        }
    }

    // MARK: - 私有辅助：挂载点

    /// 把卷挂到容器内的挂载点，并确认它**真的**挂在这个路径上。
    ///
    /// 挂完必须校验：`diskutil mount -mountPoint` 在卷已经挂载时会忽略挂载点参数、
    /// 照样打印 "mounted" 并返回 0 —— 开机/插盘时 macOS 的自动挂载常常抢在前面，
    /// 于是命令成功、挂载点却是空的（2026-09-21 与 09-23 各一次，微信随后读到空目录）。
    /// 实测：先把卷挂到 `/Volumes` 再对它执行 `mount -mountPoint <别处>`，退出码 0 而卷仍在 `/Volumes`。
    ///
    /// 校验不过就重新查一次卷挂在哪、把它从别的挂载点卸下来再挂一遍，最多 `maximumMountAttempts` 轮。
    private func mountVolume(
        _ volumeUUID: String,
        at mountPoint: URL,
        operationID: String,
        knownMountPoint: KnownMountPoint = .unknown
    ) async throws {
        var hint = knownMountPoint
        for attempt in 1...Self.maximumMountAttempts {
            try await detachForeignMountPoint(
                volumeUUID: volumeUUID,
                target: mountPoint,
                operationID: operationID,
                knownMountPoint: hint
            )
            try prepareMountPoint(at: mountPoint)
            try await performMount(volumeUUID, at: mountPoint, operationID: operationID)

            let landing = try await mountLanding(volumeUUID: volumeUUID, at: mountPoint)
            switch landing.landing {
            case .mountPointVisible:
                if attempt > 1 {
                    AppLogger.shared.logContext(
                        "重试后挂载点已就位",
                        details: [
                            ("operation_id", operationID),
                            ("attempt", "\(attempt)/\(Self.maximumMountAttempts)"),
                            ("mount_point", mountPoint.path)
                        ]
                    )
                }
                // 迁移前建的卷（或标记被删掉的卷）在这里补上防索引标记；失败只记日志，不影响挂载。
                writeNeverIndexMarkerIfNeeded(at: mountPoint, operationID: operationID)
                return
            case .reportedByDiskUtil:
                // statfs 还没看到挂载表更新，但磁盘仲裁已经确认卷在目标路径上了，按成功处理。
                // 这时不写防索引标记：标记是普通文件，写错地方会落在容器里的空目录上。
                AppLogger.shared.logContext(
                    "挂载校验以磁盘仲裁结果为准（statfs 尚未刷新）",
                    details: [("operation_id", operationID), ("mount_point", mountPoint.path)],
                    level: "WARN"
                )
                return
            case .notMounted:
                break
            }

            // 校验没过：`mountLanding` 顺手查到的"卷现在挂在哪"就是 diskarbitrationd 的权威答案，
            // 直接交给下一轮判断要不要先把卷从别处卸下来，不重复查。
            hint = Self.knownMountPoint(from: landing.info)
            AppLogger.shared.logContext(
                "挂载后校验失败，准备重试",
                details: [
                    ("operation_id", operationID),
                    ("attempt", "\(attempt)/\(Self.maximumMountAttempts)"),
                    ("mount_point", mountPoint.path),
                    ("current_mount_point", landing.info?.mountPoint ?? "")
                ],
                level: "WARN"
            )
            guard attempt < Self.maximumMountAttempts else {
                throw MigrationError.mountVerificationFailed(mountPoint)
            }
            try? await Task.sleep(nanoseconds: Self.mountRetrySettleNanoseconds)
        }
    }

    /// 执行挂载命令。部分系统版本会拒绝把卷挂到不可读目录上，这时放开权限再试一次。
    private func performMount(_ volumeUUID: String, at mountPoint: URL, operationID: String) async throws {
        do {
            try await disk.mount(volume: volumeUUID, at: mountPoint)
        } catch {
            AppLogger.shared.logContext(
                "挂载到锁定的挂载点失败，放开权限后重试",
                details: [("operation_id", operationID), ("mount_point", mountPoint.path), ("error", error.localizedDescription)],
                level: "WARN"
            )
            setMode(Self.openMountPointMode, at: mountPoint)
            // 保存未挂载目录的 fd，成功后也能锁住被卷遮住的原目录，避免拔盘后写入本地。
            let underlyingDirectory = open(mountPoint.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard underlyingDirectory >= 0 else {
                setMode(Self.lockedMountPointMode, at: mountPoint)
                throw MigrationError.mountFailed(mountPoint, error.localizedDescription)
            }
            defer {
                _ = fchmod(underlyingDirectory, Self.lockedMountPointMode)
                _ = close(underlyingDirectory)
            }
            do {
                try await disk.mount(volume: volumeUUID, at: mountPoint)
            } catch {
                setMode(Self.lockedMountPointMode, at: mountPoint)
                throw MigrationError.mountFailed(mountPoint, error.localizedDescription)
            }
        }
    }

    /// 这次挂载动作的真实落点。
    private enum MountLanding: Equatable {
        /// `statfs` 确认目标路径就是挂载点。
        case mountPointVisible
        /// `statfs` 还没刷新，但磁盘仲裁报告卷挂在目标路径上。
        case reportedByDiskUtil
        /// 卷不在目标路径上（多半是又被系统自动挂到了 `/Volumes`）。
        case notMounted
    }

    private func mountLanding(
        volumeUUID: String,
        at mountPoint: URL
    ) async throws -> (landing: MountLanding, info: DiskUtility.VolumeInfo?) {
        if isMountPoint(mountPoint) {
            try await requireExpectedVolume(volumeUUID, at: mountPoint)
            return (.mountPointVisible, nil)
        }
        let info = try? await disk.volumeInfo(for: volumeUUID)
        guard let current = info?.mountPoint, !current.isEmpty else {
            return (.notMounted, info)
        }
        return (DiskUtility.pathsMatch(current, mountPoint.path) ? .reportedByDiskUtil : .notMounted, info)
    }

    private func requireExpectedVolume(_ uuid: String, at mountPoint: URL) async throws {
        guard isMountPoint(mountPoint) else { throw MigrationError.mountVerificationFailed(mountPoint) }
        let actual: String?
        if let cached = mountedVolumeUUID(mountPoint) {
            actual = cached
        } else {
            actual = try await disk.volumeInfo(for: mountPoint.path).volumeUUID
        }
        guard actual?.caseInsensitiveCompare(uuid) == .orderedSame else {
            throw MigrationError.unexpectedMountedVolume(mountPoint)
        }
    }

    /// 卷已挂在别的位置时先卸载它。
    ///
    /// macOS 开机和插盘时会把 APFS 卷自动挂到 `/Volumes` 下；而 `diskutil mount -mountPoint`
    /// 对已挂载的卷会忽略挂载点参数并直接报告成功，此时容器路径依然是空目录。
    /// 所以挂载前必须先让卷回到"未挂载"状态，挂载动作才是幂等的。
    /// - Parameter knownMountPoint: 调用方**已经知道**的卷挂载位置（开机和插盘时来自 `/Volumes/<卷名>`
    ///   的 `statfs` + 卷根标记）。`.unknown` 表示不知道，这里自己查一次 diskutil
    ///   （开机时那次查询要一秒上下，能省就省）。
    private func detachForeignMountPoint(
        volumeUUID: String,
        target: URL,
        operationID: String,
        knownMountPoint: KnownMountPoint = .unknown
    ) async throws {
        let currentPath: String?
        switch knownMountPoint {
        case .mounted(let url): currentPath = url.path
        case .unmounted: currentPath = nil
        case .unknown: currentPath = (try? await disk.volumeInfo(for: volumeUUID))?.mountPoint
        }
        guard let currentPath, !currentPath.isEmpty else { return }
        let currentURL = URL(fileURLWithPath: currentPath)
        guard !DiskUtility.pathsMatch(currentURL.path, target.path) else { return }
        AppLogger.shared.logContext(
            "容器卷已挂在其它位置，先卸载再挂到容器路径",
            details: [
                ("operation_id", operationID),
                ("volume", volumeUUID),
                ("current_mount_point", currentPath),
                ("target_mount_point", target.path)
            ]
        )
        do {
            try await requireExpectedVolume(volumeUUID, at: currentURL)
            try await disk.unmount(mountPoint: currentURL)
        } catch {
            AppLogger.shared.logError(
                "卸载占用其它挂载点的容器卷失败，无法把它挂到容器路径",
                error: error,
                errorCode: "CONTAINER-MOUNT-DETACH-FAILED",
                context: [
                    ("operation_id", operationID),
                    ("volume", volumeUUID),
                    ("current_mount_point", currentPath)
                ],
                relatedURLs: [("target_mount_point", target)]
            )
            throw MigrationError.unmountFailed(currentURL, error.localizedDescription)
        }
    }

    /// 挂载点必须是空目录；未挂载期间保持 000 权限。
    /// 目录里有本地数据时不能锁住它：那是用户还能访问的真实数据，恢复原权限后报错。
    private func prepareMountPoint(at url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, !isSymbolicLink(at: url) else {
                throw MigrationError.sourceNotDirectory(url)
            }
            let originalMode = currentMode(at: url)
            setMode(Self.openMountPointMode, at: url)
            let contents = try fileManager.contentsOfDirectory(atPath: url.path).filter { $0 != ".DS_Store" }
            guard contents.isEmpty else {
                if let originalMode { setMode(originalMode, at: url) }
                throw MigrationError.mountPointNotEmpty(url)
            }
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        }
        setMode(Self.lockedMountPointMode, at: url)
    }

    private func currentMode(at url: URL) -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_mode & 0o7777
    }

    private func setMode(_ mode: mode_t, at url: URL) {
        if chmod(url.path, mode) != 0 {
            AppLogger.shared.logContext(
                "修改挂载点权限失败",
                details: [("path", url.path), ("mode", String(mode, radix: 8)), ("errno", String(errno))],
                level: "TRACE"
            )
        }
    }

    private func unmountQuietly(_ mountPoint: URL, expectedVolumeUUID: String, operationID: String) async {
        guard isMountPoint(mountPoint) else { return }
        do {
            try await requireExpectedVolume(expectedVolumeUUID, at: mountPoint)
            try await disk.unmount(mountPoint: mountPoint)
        } catch {
            AppLogger.shared.logError(
                "回滚：卸载失败",
                error: error,
                context: [("operation_id", operationID)],
                relatedURLs: [("mount_point", mountPoint)]
            )
        }
    }

    private func removeEmptyDirectoryQuietly(at url: URL) {
        guard !isMountPoint(url), !isSymbolicLink(at: url) else { return }
        setMode(Self.openMountPointMode, at: url)
        // 原子地只删空目录；其它卷重新挂上或本地新数据出现时，绝不递归删除。
        _ = rmdir(url.path)
    }

    /// 卸载后删除留下的空挂载点。
    ///
    /// 只用 `rmdir`：卷若又被挂了回来、或挂载点底下意外有文件，删除会失败而不是像
    /// `removeItem` 那样递归删掉外置卷或本地的数据。Finder 留下的 `.DS_Store` 可以清掉。
    private func removeEmptyMountPoint(at url: URL) throws {
        guard !isMountPoint(url) else { throw MigrationError.unexpectedMountedVolume(url) }
        setMode(Self.openMountPointMode, at: url)
        let finderMetadata = url.appendingPathComponent(".DS_Store")
        if fileManager.fileExists(atPath: finderMetadata.path) {
            try? fileManager.removeItem(at: finderMetadata)
        }
        guard rmdir(url.path) == 0 else {
            let code = errno
            if code == ENOTEMPTY || code == EEXIST { throw MigrationError.mountPointNotEmpty(url) }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private func cleanupStaging(_ staging: URL, expectedVolumeUUID: String, operationID: String) async {
        await unmountQuietly(staging, expectedVolumeUUID: expectedVolumeUUID, operationID: operationID)
        removeEmptyDirectoryQuietly(at: staging)
    }

    private func deleteVolumeQuietly(_ volume: String, operationID: String) async {
        do {
            try await disk.deleteAPFSVolume(volume)
            AppLogger.shared.logContext("回滚：已删除新建的外置卷", details: [("operation_id", operationID), ("volume", volume)])
        } catch {
            AppLogger.shared.logError(
                "回滚：删除新建的外置卷失败，请在磁盘工具中手动删除",
                error: error,
                errorCode: "CONTAINER-MOUNT-ROLLBACK-DELETE-VOLUME-FAILED",
                context: [("operation_id", operationID), ("volume", volume)]
            )
        }
    }

    // MARK: - 私有辅助：复制与标记

    /// 逐项复制卷根目录内容，跳过 `.fseventsd` 等系统条目；它们可能不可读，也不属于应用数据。
    private func copyVolumeContents(
        from mountPoint: URL,
        to staging: URL,
        estimatedTotalBytes: Int64,
        progressHandler: FileCopier.ProgressHandler?
    ) async throws {
        let entries = try fileManager.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { !Self.volumeSystemArtifacts.contains($0.lastPathComponent) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)

        let copier = FileCopier()
        var copiedBytes: Int64 = 0
        for entry in entries {
            let base = copiedBytes
            let entryBytes = try await copier.copyDirectory(
                from: entry,
                to: staging.appendingPathComponent(entry.lastPathComponent),
                estimatedTotalBytes: nil
            ) { progress in
                await progressHandler?(FileCopier.Progress(
                    copiedBytes: base + progress.copiedBytes,
                    totalBytes: estimatedTotalBytes,
                    currentFile: progress.currentFile
                ))
            }
            copiedBytes += entryBytes
        }
    }

    private func writeVolumeMarker(
        at volumeRoot: URL,
        mountPointPath: String,
        volumeUUID: String,
        dataDirType: String,
        appName: String
    ) throws {
        let marker = VolumeMarker(
            schemaVersion: ContainerMountRecord.currentSchemaVersion,
            managedBy: Self.managedIdentifier,
            mountPointPath: mountPointPath,
            volumeUUID: volumeUUID,
            dataDirType: dataDirType,
            appName: appName,
            createdAt: Date()
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(marker).write(to: volumeRoot.appendingPathComponent(Self.volumeMarkerFileName), options: .atomic)
    }

    /// `diskutil info` 的结果 → 卷挂在哪。
    static func knownMountPoint(from info: DiskUtility.VolumeInfo?) -> KnownMountPoint {
        guard let info else { return .unknown }
        guard let current = info.mountPoint, !current.isEmpty else { return .unmounted }
        return .mounted(at: URL(fileURLWithPath: current))
    }

    /// 读卷根迁移标记里的 Volume UUID；认不出来（文件不在、格式变了）返回 nil。
    static func readVolumeMarkerUUID(at volumeRoot: URL) -> String? {
        let url = volumeRoot.appendingPathComponent(volumeMarkerFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListDecoder().decode(VolumeMarker.self, from: data))?.volumeUUID
    }

    /// 在卷根放一个空的 `.metadata_never_index`，让 Spotlight 跳过整个卷。
    ///
    /// 幂等：标记已存在就原样返回，连索引目录也不动。真正写入时顺手清掉系统已经建好的
    /// 索引目录，那份索引会一直白占卷上几十到上百 MB。
    /// - Returns: 本次真的写了标记返回 `true`，标记早就存在返回 `false`。
    @discardableResult
    static func writeNeverIndexMarker(at volumeRoot: URL, fileManager: FileManager = .default) throws -> Bool {
        let markerURL = volumeRoot.appendingPathComponent(neverIndexFileName)
        guard !fileManager.fileExists(atPath: markerURL.path) else { return false }
        try Data().write(to: markerURL, options: .atomic)
        let indexDirectory = volumeRoot.appendingPathComponent(".Spotlight-V100")
        if fileManager.fileExists(atPath: indexDirectory.path) {
            try? fileManager.removeItem(at: indexDirectory)
        }
        return true
    }

    /// 1.8.2 之前的版本挂载时没带 `nobrowse`，卷会一直显示在 Finder 边栏和桌面上。
    /// 发现这种挂载就原地补上，不用等下次插盘或开机。失败只记日志：卷照常可用，下次重挂时会带上。
    private func hideFromFinderIfNeeded(_ mountPoint: URL) async {
        guard let flags = mountFlags(mountPoint), flags & UInt32(MNT_DONTBROWSE) == 0 else { return }
        do {
            try await disk.hideFromFinder(mountPoint: mountPoint, currentFlags: flags)
            AppLogger.shared.logContext("已为早期挂载的容器卷补上 nobrowse", details: [("mount_point", mountPoint.path)])
        } catch {
            AppLogger.shared.logContext(
                "为容器卷补 nobrowse 失败，卷仍可用，下次重挂时生效",
                details: [("mount_point", mountPoint.path), ("error", error.localizedDescription)],
                level: "WARN"
            )
        }
    }

    /// 挂载/迁移后补标记。任何失败都只记日志 —— 防索引是优化，
    /// 不该让挂载本身失败（例如卷以只读方式挂上时）。
    private func writeNeverIndexMarkerIfNeeded(at volumeRoot: URL, operationID: String) {
        do {
            guard try Self.writeNeverIndexMarker(at: volumeRoot, fileManager: fileManager) else { return }
            AppLogger.shared.logContext(
                "卷根已写入防索引标记",
                details: [("operation_id", operationID), ("volume_root", volumeRoot.path)]
            )
        } catch {
            AppLogger.shared.logError(
                "卷根写入防索引标记失败，Spotlight 可能继续索引该卷",
                error: error,
                errorCode: "CONTAINER-MOUNT-NEVER-INDEX-WRITE-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("volume_root", volumeRoot)]
            )
        }
    }

    // MARK: - 私有辅助：文件系统

    private func existingRealDirectory(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !isSymbolicLink(at: url)
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func makeMigrationBackupURL(for sourcePath: URL) -> URL {
        let parentURL = sourcePath.deletingLastPathComponent()
        let backupName = ".appports-migration-backup-\(sourcePath.lastPathComponent)-\(UUID().uuidString)"
        return parentURL.appendingPathComponent(backupName)
    }

    private func restoreMigrationBackup(_ backupURL: URL, to sourcePath: URL, operationID: String) -> Bool {
        if isMountPoint(sourcePath) || fileManager.fileExists(atPath: sourcePath.path) || isSymbolicLink(at: sourcePath) {
            AppLogger.shared.logError(
                "挂载迁移回滚：源路径仍存在，未覆盖恢复",
                errorCode: "CONTAINER-MOUNT-BACKUP-RESTORE-SOURCE-EXISTS",
                context: [("operation_id", operationID)],
                relatedURLs: [("source", sourcePath), ("backup", backupURL)]
            )
            return false
        }
        do {
            try fileManager.moveItem(at: backupURL, to: sourcePath)
            AppLogger.shared.logContext(
                "挂载迁移回滚：已恢复到本地源路径",
                details: [("operation_id", operationID), ("source_path", sourcePath.path), ("backup_path", backupURL.path)],
                level: "WARN"
            )
            return true
        } catch {
            AppLogger.shared.logError(
                "挂载迁移回滚：恢复到本地源路径失败，备份目录保留",
                error: error,
                errorCode: "CONTAINER-MOUNT-BACKUP-RESTORE-FAILED",
                context: [("operation_id", operationID)],
                relatedURLs: [("source", sourcePath), ("backup", backupURL)]
            )
            return false
        }
    }
}
