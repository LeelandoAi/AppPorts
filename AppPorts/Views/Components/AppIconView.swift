//
//  AppIconView.swift
//  AppPorts
//
//  Created by shimoko.com on 2026/2/6.
//

import SwiftUI
import AppKit

/// 应用图标异步加载视图
struct AppIconView: View {
    let url: URL

    @State private var icon: NSImage? = nil

    nonisolated(unsafe) private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: 40, height: 40)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
        .task(id: url) {
            let requestedURL = url
            icon = nil

            let loadingTask = Task.detached(priority: .utility) {
                let result = Self.loadIconResult(from: requestedURL)

                if result.icon == nil, !Task.isCancelled {
                    AppLogger.shared.logContext(
                        "AppIconView 图标加载失败",
                        details: [
                            ("url", requestedURL.path),
                            ("exists", result.fileExists ? "YES" : "NO"),
                            ("resolved", result.resolvedPath)
                        ],
                        level: "WARN"
                    )
                }

                return result
            }
            let result = await withTaskCancellationHandler {
                await loadingTask.value
            } onCancel: {
                loadingTask.cancel()
            }

            guard !Task.isCancelled, url == requestedURL else { return }

            icon = result.icon
        }
    }

    private struct LoadResult: @unchecked Sendable {
        let icon: NSImage?
        let fileExists: Bool
        let resolvedPath: String
    }

    nonisolated private static func loadIconResult(from appURL: URL) -> LoadResult {
        let path = appURL.path
        let fileExists = FileManager.default.fileExists(atPath: path)
        let resolvedPath = appURL.resolvingSymlinksInPath().path
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            ?? Date(timeIntervalSince1970: 0)
        let cacheKey = "\(appURL.standardizedFileURL.path)|\(modificationDate.timeIntervalSince1970)" as NSString

        if let cachedIcon = iconCache.object(forKey: cacheKey) {
            return LoadResult(
                icon: cachedIcon,
                fileExists: fileExists,
                resolvedPath: resolvedPath
            )
        }

        guard !Task.isCancelled else {
            return LoadResult(icon: nil, fileExists: fileExists, resolvedPath: resolvedPath)
        }

        let loadedIcon = loadIcon(
            from: appURL,
            fileExists: fileExists,
            resolvedURL: URL(fileURLWithPath: resolvedPath)
        )
        if let loadedIcon {
            iconCache.setObject(loadedIcon, forKey: cacheKey)
        }

        return LoadResult(
            icon: loadedIcon,
            fileExists: fileExists,
            resolvedPath: resolvedPath
        )
    }

    nonisolated private static func loadIcon(
        from appURL: URL,
        fileExists: Bool,
        resolvedURL: URL
    ) -> NSImage? {
        let fm = FileManager.default
        let path = appURL.path

        // 方式 1: NSWorkspace
        if fileExists {
            guard !Task.isCancelled else { return nil }
            let icon = NSWorkspace.shared.icon(forFile: path)
            // 检查是否为 iOS app（有 Wrapper/WrappedBundle），尝试提取真实图标
            if let iosIcon = loadIOSAppIcon(from: appURL) {
                return iosIcon
            }
            return icon
        }

        // 方式 2: 解析符号链接后重试
        guard !Task.isCancelled else { return nil }
        if resolvedURL.path != path, fm.fileExists(atPath: resolvedURL.path) {
            return NSWorkspace.shared.icon(forFile: resolvedURL.path)
        }

        // 方式 3: 从 bundle .icns 直接读取
        for tryPath in [path, resolvedURL.path] {
            guard !Task.isCancelled else { return nil }
            guard fm.fileExists(atPath: tryPath) else { continue }
            guard let plist = NSDictionary(contentsOfFile: tryPath + "/Contents/Info.plist"),
                  let iconFile = plist["CFBundleIconFile"] as? String else { continue }
            let icnsName = iconFile.hasSuffix(".icns") ? iconFile : iconFile + ".icns"
            let icnsPath = tryPath + "/Contents/Resources/" + icnsName
            if let data = try? Data(contentsOf: URL(fileURLWithPath: icnsPath)),
               let img = NSImage(data: data) {
                return img
            }
        }

        // 最终回退
        return NSWorkspace.shared.icon(forFile: path)
    }

    /// 从 iOS app 的 Wrapper/ 目录提取 AppIcon PNG
    nonisolated private static func loadIOSAppIcon(from appURL: URL) -> NSImage? {
        guard !Task.isCancelled else { return nil }

        let fm = FileManager.default
        let wrapperDir: URL
        if fm.fileExists(atPath: appURL.appendingPathComponent("Wrapper").path) {
            wrapperDir = appURL.appendingPathComponent("Wrapper")
        } else if fm.fileExists(atPath: appURL.appendingPathComponent("WrappedBundle").path) {
            wrapperDir = appURL.appendingPathComponent("WrappedBundle")
        } else {
            return nil
        }

        // 查找内部 .app
        guard let innerApps = try? fm.contentsOfDirectory(at: wrapperDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
              let innerApp = innerApps.first(where: { $0.pathExtension == "app" }) else {
            return nil
        }

        // 查找最大的 AppIcon PNG
        guard let iconFiles = try? fm.contentsOfDirectory(at: innerApp, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
              let largestIcon = iconFiles
                .filter({ $0.lastPathComponent.hasPrefix("AppIcon") && $0.pathExtension == "png" })
                .max(by: { a, b in
                    (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <
                    (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0
                }) else {
            return nil
        }

        return NSImage(contentsOf: largestIcon)
    }
}
