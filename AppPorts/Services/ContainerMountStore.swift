//
//  ContainerMountStore.swift
//  AppPorts
//

import Foundation

/// 持久化挂载迁移记录，供扫描、重挂载与后台挂载代理共用。
///
/// 记录文件位于 `~/Library/Application Support/AppPorts/container-mounts.plist`。
/// 挂载点在未挂载时是一个被锁住的空目录，记录文件是判断「待挂载」的唯一依据。
final class ContainerMountStore: @unchecked Sendable {
    static let shared = ContainerMountStore()

    private static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AppPorts/container-mounts.plist")
    }

    private let fileURL: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let writeData: @Sendable (Data, URL) throws -> Void

    /// 用同一次原子写入切换活动记录和清理记录，避免本地已还原但代理仍能重挂。
    /// 旧版本的数组格式仍可读取；新格式让旧版本安全地停止，而非把清理项当挂载项。
    private struct Document: Codable {
        var schemaVersion = 2
        var mounts: [ContainerMountRecord] = []
        var cleanups: [ContainerCleanupRecord] = []
    }

    enum StoreError: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "迁移记录无法读取，已停止修改并保留原记录。请检查文件权限或从备份恢复记录后重试。".localized
        }
    }

    init(
        fileURL: URL? = nil,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.writeData = writeData
    }

    /// 全部记录（按创建时间排序）
    func records() -> [ContainerMountRecord] {
        lock.lock()
        defer { lock.unlock() }
        do { return try load().mounts.sorted { $0.createdAt < $1.createdAt } }
        catch {
            AppLogger.shared.logError("挂载记录无法读取，保留原文件", error: error,
                errorCode: "CONTAINER-MOUNT-STORE-CORRUPT", relatedURLs: [("file", fileURL)])
            return []
        }
    }

    func pendingCleanups() throws -> [ContainerCleanupRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try load().cleanups
    }

    func record(forMountPoint url: URL) -> ContainerMountRecord? {
        let path = url.standardizedFileURL.path
        return records().first { $0.mountPointPath == path }
    }

    func upsert(_ record: ContainerMountRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try load()
        current.mounts.removeAll { $0.mountPointPath == record.mountPointPath }
        current.mounts.append(record)
        try save(current)
    }

    func remove(mountPointPath: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try load()
        current.mounts.removeAll { $0.mountPointPath == mountPointPath }
        try save(current)
    }

    /// 先同时保存挂载记录和备份位置，再尝试删除本地安全备份。
    func recordMigration(_ record: ContainerMountRecord, cleanup: ContainerCleanupRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try load()
        current.mounts.removeAll { $0.mountPointPath == record.mountPointPath }
        current.mounts.append(record)
        current.cleanups.append(cleanup)
        try save(current)
    }

    /// 必须在切换回本地目录前成功。清理记录保留卷 UUID，但不再参与自动挂载。
    func beginRestore(_ cleanup: ContainerCleanupRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try load()
        current.mounts.removeAll { $0.mountPointPath == cleanup.mountRecord.mountPointPath }
        current.cleanups.append(cleanup)
        try save(current)
    }

    /// 本地切换没有完成时，重新启用原挂载记录，并保留其它未清理的副本信息。
    func cancelRestore(_ cleanup: ContainerCleanupRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try load()
        current.cleanups.removeAll { $0.id == cleanup.id }
        current.mounts.removeAll { $0.mountPointPath == cleanup.mountRecord.mountPointPath }
        current.mounts.append(cleanup.mountRecord)
        try save(current)
    }

    func finishCleanup(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try load()
        current.cleanups.removeAll { $0.id == id }
        try save(current)
    }

    // MARK: - 私有辅助

    private func load() throws -> Document {
        guard fileManager.fileExists(atPath: fileURL.path) else { return Document() }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = PropertyListDecoder()
            if let legacy = try? decoder.decode([ContainerMountRecord].self, from: data) {
                return Document(mounts: legacy)
            }
            let document = try decoder.decode(Document.self, from: data)
            guard document.schemaVersion == 2 else { throw StoreError.unreadable }
            return document
        } catch {
            throw StoreError.unreadable
        }
    }

    private func save(_ document: Document) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try writeData(encoder.encode(document), fileURL)
    }
}
