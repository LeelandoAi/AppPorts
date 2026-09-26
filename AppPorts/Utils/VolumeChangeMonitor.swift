//
//  VolumeChangeMonitor.swift
//  AppPorts
//

import Darwin
import Foundation

// MARK: - 目录变化的事件等待器

/// 盯住一个目录，等它的**真实变化事件**（kqueue），而不是靠定时轮询。
///
/// 用途：外置盘还没插上、或开机后系统还没把盘识别出来时，挂载代理只跑一遍就退出，
/// 只能指望 launchd 按 FSEvents 前缀匹配重新拉起（延迟不可控，开机时更慢）。
/// 这里直接盯 `/Volumes`：卷挂载与卸载都会改动 `/Volumes` 目录本身，
/// 实测 kqueue 在 120ms 内就收到事件，比 `hdiutil attach` 自己返回还早
/// （所以等完还要留一段"抖动窗口"，见 `settleInterval`）。
final class VolumeChangeMonitor: @unchecked Sendable {

    /// 一次变化事件。
    struct Change: Equatable, Sendable {
        /// kqueue 的 fflags，仅用于日志排障（挂载实测 0x12，卸载实测 0x2）。
        let flags: UInt32
        /// 从开始等待到收到事件的秒数。
        let waited: TimeInterval

        var flagsDescription: String { String(format: "0x%x", flags) }
    }

    /// 监听的事件：目录被写入、被改名、链接数变化、属性变化都算"内容变了"。
    private static let watchedFlags: UInt32 = UInt32(
        NOTE_WRITE | NOTE_DELETE | NOTE_EXTEND | NOTE_RENAME | NOTE_LINK | NOTE_ATTRIB
    )

    private let directory: URL
    /// 抖动窗口：挂一个卷往往连着来好几个事件（实测一次卸载先 0x2 再 0x12），
    /// 而且事件比卷真正可用早约 100ms。安静这么久之后才算"一次变化"。
    private let settleInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.shimoko.AppPorts.volumeChangeMonitor")
    private var directoryDescriptor: Int32 = -1
    private var queueDescriptor: Int32 = -1
    private var resolveAttempts = 0

    init(directory: URL = URL(fileURLWithPath: "/Volumes"), settleInterval: TimeInterval = 1.0) {
        self.directory = directory
        self.settleInterval = settleInterval
    }

    deinit {
        stop()
    }

    /// 开始监听。**越早调用越好**：开始之后发生的变化都会留在事件队列里，
    /// 所以"先开监听、再跑第一轮挂载"不会漏掉第一轮期间插上的盘。
    @discardableResult
    func start() -> Bool {
        queue.sync { openDescriptors() }
    }

    func stop() {
        queue.sync { closeDescriptors() }
    }

    /// 等下一次变化：安静 `settleInterval` 之后返回这次变化；`timeout` 秒内没有变化返回 nil。
    func waitForNextChange(timeout: TimeInterval) async -> Change? {
        guard timeout > 0 else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                let change = waitForChange(timeout: timeout)
                // 目录被删掉/替换后旧的文件描述符会失效（事件再也不会来），按 inode 判断并重新打开。
                if watchingStaleDirectory() {
                    _ = openDescriptors()
                }
                continuation.resume(returning: change)
            }
        }
    }

    // MARK: - 私有实现（全部在 queue 上执行）

    private func openDescriptors() -> Bool {
        closeDescriptors()
        resolveAttempts += 1
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            AppLogger.shared.logContext(
                "监听目录变化失败：无法打开目录",
                details: [("path", directory.path), ("errno", String(errno))],
                level: "WARN"
            )
            return false
        }
        let kqueueDescriptor = kqueue()
        guard kqueueDescriptor >= 0 else {
            close(descriptor)
            return false
        }
        var registration = kevent(
            ident: UInt(descriptor),
            filter: Int16(EVFILT_VNODE),
            flags: UInt16(EV_ADD | EV_CLEAR),
            fflags: Self.watchedFlags,
            data: 0,
            udata: nil
        )
        guard kevent(kqueueDescriptor, &registration, 1, nil, 0, nil) == 0 else {
            close(kqueueDescriptor)
            close(descriptor)
            AppLogger.shared.logContext(
                "监听目录变化失败：无法注册 kqueue",
                details: [("path", directory.path), ("errno", String(errno))],
                level: "WARN"
            )
            return false
        }
        directoryDescriptor = descriptor
        queueDescriptor = kqueueDescriptor
        AppLogger.shared.logContext(
            "开始监听目录变化",
            details: [("path", directory.path), ("settle_seconds", String(settleInterval)), ("attempt", String(resolveAttempts))],
            level: "TRACE"
        )
        return true
    }

    /// 手上的文件描述符是否已经指向一个"过期"的目录（路径被替换、卷被卸载）。
    private func watchingStaleDirectory() -> Bool {
        guard directoryDescriptor >= 0 else { return true }
        var opened = stat()
        guard fstat(directoryDescriptor, &opened) == 0 else { return true }
        var current = stat()
        guard stat(directory.path, &current) == 0 else { return false }
        return opened.st_ino != current.st_ino || opened.st_dev != current.st_dev
    }

    private func closeDescriptors() {
        if queueDescriptor >= 0 { close(queueDescriptor); queueDescriptor = -1 }
        if directoryDescriptor >= 0 { close(directoryDescriptor); directoryDescriptor = -1 }
    }

    private func waitForChange(timeout: TimeInterval) -> Change? {
        guard directoryDescriptor >= 0, queueDescriptor >= 0 else { return nil }
        let startedAt = Date()
        let hardDeadline = startedAt.addingTimeInterval(timeout)
        var changeDeadline = hardDeadline
        var flags: UInt32 = 0

        while true {
            let budget = changeDeadline.timeIntervalSinceNow
            guard budget > 0 else { break }
            var event = kevent()
            var timeoutSpec = makeTimeoutSpec(from: budget)
            let count = kevent(queueDescriptor, nil, 0, &event, 1, &timeoutSpec)
            if count < 0 {
                if errno == EINTR { continue }
                AppLogger.shared.logContext(
                    "等待目录变化出错",
                    details: [("path", directory.path), ("errno", String(errno))],
                    level: "WARN"
                )
                break
            }
            if count == 0 { break }
            flags |= UInt32(event.fflags)
            // 收到第一个事件后把截止时间收进抖动窗口，安静下来就返回。
            changeDeadline = min(hardDeadline, Date().addingTimeInterval(settleInterval))
        }

        guard flags != 0 else { return nil }
        return Change(flags: flags, waited: Date().timeIntervalSince(startedAt))
    }

    private func makeTimeoutSpec(from interval: TimeInterval) -> timespec {
        let clamped = max(0, interval)
        let seconds = clamped.rounded(.down)
        return timespec(tv_sec: Int(seconds), tv_nsec: Int((clamped - seconds) * 1_000_000_000))
    }
}
