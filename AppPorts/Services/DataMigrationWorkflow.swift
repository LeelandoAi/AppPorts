import Foundation

/// 已授权的签名属于数据迁移流程：备份完成后才迁移，重签完成后才向调用方返回成功。
enum DataMigrationWorkflow {
    /// 确认框对应的真实应用；批准不能沿着后来改变的本地入口传给另一应用。
    struct SigningTarget: Equatable, Sendable {
        let url: URL
        let isSandboxed: Bool

        init(url: URL, isSandboxed: Bool) {
            self.url = url.standardizedFileURL
            self.isSandboxed = isSandboxed
        }
    }

    static func signingTarget(at appURL: URL) throws -> SigningTarget {
        let realURL = try CodeSigner.resolveAppURL(at: appURL)
        return SigningTarget(url: realURL, isSandboxed: CodeSigner.isSandboxed(at: realURL))
    }

    enum Failure: LocalizedError {
        case signingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .signingFailed(let error):
                return String(
                    format: "数据已迁移，但关联应用重签名失败：%@\n\n请在应用列表中重试重签名，或还原数据目录。".localized,
                    error.localizedDescription
                )
            }
        }
    }

    static func run(
        signingAppURL: URL?,
        classicModeActive: Bool = false,
        approvedSandboxedTarget: SigningTarget? = nil,
        inspectSigningTarget: (URL) async throws -> SigningTarget = { try signingTarget(at: $0) },
        validateBeforeMigration: () async throws -> Void = {},
        backupSignature: (URL) async throws -> Void,
        migrate: () async throws -> Void,
        resignApp: (URL, Bool) async throws -> Void
    ) async throws {
        let target: SigningTarget?
        if let signingAppURL {
            let inspected = try await inspectSigningTarget(signingAppURL)
            if let approvedSandboxedTarget, approvedSandboxedTarget != inspected {
                throw CodeSigner.SigningError.applicationChanged
            }
            // 全局经典模式只是功能开关，不能替代这个真实应用的逐次批准。
            if inspected.isSandboxed,
               !(classicModeActive && approvedSandboxedTarget == inspected) {
                throw CodeSigner.SigningError.sandboxedApplication(inspected.url)
            }
            target = inspected
            try await backupSignature(inspected.url)
            // 备份可能耗时很长；入口或沙盒状态改变时，先停下，不搬动任何数据。
            guard try await inspectSigningTarget(signingAppURL) == inspected else {
                throw CodeSigner.SigningError.applicationChanged
            }
        } else {
            target = nil
        }

        try await validateBeforeMigration()
        try await migrate()

        if let signingAppURL, let target {
            do {
                guard try await inspectSigningTarget(signingAppURL) == target else {
                    throw CodeSigner.SigningError.applicationChanged
                }
                let sandboxedAppApproved = target.isSandboxed
                    && classicModeActive && approvedSandboxedTarget == target
                try await resignApp(target.url, sandboxedAppApproved)
            } catch {
                // 数据已经成功迁移；不要误报为迁移失败或自动再次搬运数据。
                throw Failure.signingFailed(error)
            }
        }
    }
}
