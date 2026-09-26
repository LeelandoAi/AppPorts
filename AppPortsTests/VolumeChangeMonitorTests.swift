import Foundation
import Testing
@testable import AppPorts

/// 事件等待器是"重试不靠定时器"的地基，这里用真实文件系统事件守它。
@Suite("Volume change monitor", .serialized)
struct VolumeChangeMonitorTests {

    @Test("目录一有变化就立刻返回，不用等满超时")
    func returnsOnDirectoryChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = VolumeChangeMonitor(directory: directory, settleInterval: 0.2)
        #expect(monitor.start())
        defer { monitor.stop() }

        let writer = Task.detached {
            try? await Task.sleep(nanoseconds: 300_000_000)
            try? Data("changed".utf8).write(to: directory.appendingPathComponent("event.txt"))
        }
        defer { writer.cancel() }

        let change = await monitor.waitForNextChange(timeout: 5)
        #expect(change != nil)
        #expect((change?.waited ?? .infinity) < 3)
        #expect((change?.flags ?? 0) != 0)
    }

    @Test("目录没动静就按时超时返回 nil")
    func timesOutWhenQuiet() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = VolumeChangeMonitor(directory: directory, settleInterval: 0.2)
        #expect(monitor.start())
        defer { monitor.stop() }

        let startedAt = Date()
        let change = await monitor.waitForNextChange(timeout: 0.4)
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(change == nil)
        #expect(elapsed < 3)
    }

    @Test("被监听的目录被替换（卸载后重建）之后仍能等到变化")
    func keepsWatchingAfterDirectoryReplacement() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("watched")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let monitor = VolumeChangeMonitor(directory: directory, settleInterval: 0.2)
        #expect(monitor.start())
        defer { monitor.stop() }

        // 整目录换掉：inode 变了，旧的描述符再也收不到事件，必须自己重新打开。
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = await monitor.waitForNextChange(timeout: 0.8)

        try Data("after".utf8).write(to: directory.appendingPathComponent("after.txt"))
        let change = await monitor.waitForNextChange(timeout: 5)
        #expect(change != nil)
    }

    @Test("目录不存在时开始监听会失败而不是崩")
    func failsToStartOnMissingDirectory() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("volume-change-monitor-missing-\(UUID().uuidString)")
        let monitor = VolumeChangeMonitor(directory: missing, settleInterval: 0.1)
        #expect(monitor.start() == false)
        monitor.stop()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("volume-change-monitor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
