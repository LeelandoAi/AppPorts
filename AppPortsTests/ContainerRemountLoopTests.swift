import Foundation
import Testing
@testable import AppPorts

@Suite("Container remount loop", .serialized)
struct ContainerRemountLoopTests {

    @Test("全部就位时只跑一轮，不等待")
    func stopsImmediatelyWhenSettled() async {
        let recorder = WaitRecorder()
        let result = await ContainerRemountLoop.run(
            attempt: { .results([Self.outcome(state: .mounted)]) },
            waitForChange: { timeout in await recorder.record(timeout: timeout) }
        )

        #expect(result.reason == .settled)
        #expect(result.cycles == 1)
        #expect(result.waited == false)
        #expect(await recorder.timeouts.isEmpty)
    }

    @Test("没有挂载记录时直接收工")
    func stopsWhenNoRecords() async {
        let result = await ContainerRemountLoop.run(
            attempt: { .results([]) },
            waitForChange: { _ in nil }
        )

        #expect(result.reason == .noRecords)
        #expect(result.outcomes.isEmpty)
    }

    @Test("卷没上线时等事件，事件到了就重试并成功")
    func retriesAfterEvent() async {
        let attempts = AttemptSequence([
            [Self.outcome(state: .unavailable)],
            [Self.outcome(state: .mounted)]
        ])
        let recorder = WaitRecorder(changes: [VolumeChangeMonitor.Change(flags: 0x12, waited: 3.2)])

        let result = await ContainerRemountLoop.run(
            policy: .init(window: 180, backstop: 20, maxCycles: 20),
            attempt: { .results(attempts.next()) },
            waitForChange: { await recorder.record(timeout: $0) }
        )

        #expect(result.reason == .settled)
        #expect(result.cycles == 2)
        #expect(result.waited)
        #expect(await recorder.timeouts == [20])
    }

    @Test("窗口用尽就收工，不会无限等")
    func stopsWhenWindowExpires() async {
        let clock = FakeClock()
        let recorder = WaitRecorder()

        let result = await ContainerRemountLoop.run(
            policy: .init(window: 60, backstop: 20, maxCycles: 20),
            attempt: { .results([Self.outcome(state: .unavailable)]) },
            waitForChange: { timeout in await recorder.record(timeout: timeout, clock: clock) },
            now: { clock.now }
        )

        #expect(result.reason == .windowExpired)
        #expect(result.cycles == 4)
        #expect(await recorder.timeouts == [20, 20, 20])
    }

    @Test("一直让路给主应用时如实标出来，而不是当成没有记录")
    func reportsAlwaysDeferred() async {
        let clock = FakeClock()
        let result = await ContainerRemountLoop.run(
            policy: .init(window: 30, backstop: 20, maxCycles: 20),
            attempt: { .deferred },
            waitForChange: { timeout in
                clock.advance(timeout)
                return nil
            },
            now: { clock.now }
        )

        #expect(result.reason == .alwaysDeferred)
        #expect(result.cycles == 3)
        #expect(result.deferredCycles == 3)
        #expect(result.outcomes.isEmpty)
    }

    @Test("轮数上限是双保险：事件不停也不会超过上限")
    func respectsCycleLimit() async {
        let result = await ContainerRemountLoop.run(
            policy: .init(window: 600, backstop: 20, maxCycles: 2),
            attempt: { .results([Self.outcome(state: .unavailable)]) },
            waitForChange: { _ in VolumeChangeMonitor.Change(flags: 0x12, waited: 0.1) }
        )

        #expect(result.reason == .cycleLimit)
        #expect(result.cycles == 2)
    }

    @Test("挂载失败的记录同样会继续等")
    func keepsWaitingForFailedRecords() {
        let pending = ContainerRemountLoop.pendingRecords(in: [
            Self.outcome(state: .failed("x")),
            Self.outcome(state: .unavailable),
            Self.outcome(state: .alreadyMounted),
            Self.outcome(state: .mounted)
        ])
        #expect(pending.count == 2)
    }

    // MARK: - 夹具

    private static func outcome(state: ContainerVolumeMigrator.RemountOutcome.State) -> ContainerVolumeMigrator.RemountOutcome {
        ContainerVolumeMigrator.RemountOutcome(
            record: ContainerMountRecord(
                appName: "Chat",
                bundleIdentifier: nil,
                dataDirType: DataDirType.containers.rawValue,
                mountPointPath: "/tmp/fixture-\(UUID().uuidString)",
                volumeUUID: "UUID",
                volumeName: "AppPorts-test",
                externalRootPath: "/Volumes/hano"
            ),
            state: state
        )
    }

    private final class AttemptSequence: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: [[ContainerVolumeMigrator.RemountOutcome]]

        init(_ attempts: [[ContainerVolumeMigrator.RemountOutcome]]) {
            self.remaining = attempts
        }

        func next() -> [ContainerVolumeMigrator.RemountOutcome] {
            lock.lock(); defer { lock.unlock() }
            guard !remaining.isEmpty else { return [] }
            return remaining.removeFirst()
        }
    }

    /// 记录每次等待的时长；给了 changes 就按顺序返回变化事件，否则一律超时。
    private actor WaitRecorder {
        private let changes: [VolumeChangeMonitor.Change?]
        private(set) var timeouts: [TimeInterval] = []

        init(changes: [VolumeChangeMonitor.Change?] = []) {
            self.changes = changes
        }

        func record(timeout: TimeInterval, clock: FakeClock? = nil) -> VolumeChangeMonitor.Change? {
            timeouts.append(timeout)
            clock?.advance(timeout)
            let index = timeouts.count - 1
            guard index < changes.count else { return nil }
            return changes[index]
        }
    }

    private final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_000_000)

        var now: Date { lock.lock(); defer { lock.unlock() }; return current }

        func advance(_ interval: TimeInterval) {
            lock.lock(); current = current.addingTimeInterval(interval); lock.unlock()
        }
    }
}
