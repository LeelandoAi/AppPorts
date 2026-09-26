import Foundation
import Testing
@testable import AppPorts

@Suite("Signature repair restore safety")
@MainActor
struct SignatureRepairSafetyTests {
    enum RunningIdentity: CaseIterable {
        case pathOnly, bundleIdentifierOnly
    }

    @Test("A running real app is rejected before the operation becomes busy", arguments: RunningIdentity.allCases)
    func rejectsRunningAppBeforeBegin(identity: RunningIdentity) throws {
        let workspace = try Workspace()
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        var running: [AppRunningState.RunningApplication] = []
        var reads = 0
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) {
            reads += 1
            return running
        }

        // 模拟扫描时未运行，点击「全部还原」前真实应用已从外部副本启动。
        running = [workspace.runningApplication(identity: identity)]
        #expect(workflow.begin(operationState: operationState) == .appRunning)
        #expect(operationState.isBusy == false)
        #expect(reads == 1)
    }

    @Test("Stopping the app after scanning allows the entire batch to restore")
    func usesFreshStoppedStateAndRestoresInOrder() async throws {
        let workspace = try Workspace()
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        var running = [workspace.runningApplication()]
        var reads = 0
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) {
            reads += 1
            return running
        }
        running = []
        let token = try startedToken(workflow.begin(operationState: operationState))
        defer { operationState.finish(token) }
        let items = workspace.items(count: 3)
        var restored: [String] = []
        var indices: [Int] = []

        let outcome = await workflow.run(items: items) { item, index in
            #expect(operationState.isBusy)
            restored.append(item.id)
            indices.append(index)
            await Task.yield()
        }

        guard case .completed = outcome else {
            Issue.record("A stopped application should allow the batch to complete")
            return
        }
        #expect(restored == items.map(\.id))
        #expect(indices == [0, 1, 2])
        #expect(reads == 4, "Read once at begin and immediately before each directory")
        operationState.finish(token)
        #expect(operationState.isBusy == false)
    }

    @Test("Launching after begin prevents even the first directory restore")
    func rechecksBeforeFirstDirectory() async throws {
        let workspace = try Workspace()
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        var running: [AppRunningState.RunningApplication] = []
        var reads = 0
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) {
            reads += 1
            return running
        }
        let token = try startedToken(workflow.begin(operationState: operationState))
        defer { operationState.finish(token) }
        running = [workspace.runningApplication()]
        var restored: [String] = []

        let outcome = await workflow.run(items: workspace.items(count: 2)) { item, _ in
            restored.append(item.id)
        }

        guard case .appRunning = outcome else {
            Issue.record("The first restore must recheck the app after the asynchronous task starts")
            return
        }
        #expect(restored.isEmpty)
        #expect(reads == 2)
    }

    @Test("Relaunching during a restore stops before the next directory", arguments: [0, 1])
    func rechecksBetweenDirectories(relaunchAfterIndex: Int) async throws {
        let workspace = try Workspace()
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        var running: [AppRunningState.RunningApplication] = []
        var reads = 0
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) {
            reads += 1
            return running
        }
        let token = try startedToken(workflow.begin(operationState: operationState))
        defer { operationState.finish(token) }
        let items = workspace.items(count: 3)
        var restored: [String] = []

        let outcome = await workflow.run(items: items) { item, index in
            restored.append(item.id)
            if index == relaunchAfterIndex {
                running = [workspace.runningApplication()]
                await Task.yield()
            }
        }

        guard case .appRunning = outcome else {
            Issue.record("A relaunched app must stop the remaining restores")
            return
        }
        #expect(restored == items.prefix(relaunchAfterIndex + 1).map(\.id))
        #expect(reads == relaunchAfterIndex + 3)
    }

    @Test("Unrelated processes with missing bundle identifiers do not block repair")
    func ignoresUnrelatedProcesses() async throws {
        let workspace = try Workspace(identifier: nil)
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) {
            [
                .init(bundleURL: nil, bundleIdentifier: nil),
                .init(bundleURL: workspace.root.appendingPathComponent("Other.app"), bundleIdentifier: nil),
                .init(bundleURL: nil, bundleIdentifier: "")
            ]
        }
        let token = try startedToken(workflow.begin(operationState: operationState))
        defer { operationState.finish(token) }
        let items = workspace.items(count: 2)
        var restored: [String] = []

        let outcome = await workflow.run(items: items) { item, _ in
            restored.append(item.id)
        }

        guard case .completed = outcome else {
            Issue.record("Unrelated running applications should not prevent repair")
            return
        }
        #expect(restored == items.map(\.id))
    }

    @Test("An existing operation keeps its token when a repair batch cannot begin")
    func preservesBusyOperationOwnership() throws {
        let workspace = try Workspace()
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        let existingToken = try #require(operationState.begin())
        defer { operationState.finish(existingToken) }
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) { [] }

        #expect(workflow.begin(operationState: operationState) == .busy)
        #expect(operationState.isBusy)
        operationState.finish(UUID())
        #expect(operationState.isBusy)
        operationState.finish(existingToken)
        #expect(operationState.isBusy == false)
    }

    @Test("A restore failure reports its directory and leaves later directories untouched")
    func stopsAfterRestoreFailure() async throws {
        let workspace = try Workspace()
        defer { workspace.cleanup() }
        let operationState = AppOperationState()
        let workflow = SignatureRepairRestoreWorkflow(appURL: workspace.portalURL) { [] }
        let token = try startedToken(workflow.begin(operationState: operationState))
        defer { operationState.finish(token) }
        let items = workspace.items(count: 3)
        var attempted: [String] = []

        let outcome = await workflow.run(items: items) { item, index in
            attempted.append(item.id)
            if index == 1 { throw RestoreFailure.copyFailed }
        }

        guard case .restoreFailed(let failedItem, let error) = outcome else {
            Issue.record("Expected the failing directory and its original error")
            return
        }
        #expect(failedItem.id == items[1].id)
        #expect(error as? RestoreFailure == .copyFailed)
        #expect(attempted == items.prefix(2).map(\.id))
    }

    private enum RestoreFailure: Error {
        case copyFailed
    }

    private func startedToken(_ result: SignatureRepairRestoreWorkflow.StartResult) throws -> UUID {
        let token: UUID?
        if case .started(let value) = result {
            token = value
        } else {
            token = nil
        }
        return try #require(token, "Expected the repair batch to acquire an operation token")
    }

    private struct Workspace {
        let root: URL
        let realAppURL: URL
        let portalURL: URL
        let identifier: String?

        init(identifier: String? = "com.appports.tests.signature-repair") throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("SignatureRepairSafetyTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            realAppURL = root.appendingPathComponent("External/Chat.app")
            portalURL = root.appendingPathComponent("Chat.app")
            self.identifier = identifier
            try Self.makeBundle(at: realAppURL, identifier: identifier)
            try Self.makeBundle(at: portalURL, identifier: "com.appports.tests.signature-repair.appports.stub")
            try realAppURL.path.write(
                to: portalURL.appendingPathComponent("Contents/Resources/real_app_path.txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        func runningApplication(identity: RunningIdentity = .pathOnly) -> AppRunningState.RunningApplication {
            switch identity {
            case .pathOnly:
                return .init(bundleURL: realAppURL, bundleIdentifier: nil)
            case .bundleIdentifierOnly:
                return .init(bundleURL: nil, bundleIdentifier: identifier)
            }
        }

        func items(count: Int) -> [DataDirItem] {
            (0..<count).map { index in
                DataDirItem(
                    name: "Container \(index)",
                    path: root.appendingPathComponent("Containers/\(index)"),
                    type: .containers,
                    priority: .critical,
                    description: "",
                    status: DataDirStatus.linked,
                    linkedDestination: root.appendingPathComponent("External/Data/\(index)")
                )
            }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }

        private static func makeBundle(at url: URL, identifier: String?) throws {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("Contents/Resources"),
                withIntermediateDirectories: true
            )
            var info = ["CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
            if let identifier { info["CFBundleIdentifier"] = identifier }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
        }
    }
}
