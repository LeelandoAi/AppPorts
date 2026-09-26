import Foundation
import Testing
@testable import AppPorts

/// 挂载点判定的路径比较：挂载点的名字由内核给出（真实路径），
/// 记录里存的是应用路径，写法可能不一样。这里守住"不同写法也认得出来"。
@Suite("Disk utility path matching")
struct DiskUtilityPathTests {

    @Test("符号链接写法和真实路径算同一个位置")
    func matchesSymlinkedSpelling() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ap-path-match-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(DiskUtility.pathsMatch(link.path, real.path))
        #expect(DiskUtility.pathsMatch(real.path, link.path))
        #expect(DiskUtility.equivalentPaths(for: link).contains(real.path))
    }

    @Test("候选路径里包含内核 realpath：/tmp 这类写法不再被当成两个地方")
    func includesKernelResolvedPath() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ap-path-kernel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // 临时目录本身就在 /var → /private/var 这种符号链接后面，
        // `URL.resolvingSymlinksInPath()` 不一定解析得动，必须靠 realpath 兜住。
        let resolved = try #require(DiskUtility.resolvedPath(base.path))
        #expect(DiskUtility.equivalentPaths(for: base).contains(resolved))

        if let tmpTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: "/tmp") {
            #expect(tmpTarget == "private/tmp")
            #expect(DiskUtility.equivalentPaths(for: URL(fileURLWithPath: "/tmp")).contains("/private/tmp"))
        }
    }

    @Test("不同路径不会误判成同一个位置")
    func doesNotMatchDifferentPaths() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ap-path-distinct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("b"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(DiskUtility.pathsMatch(base.appendingPathComponent("a").path, base.appendingPathComponent("b").path) == false)
    }
}
