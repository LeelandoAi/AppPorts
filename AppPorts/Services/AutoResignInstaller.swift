//
//  AutoResignInstaller.swift
//  AppPorts
//

import Foundation

/// 管理“开机自动重签名” LaunchAgent 的安装与卸载
///
/// 安装后在 ~/Library/LaunchAgents/ 创建一个 plist，
/// 用户每次登录时自动对签名已失效的已迁移应用执行 ad-hoc 重签名。
enum AutoResignInstaller {

    private static let label = "com.shimoko.AppPorts.re-sign"
    private static let scriptName = "AppPorts-ReSign.sh"
    private static let backgroundTaskStopper = BackgroundTaskStopper()

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AppPorts")
    }

    private static var scriptURL: URL {
        appSupportDir.appendingPathComponent(scriptName)
    }

    // MARK: - Install

    /// 升级时先停止旧任务再同步脚本；保留 plist，下次登录仍按用户设置运行。
    static func refreshInstalledScriptIfNeeded() async throws {
        guard isInstalled,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let bundledScript = Bundle.main.url(forResource: scriptName, withExtension: nil) else {
            throw InstallError.scriptNotFound
        }
        if (try? Data(contentsOf: scriptURL)) != (try Data(contentsOf: bundledScript)) {
            try await stopBackgroundTask()
        }
        try synchronizeScript(from: bundledScript, to: scriptURL)
    }

    /// 旧脚本可能已读完记录并准备原地重签。仅更新脚本或记录不能取消它，
    /// 手动签名事务开始前必须确认本次登录任务及其子进程已退出。
    /// 不删除 plist，也不在当前会话重新 bootstrap，避免刚恢复就再次后台重签。
    static func stopBackgroundTask(
        runner: ShellCommandRunning = ProcessCommandRunner(),
        processGroupIsRunning: @escaping @Sendable (Int32) -> Bool = { kill(-$0, 0) == 0 || errno != ESRCH },
        timeout: TimeInterval = 15
    ) async throws {
        try await backgroundTaskStopper.stop(runner: runner, processGroupIsRunning: processGroupIsRunning, timeout: timeout)
    }

    private actor BackgroundTaskStopper {
        // actor 在 await 时可重入；共享进行中的任务，让启动刷新和手动操作等同一个停止屏障。
        private var pending: Task<Void, Error>?

        func stop(runner: ShellCommandRunning, processGroupIsRunning: @escaping @Sendable (Int32) -> Bool, timeout: TimeInterval) async throws {
            if let pending { return try await pending.value }
            let task = Task { try await AutoResignInstaller.stopLoadedTask(runner: runner, processGroupIsRunning: processGroupIsRunning, timeout: timeout) }
            pending = task
            defer { pending = nil }
            try await task.value
        }
    }

    private static func stopLoadedTask(
        runner: ShellCommandRunning,
        processGroupIsRunning: @escaping @Sendable (Int32) -> Bool,
        timeout: TimeInterval
    ) async throws {
        let target = "gui/\(getuid())/\(label)"
        let status = try await runner.run(executable: "/bin/launchctl", arguments: ["print", target], timeout: timeout)
        guard !status.timedOut else { throw InstallError.backgroundTaskStillRunning }
        if status.status != 0 {
            guard status.combinedText.localizedCaseInsensitiveContains("could not find service") else {
                throw InstallError.backgroundTaskStillRunning
            }
            return
        }
        let pid = status.stdoutText.components(separatedBy: .newlines).compactMap { line -> Int32? in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " = ")
            guard parts.count == 2, parts[0] == "pid" else { return nil }
            return Int32(parts[1])
        }.first
        let help = try await runner.run(executable: "/bin/launchctl", arguments: ["help", "bootout"], timeout: timeout)
        let supportsWait = help.combinedText.contains("--wait")
        let arguments = supportsWait ? ["bootout", "--wait", target] : ["bootout", target]
        let stopped = try await runner.run(executable: "/bin/launchctl", arguments: arguments, timeout: timeout)
        guard !stopped.timedOut else { throw InstallError.backgroundTaskStillRunning }
        if stopped.status != 0 {
            // 启动刷新和手动操作可能同时停同一任务；只有确认任务已不存在才接受。
            let check = try await runner.run(executable: "/bin/launchctl", arguments: ["print", target], timeout: timeout)
            guard !check.timedOut, check.status != 0,
                  check.combinedText.localizedCaseInsensitiveContains("could not find service") else {
                throw InstallError.backgroundTaskStillRunning
            }
        }
        // 旧系统没有 bootout --wait。launchd 为任务建立独立进程组并在 bootout 时清理；
        // 等整组消失，不能只等 bash 退出而漏掉仍在运行的 codesign 子进程。
        let deadline = Date().addingTimeInterval(timeout)
        if let pid, pid > 1 {
            while processGroupIsRunning(pid) {
                guard Date() < deadline else { throw InstallError.backgroundTaskStillRunning }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    static func synchronizeScript(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        if (try? Data(contentsOf: destination)) != data {
            try data.write(to: destination, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    static func install() throws {
        let fm = FileManager.default
        let appSupportDirURL = appSupportDir

        // 1. 确保 Application Support 目录存在
        if !fm.fileExists(atPath: appSupportDirURL.path) {
            try fm.createDirectory(at: appSupportDirURL, withIntermediateDirectories: true)
        }

        // 2. 复制脚本
        guard let bundledScript = Bundle.main.url(forResource: scriptName, withExtension: nil) else {
            throw InstallError.scriptNotFound
        }
        try synchronizeScript(from: bundledScript, to: scriptURL)

        // 3. 创建 LaunchAgent plist
        let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(label)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/bin/bash</string>
                    <string>\(scriptURL.path)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>EnvironmentVariables</key>
                <dict>
                    <key>PATH</key>
                    <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
                </dict>
            </dict>
            </plist>
            """

        try plistContent.write(to: agentPlistURL, atomically: true, encoding: .utf8)

        // 4. 加载 LaunchAgent
        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        load.arguments = ["bootstrap", "gui/\(getuid())", agentPlistURL.path]
        try load.run()
        load.waitUntilExit()

        if load.terminationStatus != 0 {
            // 降级：尝试旧版 load
            let legacy = Process()
            legacy.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            legacy.arguments = ["load", agentPlistURL.path]
            try legacy.run()
            legacy.waitUntilExit()

            if legacy.terminationStatus != 0 {
                throw InstallError.launchAgentLoadFailed
            }
        }

        AppLogger.shared.log("开机自动重签名已安装")
    }

    // MARK: - Uninstall

    static func uninstall() {
        let fm = FileManager.default

        // 1. 卸载 LaunchAgent
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["bootout", "gui/\(getuid())", agentPlistURL.path]
        try? unload.run()
        unload.waitUntilExit()

        // 降级
        let legacy = Process()
        legacy.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        legacy.arguments = ["unload", agentPlistURL.path]
        try? legacy.run()
        legacy.waitUntilExit()

        // 2. 删除文件
        try? fm.removeItem(at: agentPlistURL)
        try? fm.removeItem(at: scriptURL)

        AppLogger.shared.log("开机自动重签名已卸载")
    }

    // MARK: - Status

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    enum InstallError: LocalizedError {
        case scriptNotFound
        case launchAgentLoadFailed
        case backgroundTaskStillRunning

        var errorDescription: String? {
            switch self {
            case .scriptNotFound:
                return "找不到重签名脚本，安装失败".localized
            case .launchAgentLoadFailed:
                return "LaunchAgent 加载失败".localized
            case .backgroundTaskStillRunning:
                return "无法确认后台重签任务已经停止，已取消本次操作以保护原始签名。请稍后重试。".localized
            }
        }
    }
}
