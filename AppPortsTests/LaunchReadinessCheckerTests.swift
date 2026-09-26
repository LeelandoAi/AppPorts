//
//  LaunchReadinessCheckerTests.swift
//  AppPorts
//
//  欢迎屏「启动状态检查」：权限与外部存储格式的判定逻辑。
//

import Foundation
import Testing
@testable import AppPorts

@Suite("Launch readiness check")
struct LaunchReadinessCheckerTests {

    // MARK: 检查项映射

    @Test("三项都满足时全部通过")
    func allSatisfied() {
        let items = LaunchReadinessChecker.items(
            hasFullDiskAccess: true,
            hasAppManagementPermission: true,
            externalDriveState: .apfs
        )

        #expect(items.map(\.id) == [
            LaunchReadinessChecker.ItemID.fullDiskAccess,
            LaunchReadinessChecker.ItemID.appManagement,
            LaunchReadinessChecker.ItemID.externalDrive
        ])
        #expect(items.allSatisfy { $0.level == .ok })
        #expect(items.allSatisfy { $0.action == nil })
    }

    @Test("缺少完全磁盘访问权限时报失败并给出设置入口")
    func missingFullDiskAccess() throws {
        let items = LaunchReadinessChecker.items(
            hasFullDiskAccess: false,
            hasAppManagementPermission: true,
            externalDriveState: .apfs
        )

        let item = try #require(items.first { $0.id == LaunchReadinessChecker.ItemID.fullDiskAccess })
        #expect(item.level == .failed)
        #expect(item.action == .fullDiskAccess)
        #expect(item.title == "完全磁盘访问权限")
    }

    @Test("缺少 App 管理权限时报失败并给出设置入口")
    func missingAppManagement() {
        let items = LaunchReadinessChecker.items(
            hasFullDiskAccess: true,
            hasAppManagementPermission: false,
            externalDriveState: .apfs
        )

        let item = items.first { $0.id == LaunchReadinessChecker.ItemID.appManagement }
        #expect(item?.level == .failed)
        #expect(item?.action == .appManagement)
    }

    // MARK: 外部存储

    @Test("没选外部存储只是提醒，不拦截")
    func externalDriveNotSelected() {
        let item = driveItem(state: .notSelected)
        #expect(item?.level == .warning)
        #expect(item?.action == nil)
    }

    @Test("外部存储读不到时提示连接后重新检查")
    func externalDriveUnavailable() {
        let item = driveItem(state: .unavailable(path: "/Volumes/Missing"))
        #expect(item?.level == .warning)
        #expect(item?.detail.contains("/Volumes/Missing") == true)
    }

    @Test("APFS 外部存储通过")
    func externalDriveAPFS() {
        let item = driveItem(state: .apfs)
        #expect(item?.level == .ok)
        #expect(item?.action == nil)
    }

    @Test("非 APFS 外部存储说明只影响沙盒应用数据，不把用户引向经典模式")
    func externalDriveNotAPFS() {
        let item = driveItem(state: .notAPFS(filesystem: "ExFAT"))
        #expect(item?.level == .warning)
        #expect(item?.detail.contains("ExFAT") == true)
        #expect(item?.detail.contains("APFS") == true)
        // 经典模式会重签沙盒应用，在 macOS 27 上可能让应用打不开，不能作为默认退路推荐。
        #expect(item?.detail.contains("经典") == false)
        // 占位符必须被真实格式替换掉
        #expect(item?.detail.contains("%@") == false)
    }

    @Test("加密的 APFS 外部存储提醒沙盒应用数据会留在本机")
    func externalDriveEncryptedAPFS() {
        let item = driveItem(state: .encryptedAPFS)
        #expect(item?.level == .warning)
        #expect(item?.action == nil)
        #expect(item?.detail.contains("APFS") == true)
    }

    @Test("读不出文件系统类型时用「未知格式」兜底")
    func externalDriveUnknownFormat() {
        let item = driveItem(state: .notAPFS(filesystem: nil))
        #expect(item?.level == .warning)
        #expect(item?.detail.contains("%@") == false)
    }

    @Test("文件系统类型转成常见写法")
    func filesystemDisplayNames() {
        #expect(LaunchReadinessChecker.filesystemDisplayName("hfs") == "HFS+")
        #expect(LaunchReadinessChecker.filesystemDisplayName("exfat") == "ExFAT")
        #expect(LaunchReadinessChecker.filesystemDisplayName("apfs") == "APFS")
        #expect(LaunchReadinessChecker.filesystemDisplayName("msdos") == "FAT32")
        #expect(LaunchReadinessChecker.filesystemDisplayName("ntfs") == "NTFS")
        #expect(LaunchReadinessChecker.filesystemDisplayName("  ") == nil)
        #expect(LaunchReadinessChecker.filesystemDisplayName(nil) == nil)
    }

    // MARK: 探针装配

    @Test("check() 会用保存的外部路径去查格式")
    func checkUsesSavedPath() async {
        let recorder = PathRecorder()
        let checker = LaunchReadinessChecker(probe: LaunchReadinessChecker.Probe(
            hasFullDiskAccess: { true },
            hasAppManagementPermission: { true },
            externalDrivePath: { "/Volumes/TestDrive" },
            externalDriveState: { path in
                await recorder.record(path)
                return .notAPFS(filesystem: "exfat")
            }
        ))

        let items = await checker.check()
        let probedPaths = await recorder.paths
        #expect(probedPaths == ["/Volumes/TestDrive"])
        #expect(items.first { $0.id == LaunchReadinessChecker.ItemID.externalDrive }?.level == .warning)
    }

    @Test("没保存外部路径时不调用 diskutil")
    func checkSkipsDiskutilWithoutSavedPath() async {
        let recorder = PathRecorder()
        let checker = LaunchReadinessChecker(probe: LaunchReadinessChecker.Probe(
            hasFullDiskAccess: { true },
            hasAppManagementPermission: { true },
            externalDrivePath: { nil },
            externalDriveState: { path in
                await recorder.record(path)
                return .apfs
            }
        ))

        let items = await checker.check()
        let probedPaths = await recorder.paths
        #expect(probedPaths.isEmpty)
        #expect(items.first { $0.id == LaunchReadinessChecker.ItemID.externalDrive }?.level == .warning)
    }

    @Test("空字符串的外部路径按「未选择」处理")
    func checkTreatsEmptyPathAsNotSelected() async {
        let checker = LaunchReadinessChecker(probe: LaunchReadinessChecker.Probe(
            hasFullDiskAccess: { true },
            hasAppManagementPermission: { true },
            externalDrivePath: { "" },
            externalDriveState: { _ in .apfs }
        ))

        let items = await checker.check()
        #expect(items.first { $0.id == LaunchReadinessChecker.ItemID.externalDrive }?.level == .warning)
    }

    // MARK: 外部存储格式探测

    @Test("APFS 卷判定为 .apfs")
    func detectsAPFSVolume() async throws {
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanup() }
        let fake = FakeDiskCommandRunner(externalFilesystem: "apfs")

        let state = await LaunchReadinessChecker.externalDriveState(
            atPath: workspace.root.path,
            disk: DiskUtility(runner: fake)
        )
        #expect(state == .apfs)
    }

    @Test("加密的 APFS 卷判定为 .encryptedAPFS")
    func detectsEncryptedAPFSVolume() async throws {
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanup() }
        let fake = FakeDiskCommandRunner(externalFilesystem: "apfs", externalEncrypted: true)

        let state = await LaunchReadinessChecker.externalDriveState(
            atPath: workspace.root.path,
            disk: DiskUtility(runner: fake)
        )
        #expect(state == .encryptedAPFS)
    }

    @Test("非 APFS 卷带回实际格式")
    func detectsNonAPFSVolume() async throws {
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanup() }
        let fake = FakeDiskCommandRunner(externalFilesystem: "exfat")

        let state = await LaunchReadinessChecker.externalDriveState(
            atPath: workspace.root.path,
            disk: DiskUtility(runner: fake)
        )
        #expect(state == .notAPFS(filesystem: "exfat"))
    }

    @Test("路径不存在时判定为不可用，不问 diskutil")
    func missingPathIsUnavailable() async {
        let fake = FakeDiskCommandRunner()

        let state = await LaunchReadinessChecker.externalDriveState(
            atPath: "/Volumes/AppPorts-Not-Connected",
            disk: DiskUtility(runner: fake)
        )
        #expect(state == .unavailable(path: "/Volumes/AppPorts-Not-Connected"))
        #expect(fake.calls.isEmpty)
    }

    // MARK: 完全磁盘访问权限探针

    @Test("能打开受保护文件时判定为已授权")
    func fullDiskAccessProbeReadsFile() throws {
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanup() }
        let readable = workspace.root.appendingPathComponent("readable.db")
        try Data("x".utf8).write(to: readable)

        #expect(LaunchReadinessChecker.hasFullDiskAccess(candidatePaths: [readable.path]))
    }

    @Test("打不开受保护文件时判定为未授权")
    func fullDiskAccessProbeRejectsUnreadableFile() throws {
        let workspace = try TemporaryWorkspace()
        defer { workspace.cleanup() }
        let unreadable = workspace.root.appendingPathComponent("unreadable.db")
        try Data("x".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)

        #expect(LaunchReadinessChecker.hasFullDiskAccess(candidatePaths: [unreadable.path]) == false)
    }

    @Test("候选文件都不存在时按未授权处理")
    func fullDiskAccessProbeWithoutCandidates() {
        let missing = "/tmp/appports-missing-\(UUID().uuidString)/TCC.db"
        #expect(LaunchReadinessChecker.hasFullDiskAccess(candidatePaths: [missing]) == false)
    }

    @Test("默认候选路径覆盖用户与系统 TCC 数据库")
    func defaultProbePaths() {
        let paths = LaunchReadinessChecker.fullDiskAccessProbePaths(homeDirectory: "/Users/example")
        #expect(paths.contains("/Users/example/Library/Application Support/com.apple.TCC/TCC.db"))
        #expect(paths.contains("/Users/example/Library/Messages/chat.db"))
        #expect(paths.contains("/Library/Application Support/com.apple.TCC/TCC.db"))
    }

    // MARK: 系统设置入口

    @Test("检查项自带对应系统设置面板")
    func settingsURLs() {
        #expect(LaunchReadinessChecker.Item.Action.fullDiskAccess.settingsURLs.count == 1)
        #expect(LaunchReadinessChecker.Item.Action.fullDiskAccess.settingsURLs[0].absoluteString.contains("Privacy_AllFiles"))

        let appManagement = LaunchReadinessChecker.Item.Action.appManagement.settingsURLs
        #expect(appManagement.count == 2)
        #expect(appManagement[0].absoluteString.contains("Privacy_AppManagement"))
    }

    // MARK: 辅助

    private func driveItem(state: LaunchReadinessChecker.ExternalDriveState) -> LaunchReadinessChecker.Item? {
        LaunchReadinessChecker.items(
            hasFullDiskAccess: true,
            hasAppManagementPermission: true,
            externalDriveState: state
        ).first { $0.id == LaunchReadinessChecker.ItemID.externalDrive }
    }

    private actor PathRecorder {
        private(set) var paths: [String] = []

        func record(_ path: String) {
            paths.append(path)
        }
    }

    private struct TemporaryWorkspace {
        let root: URL

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("appports-readiness-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func cleanup() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
