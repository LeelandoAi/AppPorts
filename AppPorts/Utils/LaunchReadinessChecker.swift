//
//  LaunchReadinessChecker.swift
//  AppPorts
//
//  欢迎屏的启动自检：迁移所需权限是否齐全、外部存储格式是否满足要求。
//

import Foundation

// MARK: - 启动自检

/// 欢迎屏「状态检查」的判定逻辑。
///
/// 三个检查项：
/// 1. **完全磁盘访问权限**：读取 `~/Library` 下受 TCC 保护的应用数据（邮件、信息等）需要它；
/// 2. **App 管理权限**（`kTCCServiceSystemPolicyAppBundles`）：替换 `/Applications` 里的应用需要它；
/// 3. **外部存储格式**：只有沙盒应用的数据（挂载迁移）要求未加密的 APFS；其他情况说明「不影响其他迁移」。
///
/// 结果只用于提示，不阻断用户进入主界面：外部存储可以稍后再选。
struct LaunchReadinessChecker: Sendable {

    // MARK: 结果类型

    /// 单项检查结果
    struct Item: Identifiable, Equatable, Sendable {
        enum Level: Equatable, Sendable {
            /// 已满足
            case ok
            /// 不满足，但有退路（例如外部盘不是 APFS）
            case warning
            /// 不满足且必须处理（缺少权限）
            case failed
        }

        /// 点击「去设置授予权限」后要打开的系统设置面板
        enum Action: Equatable, Sendable {
            case fullDiskAccess
            case appManagement
        }

        let id: String
        let level: Level
        let title: String
        let detail: String
        let action: Action?
    }

    /// 外部存储的检查结果
    enum ExternalDriveState: Equatable, Sendable {
        /// 用户还没选外部存储
        case notSelected
        /// 路径不存在或卷信息读不出来（盘没插、卷已卸载）
        case unavailable(path: String)
        /// 已是 APFS，可以挂载迁移
        case apfs
        /// APFS 但已加密：挂载迁移新建的数据卷不会继承密码，所以不会把数据放到这里
        case encryptedAPFS
        /// 不是 APFS，挂载迁移不可用
        case notAPFS(filesystem: String?)
    }

    /// 检查项的稳定标识，界面与测试共用。
    enum ItemID {
        static let fullDiskAccess = "full-disk-access"
        static let appManagement = "app-management"
        static let externalDrive = "external-drive"
    }

    /// 外部存储路径在 UserDefaults 里的键，与主界面共用。
    static let externalDrivePathKey = "ExternalDrivePath"

    // MARK: 依赖注入

    /// 检测用到的外部依赖；测试注入假实现，避免依赖真机状态。
    struct Probe: Sendable {
        var hasFullDiskAccess: @Sendable () -> Bool
        var hasAppManagementPermission: @Sendable () -> Bool
        var externalDrivePath: @Sendable () -> String?
        var externalDriveState: @Sendable (_ path: String) async -> ExternalDriveState
    }

    let probe: Probe

    init(probe: Probe = .live) {
        self.probe = probe
    }

    // MARK: 检查

    /// 依次检查三项，返回界面直接可用的结果列表。
    func check() async -> [Item] {
        let savedPath = probe.externalDrivePath()
        let driveState: ExternalDriveState
        if let savedPath, !savedPath.isEmpty {
            driveState = await probe.externalDriveState(savedPath)
        } else {
            driveState = .notSelected
        }

        return Self.items(
            hasFullDiskAccess: probe.hasFullDiskAccess(),
            hasAppManagementPermission: probe.hasAppManagementPermission(),
            externalDriveState: driveState
        )
    }

    /// 纯函数版本：把已检测到的状态映射成检查项，方便测试。
    static func items(
        hasFullDiskAccess: Bool,
        hasAppManagementPermission: Bool,
        externalDriveState: ExternalDriveState
    ) -> [Item] {
        [
            fullDiskAccessItem(granted: hasFullDiskAccess),
            appManagementItem(granted: hasAppManagementPermission),
            externalDriveItem(state: externalDriveState)
        ]
    }

    private static func fullDiskAccessItem(granted: Bool) -> Item {
        guard granted else {
            return Item(
                id: ItemID.fullDiskAccess,
                level: .failed,
                title: "完全磁盘访问权限".localized,
                detail: "AppPorts 读取邮件、信息等受保护的应用数据目录需要它。请在「系统设置 › 隐私与安全性 › 完全磁盘访问权限」里勾选 AppPorts。".localized,
                action: .fullDiskAccess
            )
        }
        return Item(
            id: ItemID.fullDiskAccess,
            level: .ok,
            title: "完全磁盘访问权限".localized,
            detail: "已授予，可以读取受保护的应用数据目录。".localized,
            action: nil
        )
    }

    private static func appManagementItem(granted: Bool) -> Item {
        guard granted else {
            return Item(
                id: ItemID.appManagement,
                level: .failed,
                title: "App 管理权限".localized,
                detail: "迁移应用需要替换 /Applications 里的本地副本。请在「系统设置 › 隐私与安全性 › App 管理」里允许 AppPorts。".localized,
                action: .appManagement
            )
        }
        return Item(
            id: ItemID.appManagement,
            level: .ok,
            title: "App 管理权限".localized,
            detail: "已授予，可以替换 /Applications 里的应用。".localized,
            action: nil
        )
    }

