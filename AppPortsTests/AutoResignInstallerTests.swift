import Foundation
import Testing
@testable import AppPorts

@Suite("Background signing coordination", .serialized)
struct AutoResignInstallerTests {
    @Test("An explicitly absent login task needs no stop command")
    func absentTask() async throws {
        let runner = Runner(responses: [.result(status: 113, text: "Could not find service")])
        try await AutoResignInstaller.stopBackgroundTask(runner: runner)
        #expect(await runner.calls.count == 1)
    }

    @Test("Permission errors cannot be mistaken for an absent task")
    func queryFailure() async throws {
        let runner = Runner(responses: [.result(status: 1, text: "Operation not permitted")])
        await #expect(throws: AutoResignInstaller.InstallError.self) {
            try await AutoResignInstaller.stopBackgroundTask(runner: runner)
        }
        #expect(await runner.calls.count == 1)
    }

    @Test("Supported systems wait for a single service to exit")
    func waitForBootout() async throws {
        let runner = Runner(responses: [.result(text: "pid = 99999"), .result(text: "bootout [--wait]"), .result()])
        try await AutoResignInstaller.stopBackgroundTask(runner: runner, processGroupIsRunning: { _ in false })
        let commands = await runner.calls
        #expect(commands.last?.prefix(2) == ["bootout", "--wait"])
        #expect(commands.last?.last?.hasSuffix("/com.shimoko.AppPorts.re-sign") == true)
    }

    @Test("Old systems require the entire process group to exit")
    func refusesLiveChildProcesses() async throws {
        let runner = Runner(responses: [.result(text: "pid = 99999"), .result(text: "bootout <service>"), .result()])
        await #expect(throws: AutoResignInstaller.InstallError.self) {
            try await AutoResignInstaller.stopBackgroundTask(runner: runner, processGroupIsRunning: { _ in true }, timeout: 0)
        }
        #expect(await runner.calls.last?.first == "bootout")
        #expect(await runner.calls.last?.contains("--wait") == false)
    }

    @Test("A timed-out stop never permits signature restoration")
    func refusesStopTimeout() async throws {
        let runner = Runner(responses: [.result(text: "pid = 99999"), .result(text: "--wait"), .result(timedOut: true)])
        await #expect(throws: AutoResignInstaller.InstallError.self) {
            try await AutoResignInstaller.stopBackgroundTask(runner: runner, processGroupIsRunning: { _ in false })
        }
    }

    private actor Runner: ShellCommandRunning {
        var responses: [Response]
        private(set) var calls: [[String]] = []
        init(responses: [Response]) { self.responses = responses }
        func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ShellCommandResult {
            calls.append(arguments)
            let response = responses.removeFirst()
            return ShellCommandResult(status: response.status, standardOutput: Data(response.text.utf8), standardError: Data(), timedOut: response.timedOut)
        }
    }

    private struct Response {
        let status: Int32
        let text: String
        let timedOut: Bool
        static func result(status: Int32 = 0, text: String = "", timedOut: Bool = false) -> Self {
            Self(status: status, text: text, timedOut: timedOut)
        }
    }
}