    private static func externalDriveItem(state: ExternalDriveState) -> Item {
        switch state {
        case .notSelected:
            return Item(
                id: ItemID.externalDrive,
                level: .warning,
                title: "外部存储".localized,
                detail: "可以先开始使用，之后再选择存放应用的外部存储。".localized,
                action: nil
            )
        case .unavailable(let path):
            return Item(
                id: ItemID.externalDrive,
                level: .warning,
                title: "外部存储".localized,
                detail: String(
                    format: "读不到外部存储路径：%@。请连接外部存储后重新检查。".localized,
                    path
                ),
                action: nil
            )
        case .apfs:
            return Item(
                id: ItemID.externalDrive,
                level: .ok,
                title: "外部存储".localized,
                detail: "格式为 APFS。应用和数据目录都可以迁移到这里，包括沙盒应用的数据（如聊天记录）。".localized,
                action: nil
            )
        case .encryptedAPFS:
            return Item(
                id: ItemID.externalDrive,
                level: .warning,
                title: "外部存储".localized,
                detail: "格式为 APFS（已加密）。应用和普通数据目录可以迁移到这里；沙盒应用的数据（如聊天记录）不会迁移到加密的外部存储，会继续留在本机。".localized,
                action: nil
            )
        case .notAPFS(let filesystem):
            // 不把用户引向经典模式：它会重签沙盒应用，在 macOS 27 上可能让应用打不开。
            let format = filesystemDisplayName(filesystem) ?? "未知格式".localized
            return Item(
                id: ItemID.externalDrive,
                level: .warning,
                title: "外部存储".localized,
                detail: String(
                    format: "当前格式：%@。应用和普通数据目录可以照常迁移到这里。只有沙盒应用的数据（如聊天记录）需要 APFS 格式；这部分留在本机也不影响使用，不需要为此改动这块盘。".localized,
                    format
                ),
                action: nil
            )
        }
    }

    /// diskutil 给出的文件系统类型（apfs/hfs/exfat…）转成用户认得的写法。
    static func filesystemDisplayName(_ type: String?) -> String? {
        guard let raw = type?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "apfs": return "APFS"
        case "hfs": return "HFS+"
        case "exfat": return "ExFAT"
        case "msdos", "fat": return "FAT32"
        case "ntfs": return "NTFS"
        default: return raw.uppercased()
        }
    }

    // MARK: 探针实现

    /// 只有拿到「完全磁盘访问权限」才能打开的文件；按先后顺序探测。
    static func fullDiskAccessProbePaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "\(homeDirectory)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(homeDirectory)/Library/Messages/chat.db",
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
    }

    /// 尝试打开受 TCC 保护的文件来判断完全磁盘访问权限。
    ///
    /// - Note: 用 `open` 而不是 `FileManager.isReadableFile`：系统拦截的是真正的打开操作。
    ///   所有候选文件都不存在时无法判断，按「未授权」处理，引导用户去系统设置确认。
    static func hasFullDiskAccess(candidatePaths: [String] = fullDiskAccessProbePaths()) -> Bool {
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
        }
        return false
    }

    /// 往 `/Applications` 写一个临时文件来判断 App 管理权限，与「应用数据」页的判断方式一致。
    static func hasAppManagementPermission() -> Bool {
        let testFile = URL(fileURLWithPath: "/Applications/.appports-permission-test")
        do {
            try Data().write(to: testFile, options: .atomic)
            try FileManager.default.removeItem(at: testFile)
            return true
        } catch {
            return false
        }
    }

    /// 读取外部存储路径所在卷的文件系统类型。
    static func externalDriveState(atPath path: String, disk: DiskUtility = DiskUtility()) async -> ExternalDriveState {
        guard FileManager.default.fileExists(atPath: path) else { return .unavailable(path: path) }
        // diskutil 只认卷的挂载点或设备，不认卷内子目录。
        let volumePath = DiskUtility.mountedVolumePath(containing: URL(fileURLWithPath: path)) ?? path
        guard let info = try? await disk.volumeInfo(for: volumePath) else { return .unavailable(path: path) }
        guard info.isAPFS else { return .notAPFS(filesystem: info.filesystemType) }
        return info.isEncrypted ? .encryptedAPFS : .apfs
    }
}

// MARK: - 生产环境探针

extension LaunchReadinessChecker.Probe {
    /// 真机上的检测实现。
    static let live = LaunchReadinessChecker.Probe(
        hasFullDiskAccess: { LaunchReadinessChecker.hasFullDiskAccess() },
        hasAppManagementPermission: { LaunchReadinessChecker.hasAppManagementPermission() },
        externalDrivePath: { UserDefaults.standard.string(forKey: LaunchReadinessChecker.externalDrivePathKey) },
        externalDriveState: { path in await LaunchReadinessChecker.externalDriveState(atPath: path) }
    )
}

// MARK: - 系统设置入口

extension LaunchReadinessChecker.Item.Action {
    /// 对应的「系统设置」面板；旧系统没有「App 管理」面板时退回「隐私与安全性」首页。
    var settingsURLs: [URL] {
        let rawValues: [String]
        switch self {
        case .fullDiskAccess:
            rawValues = ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        case .appManagement:
            rawValues = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement",
                "x-apple.systempreferences:com.apple.preference.security"
            ]
        }
        return rawValues.compactMap { URL(string: $0) }
    }
}
