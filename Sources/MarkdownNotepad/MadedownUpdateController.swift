import AppKit
import Foundation
import SwiftUI

struct MadedownReleaseAsset: Codable, Identifiable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int
    let contentType: String?

    var id: String { downloadURL.absoluteString }

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

struct MadedownRelease: Codable, Sendable {
    let tagName: String
    let name: String?
    let notes: String?
    let pageURL: URL
    let isDraft: Bool
    let isPrerelease: Bool
    let assets: [MadedownReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case notes = "body"
        case pageURL = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case assets
    }
}

struct MadedownSemanticVersion: Comparable, CustomStringConvertible, Sendable {
    private enum Identifier: Equatable, Sendable {
        case number(Int)
        case text(String)
    }

    private let core: [Int]
    private let prerelease: [Identifier]
    let original: String

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.first.map { $0 == "v" || $0 == "V" } == true
            ? String(trimmed.dropFirst())
            : trimmed
        let versionAndMetadata = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let versionAndPrerelease = versionAndMetadata[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let components = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        core = components.map { Int($0) ?? 0 }
        if versionAndPrerelease.count == 2, !versionAndPrerelease[1].isEmpty {
            prerelease = versionAndPrerelease[1].split(separator: ".").map { component in
                if component.allSatisfy(\.isNumber), let number = Int(component) {
                    return .number(number)
                }
                return .text(component.lowercased())
            }
        } else {
            prerelease = []
        }
        original = trimmed
    }

    var description: String { original }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.core.count, rhs.core.count)
        for index in 0..<count {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right {
                return left < right
            }
        }

        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }

        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            guard left != right else { continue }
            switch (left, right) {
            case let (.number(leftNumber), .number(rightNumber)):
                return leftNumber < rightNumber
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            case let (.text(leftText), .text(rightText)):
                return leftText.localizedStandardCompare(rightText) == .orderedAscending
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

enum MadedownUpdateError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int)
    case invalidRelease
    case invalidVersion(String)
    case noInstallerAsset
    case unsafeDownloadURL
    case emptyDownload
    case unsupportedInstallerFormat
    case unableToPrepareInstaller(String)
    case invalidApplicationBundle(String)
    case currentApplicationCannotBeReplaced
    case updaterHelperMissing
    case unableToStartUpdater
    case unableToDismissUpdateSheet
    case updaterFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return MadedownL10n.text(
                "GitHub returned an unrecognized response.",
                "GitHub 返回了无法识别的响应。"
            )
        case let .requestFailed(statusCode):
            return MadedownL10n.text(
                "The GitHub request failed (HTTP \(statusCode)). Please try again later.",
                "GitHub 请求失败（HTTP \(statusCode)）。请稍后重试。"
            )
        case .invalidRelease:
            return MadedownL10n.text(
                "The latest GitHub Release is not an installable stable version.",
                "GitHub 最新 Release 不是可安装的稳定版本。"
            )
        case let .invalidVersion(version):
            return MadedownL10n.text(
                "Unrecognized version: \(version)",
                "无法识别版本号：\(version)"
            )
        case .noInstallerAsset:
            return MadedownL10n.text(
                "The latest Release does not contain a macOS DMG or ZIP suitable for an in-place update.",
                "最新 Release 中没有找到可原位更新的 macOS DMG 或 ZIP 安装包。"
            )
        case .unsafeDownloadURL:
            return MadedownL10n.text(
                "The installer download URL failed the security check.",
                "安装包下载地址未通过安全检查。"
            )
        case .emptyDownload:
            return MadedownL10n.text(
                "The downloaded installer is empty. Please try again.",
                "下载的安装包为空，请重试。"
            )
        case .unsupportedInstallerFormat:
            return MadedownL10n.text(
                "This installer format does not support a safe in-place update.",
                "该安装包格式不支持安全的原位更新。"
            )
        case let .unableToPrepareInstaller(message):
            return MadedownL10n.text(
                "Unable to prepare the update: \(message)",
                "无法解包更新：\(message)"
            )
        case let .invalidApplicationBundle(message):
            return MadedownL10n.text(
                "The update failed application validation: \(message)",
                "更新包未通过应用校验：\(message)"
            )
        case .currentApplicationCannotBeReplaced:
            return MadedownL10n.text(
                "This process is not running from Madedown.app, so the development build cannot be replaced. Check for updates from an installed app.",
                "当前程序不是从 Madedown.app 中运行，不能覆盖开发构建。请使用已安装的应用检查更新。"
            )
        case .updaterHelperMissing:
            return MadedownL10n.text(
                "This app does not contain the in-place update helper. Please replace it once from GitHub Releases.",
                "当前应用缺少原位更新助手，请先从 GitHub Releases 手动替换一次。"
            )
        case .unableToStartUpdater:
            return MadedownL10n.text(
                "The update helper could not start. The installed version was not changed.",
                "无法启动更新助手，旧版本没有被改动。"
            )
        case .unableToDismissUpdateSheet:
            return MadedownL10n.text(
                "The update window could not close before installation. The installed version was not changed.",
                "安装前无法关闭更新窗口，旧版本没有被改动。"
            )
        case let .updaterFailed(message):
            return MadedownL10n.text(
                "The update helper stopped before installation completed: \(message)",
                "更新助手未能完成安装：\(message)"
            )
        }
    }
}

enum MadedownUpdateLogic {
    enum InstallLaunchDecision: Equatable {
        case waitForUpdateSheet
        case launchUpdater
    }

    static let repository = "zhxnix/Madedown"
    static let bundledVersionFallback = "1.3.2"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundledVersionFallback
    }

    static func isNewerVersion(_ candidate: String, than current: String) throws -> Bool {
        guard let candidateVersion = MadedownSemanticVersion(candidate) else {
            throw MadedownUpdateError.invalidVersion(candidate)
        }
        guard let currentVersion = MadedownSemanticVersion(current) else {
            throw MadedownUpdateError.invalidVersion(current)
        }
        return candidateVersion > currentVersion
    }

    static func preferredAsset(in release: MadedownRelease) -> MadedownReleaseAsset? {
        release.assets
            .filter { isSafeGitHubDownloadURL($0.downloadURL) }
            .filter { asset in
                let extensionName = asset.name.lowercased()
                return extensionName.hasSuffix(".dmg") ||
                    extensionName.hasSuffix(".zip")
            }
            .sorted { assetScore($0) < assetScore($1) }
            .first
    }

    static func isSafeGitHubDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" ||
            host == "objects.githubusercontent.com" ||
            host.hasSuffix(".githubusercontent.com")
    }

    static func installLaunchDecision(updateSheetIsAttached: Bool) -> InstallLaunchDecision {
        updateSheetIsAttached ? .waitForUpdateSheet : .launchUpdater
    }

    private static func assetScore(_ asset: MadedownReleaseAsset) -> (Int, Int, String) {
        let name = asset.name.lowercased()
        let formatScore: Int
        if name.hasSuffix(".dmg") {
            formatScore = 0
        } else {
            formatScore = 1
        }
        let platformScore = name.contains("madedown") || name.contains("mac") || name.contains("universal") ? 0 : 1
        return (formatScore, platformScore, name)
    }

    static func runSelfTests() {
        precondition(
            try! isNewerVersion("v1.10.0", than: "1.9.9"),
            "Update version comparison must compare numeric components"
        )
        precondition(
            !(try! isNewerVersion("2.0.0-beta.2", than: "2.0.0")),
            "A prerelease must not replace the matching stable release"
        )
        precondition(
            MadedownSemanticVersion("1.0") == MadedownSemanticVersion("1.0.0"),
            "Equivalent semantic versions should compare equally"
        )

        let release = MadedownRelease(
            tagName: "v2.0.0",
            name: "Madedown 2.0.0",
            notes: nil,
            pageURL: URL(string: "https://github.com/zhxnix/Madedown/releases/tag/v2.0.0")!,
            isDraft: false,
            isPrerelease: false,
            assets: [
                MadedownReleaseAsset(
                    name: "Source.zip",
                    downloadURL: URL(string: "https://github.com/zhxnix/Madedown/releases/download/v2.0.0/Source.zip")!,
                    size: 10,
                    contentType: "application/zip"
                ),
                MadedownReleaseAsset(
                    name: "Madedown-2.0.0.dmg",
                    downloadURL: URL(string: "https://github.com/zhxnix/Madedown/releases/download/v2.0.0/Madedown.dmg")!,
                    size: 20,
                    contentType: "application/x-apple-diskimage"
                )
            ]
        )
        precondition(
            preferredAsset(in: release)?.name == "Madedown-2.0.0.dmg",
            "The updater must prefer the native DMG installer"
        )
        precondition(
            !isSafeGitHubDownloadURL(URL(string: "http://example.com/Madedown.dmg")!),
            "The updater must reject non-HTTPS and non-GitHub download URLs"
        )
        let packageOnlyRelease = MadedownRelease(
            tagName: "v2.0.0",
            name: nil,
            notes: nil,
            pageURL: release.pageURL,
            isDraft: false,
            isPrerelease: false,
            assets: [
                MadedownReleaseAsset(
                    name: "Madedown-2.0.0.pkg",
                    downloadURL: URL(string: "https://github.com/zhxnix/Madedown/releases/download/v2.0.0/Madedown.pkg")!,
                    size: 20,
                    contentType: "application/vnd.apple.installer+xml"
                )
            ]
        )
        precondition(
            preferredAsset(in: packageOnlyRelease) == nil,
            "The in-place updater must not open a PKG that can create a second installation"
        )
        precondition(
            installLaunchDecision(updateSheetIsAttached: true) == .waitForUpdateSheet,
            "The updater must not ask AppKit to terminate while its modal sheet is attached"
        )
        precondition(
            installLaunchDecision(updateSheetIsAttached: false) == .launchUpdater,
            "The updater should launch only after its modal sheet is detached"
        )
    }
}

private struct GitHubReleaseClient: Sendable {
    func latestStableRelease() async throws -> MadedownRelease {
        guard let endpoint = URL(
            string: "https://api.github.com/repos/\(MadedownUpdateLogic.repository)/releases/latest"
        ) else {
            throw MadedownUpdateError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Madedown/\(MadedownUpdateLogic.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MadedownUpdateError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MadedownUpdateError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(MadedownRelease.self, from: data)
        guard !release.isDraft, !release.isPrerelease else {
            throw MadedownUpdateError.invalidRelease
        }
        return release
    }
}

private final class MadedownAssetDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let progressHandler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    init(destinationURL: URL, progressHandler: @escaping @Sendable (Double) -> Void) {
        self.destinationURL = destinationURL
        self.progressHandler = progressHandler
    }

    func start(request: URLRequest) async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 60 * 30
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            finish(.failure(MadedownUpdateError.invalidResponse))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            finish(.failure(MadedownUpdateError.requestFailed(statusCode: response.statusCode)))
            return
        }

        do {
            try FileManager.default.copyItem(at: location, to: destinationURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                try? FileManager.default.removeItem(at: destinationURL)
                throw MadedownUpdateError.emptyDownload
            }
            finish(.success(destinationURL))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              MadedownUpdateLogic.isSafeGitHubDownloadURL(redirectedURL) else {
            completionHandler(nil)
            finish(.failure(MadedownUpdateError.unsafeDownloadURL))
            return
        }
        completionHandler(request)
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}

private struct MadedownDownloadedAsset: Sendable {
    let fileURL: URL
    let workspaceURL: URL
}

private enum MadedownReleaseDownloader {
    static func download(
        _ asset: MadedownReleaseAsset,
        version: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> MadedownDownloadedAsset {
        guard MadedownUpdateLogic.isSafeGitHubDownloadURL(asset.downloadURL) else {
            throw MadedownUpdateError.unsafeDownloadURL
        }

        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let updatesDirectory = supportDirectory
            .appendingPathComponent("Madedown", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
        removeStaleWorkspaces(in: updatesDirectory, fileManager: fileManager)

        let workspace = updatesDirectory.appendingPathComponent(
            "update-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)

        let sanitizedName = asset.name.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "-",
            options: .regularExpression
        )
        let destination = workspace.appendingPathComponent("\(version)-\(sanitizedName)")

        var request = URLRequest(url: asset.downloadURL)
        request.timeoutInterval = 30
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Madedown/\(MadedownUpdateLogic.currentVersion)", forHTTPHeaderField: "User-Agent")
        let operation = MadedownAssetDownloadOperation(
            destinationURL: destination,
            progressHandler: progress
        )
        do {
            let fileURL = try await operation.start(request: request)
            return MadedownDownloadedAsset(fileURL: fileURL, workspaceURL: workspace)
        } catch {
            try? fileManager.removeItem(at: workspace)
            throw error
        }
    }

    private static func removeStaleWorkspaces(in directory: URL, fileManager: FileManager) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let expiry = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for entry in entries {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < expiry {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}

private struct MadedownApplicationUpdateContext: Sendable {
    let targetAppURL: URL
    let bundledHelperURL: URL
}

struct MadedownPreparedUpdate: Sendable {
    let stagedAppURL: URL
    let targetAppURL: URL
    let helperURL: URL
    let workspaceURL: URL
    let expectedVersion: String
}

private enum MadedownUpdatePackagePreparer {
    private static let expectedBundleIdentifier = "io.github.zhxnix.Madedown"

    static func applicationContext() throws -> MadedownApplicationUpdateContext {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Info.plist").path),
              Bundle.main.bundleIdentifier == expectedBundleIdentifier else {
            throw MadedownUpdateError.currentApplicationCannotBeReplaced
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            throw MadedownUpdateError.updaterHelperMissing
        }
        let helperURL = resourceURL.appendingPathComponent("MadedownUpdaterHelper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw MadedownUpdateError.updaterHelperMissing
        }
        return MadedownApplicationUpdateContext(targetAppURL: bundleURL, bundledHelperURL: helperURL)
    }

    static func prepare(
        downloaded: MadedownDownloadedAsset,
        asset: MadedownReleaseAsset,
        release: MadedownRelease,
        context: MadedownApplicationUpdateContext
    ) async throws -> MadedownPreparedUpdate {
        try await Task.detached(priority: .userInitiated) {
            try prepareSynchronously(
                downloaded: downloaded,
                asset: asset,
                release: release,
                context: context
            )
        }.value
    }

    static func runDMGExtractionSelfTest(_ dmgURL: URL, expectedVersion: String) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "Madedown-DMGPreparation-\(UUID().uuidString)",
            isDirectory: true
        )
        let mountURL = root.appendingPathComponent("mounted", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? run("/usr/bin/hdiutil", arguments: ["detach", "-force", "-quiet", mountURL.path])
            try? fileManager.removeItem(at: root)
        }

        let copiedApp = try appFromDMG(dmgURL, mountedAt: mountURL)
        try validateApplication(copiedApp, expectedVersion: expectedVersion)
        let remainingMountContents = try fileManager.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: nil
        )
        guard remainingMountContents.isEmpty else {
            throw MadedownUpdateError.unableToPrepareInstaller(
                MadedownL10n.text(
                    "The DMG remained mounted after extraction",
                    "提取完成后 DMG 仍处于挂载状态"
                )
            )
        }
    }

    private static func prepareSynchronously(
        downloaded: MadedownDownloadedAsset,
        asset: MadedownReleaseAsset,
        release: MadedownRelease,
        context: MadedownApplicationUpdateContext
    ) throws -> MadedownPreparedUpdate {
        let fileManager = FileManager.default
        let extractedRoot = downloaded.workspaceURL.appendingPathComponent("extracted", isDirectory: true)
        let stagedApp = downloaded.workspaceURL.appendingPathComponent("Madedown.app", isDirectory: true)
        let helperCopy = downloaded.workspaceURL.appendingPathComponent("MadedownUpdaterHelper")
        try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

        let lowercasedName = asset.name.lowercased()
        let sourceApp: URL
        if lowercasedName.hasSuffix(".dmg") {
            sourceApp = try appFromDMG(downloaded.fileURL, mountedAt: extractedRoot)
        } else if lowercasedName.hasSuffix(".zip") {
            try run("/usr/bin/ditto", arguments: ["-x", "-k", downloaded.fileURL.path, extractedRoot.path])
            sourceApp = try findApplication(in: extractedRoot)
        } else {
            throw MadedownUpdateError.unsupportedInstallerFormat
        }

        try run("/usr/bin/ditto", arguments: [sourceApp.path, stagedApp.path])
        try validateApplication(stagedApp, expectedVersion: release.tagName)
        try fileManager.copyItem(at: context.bundledHelperURL, to: helperCopy)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperCopy.path)
        try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", helperCopy.path])

        return MadedownPreparedUpdate(
            stagedAppURL: stagedApp,
            targetAppURL: context.targetAppURL,
            helperURL: helperCopy,
            workspaceURL: downloaded.workspaceURL,
            expectedVersion: release.tagName
        )
    }

    private static func appFromDMG(_ dmgURL: URL, mountedAt mountURL: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.removeItemIfPresent(at: mountURL)
        try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)
        try run(
            "/usr/bin/hdiutil",
            arguments: ["attach", dmgURL.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mountURL.path]
        )
        do {
            let app = try autoreleasepool {
                try findApplication(in: mountURL)
            }
            let copiedApp = mountURL.deletingLastPathComponent().appendingPathComponent("MountedMadedown.app")
            try run("/usr/bin/ditto", arguments: [app.path, copiedApp.path])
            try detachDMG(at: mountURL)
            return copiedApp
        } catch {
            try? detachDMG(at: mountURL)
            throw error
        }
    }

    private static func detachDMG(at mountURL: URL) throws {
        for attempt in 0..<10 {
            do {
                try run("/usr/bin/hdiutil", arguments: ["detach", "-quiet", mountURL.path])
                return
            } catch {
                guard attempt < 9 else { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        try run("/usr/bin/hdiutil", arguments: ["detach", "-force", "-quiet", mountURL.path])
    }

    private static func findApplication(in root: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw MadedownUpdateError.unableToPrepareInstaller(
                MadedownL10n.text("Unable to read the installer contents", "无法读取安装包内容")
            )
        }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: infoURL),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == expectedBundleIdentifier else {
                continue
            }
            return url
        }
        throw MadedownUpdateError.unableToPrepareInstaller(
            MadedownL10n.text("Madedown.app was not found in the installer", "安装包中没有找到 Madedown.app")
        )
    }

    private static func validateApplication(_ appURL: URL, expectedVersion: String) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String,
              MadedownSemanticVersion(version) == MadedownSemanticVersion(expectedVersion),
              let executable = info["CFBundleExecutable"] as? String,
              FileManager.default.isExecutableFile(
                atPath: appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path
              ) else {
            throw MadedownUpdateError.invalidApplicationBundle(
                MadedownL10n.text(
                    "The bundle identifier, version, or main executable is invalid",
                    "Bundle ID、版本号或主程序不正确"
                )
            )
        }
        try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
    }

    private static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MadedownUpdateError.unableToPrepareInstaller(error.localizedDescription)
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw MadedownUpdateError.unableToPrepareInstaller(
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

func runMadedownDMGExtractionSelfTest(_ dmgURL: URL, expectedVersion: String) throws {
    try MadedownUpdatePackagePreparer.runDMGExtractionSelfTest(
        dmgURL,
        expectedVersion: expectedVersion
    )
}

private extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}

@MainActor
final class MadedownUpdateController: ObservableObject {
    static let shared = MadedownUpdateController()

    enum State {
        case idle
        case checking(currentVersion: String)
        case upToDate(currentVersion: String, latestVersion: String)
        case available(release: MadedownRelease, asset: MadedownReleaseAsset)
        case downloading(release: MadedownRelease, asset: MadedownReleaseAsset, progress: Double)
        case preparing(release: MadedownRelease)
        case readyToInstall(release: MadedownRelease, update: MadedownPreparedUpdate)
        case installing(release: MadedownRelease)
        case failure(message: String)
    }

    @Published var isPresented = false
    @Published private(set) var state: State = .idle

    private var workTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var updaterProcess: Process?
    private var updaterErrorPipe: Pipe?
    private let client = GitHubReleaseClient()

    private init() {}

    func checkForUpdates() {
        discardPreparedUpdateIfNeeded()
        workTask?.cancel()
        let currentVersion = MadedownUpdateLogic.currentVersion
        state = .checking(currentVersion: currentVersion)
        isPresented = true

        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await client.latestStableRelease()
                try Task.checkCancellation()
                if try MadedownUpdateLogic.isNewerVersion(release.tagName, than: currentVersion) {
                    guard let asset = MadedownUpdateLogic.preferredAsset(in: release) else {
                        throw MadedownUpdateError.noInstallerAsset
                    }
                    state = .available(release: release, asset: asset)
                } else {
                    state = .upToDate(currentVersion: currentVersion, latestVersion: release.tagName)
                }
            } catch is CancellationError {
                state = .idle
                isPresented = false
            } catch let error as URLError where error.code == .cancelled {
                state = .idle
                isPresented = false
            } catch {
                state = .failure(message: error.localizedDescription)
            }
        }
    }

    func startUpgrade() {
        guard case let .available(release, asset) = state else { return }
        let context: MadedownApplicationUpdateContext
        do {
            context = try MadedownUpdatePackagePreparer.applicationContext()
        } catch {
            state = .failure(message: error.localizedDescription)
            return
        }

        state = .downloading(release: release, asset: asset, progress: 0)
        workTask = Task { [weak self] in
            guard let self else { return }
            var downloaded: MadedownDownloadedAsset?
            do {
                let downloadedAsset = try await MadedownReleaseDownloader.download(
                    asset,
                    version: release.tagName
                ) { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              case let .downloading(currentRelease, currentAsset, _) = self.state,
                              currentRelease.tagName == release.tagName else {
                            return
                        }
                        self.state = .downloading(
                            release: currentRelease,
                            asset: currentAsset,
                            progress: progress
                        )
                    }
                }
                downloaded = downloadedAsset
                try Task.checkCancellation()
                state = .preparing(release: release)
                let prepared = try await MadedownUpdatePackagePreparer.prepare(
                    downloaded: downloadedAsset,
                    asset: asset,
                    release: release,
                    context: context
                )
                try Task.checkCancellation()
                state = .readyToInstall(release: release, update: prepared)
            } catch is CancellationError {
                if let downloaded {
                    try? FileManager.default.removeItem(at: downloaded.workspaceURL)
                }
                state = .available(release: release, asset: asset)
            } catch let error as URLError where error.code == .cancelled {
                if let downloaded {
                    try? FileManager.default.removeItem(at: downloaded.workspaceURL)
                }
                state = .available(release: release, asset: asset)
            } catch {
                if let downloaded {
                    try? FileManager.default.removeItem(at: downloaded.workspaceURL)
                }
                state = .failure(message: error.localizedDescription)
            }
        }
    }

    func installAndRelaunch() {
        guard case let .readyToInstall(release, update) = state else { return }
        state = .installing(release: release)

        let updateSheet = activeUpdateSheet()
        isPresented = false
        installTask?.cancel()
        installTask = Task { [weak self] in
            guard let self else { return }
            let sheetDismissed = await waitForUpdateSheetToDismiss(updateSheet)
            guard !Task.isCancelled else { return }
            installTask = nil
            guard sheetDismissed else {
                failInstallation(
                    MadedownUpdateError.unableToDismissUpdateSheet.localizedDescription,
                    workspaceURL: update.workspaceURL
                )
                return
            }
            launchUpdater(update: update)
        }
    }

    private func activeUpdateSheet() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow, keyWindow.sheetParent != nil {
            return keyWindow
        }
        return NSApp.windows.lazy.compactMap(\.attachedSheet).first
    }

    private func waitForUpdateSheetToDismiss(_ updateSheet: NSWindow?) async -> Bool {
        for _ in 0..<100 {
            let isAttached = updateSheet?.sheetParent != nil
            if MadedownUpdateLogic.installLaunchDecision(updateSheetIsAttached: isAttached) == .launchUpdater {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                return false
            }
        }
        return false
    }

    private func launchUpdater(update: MadedownPreparedUpdate) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = update.helperURL
        process.arguments = [
            "--staged-app", update.stagedAppURL.path,
            "--target-app", update.targetAppURL.path,
            "--workspace", update.workspaceURL.path,
            "--expected-version", update.expectedVersion,
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] completedProcess in
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let helperMessage = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in
                guard let self, updaterProcess === completedProcess else { return }
                updaterProcess = nil
                updaterErrorPipe = nil
                guard completedProcess.terminationStatus != 0 else { return }
                let message = helperMessage.flatMap { $0.isEmpty ? nil : $0 }
                    ?? MadedownL10n.text("Unknown helper error", "未知的更新助手错误")
                failInstallation(
                    MadedownUpdateError.updaterFailed(message).localizedDescription,
                    workspaceURL: update.workspaceURL
                )
            }
        }

        updaterProcess = process
        updaterErrorPipe = errorPipe
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            updaterProcess = nil
            updaterErrorPipe = nil
            failInstallation(
                MadedownUpdateError.unableToStartUpdater.localizedDescription,
                workspaceURL: update.workspaceURL
            )
        }
    }

    private func failInstallation(_ message: String, workspaceURL: URL) {
        try? FileManager.default.removeItem(at: workspaceURL)
        state = .failure(message: message)
        isPresented = true
    }

    func openReleasePage(_ release: MadedownRelease) {
        NSWorkspace.shared.open(release.pageURL)
    }

    func cancelWork() {
        discardPreparedUpdateIfNeeded()
        workTask?.cancel()
        workTask = nil
        isPresented = false
    }

    func dismiss() {
        discardPreparedUpdateIfNeeded()
        isPresented = false
    }

    private func discardPreparedUpdateIfNeeded() {
        guard case let .readyToInstall(_, update) = state else { return }
        try? FileManager.default.removeItem(at: update.workspaceURL)
        state = .idle
    }
}

struct MadedownUpdateView: View {
    @ObservedObject var controller: MadedownUpdateController
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                Text(language.text("Madedown Update", "Madedown 更新"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }

            content

            Divider()
            actions
        }
        .padding(22)
        .frame(width: 500)
        .frame(minHeight: 250)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle:
            Text(language.text("Ready to check GitHub Releases.", "准备检查 GitHub Releases。"))
                .foregroundStyle(.secondary)
        case let .checking(currentVersion):
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(language.text(
                    "Checking for the latest version… (current: \(currentVersion))",
                    "正在检查最新版本…（当前 \(currentVersion)）"
                ))
            }
        case let .upToDate(currentVersion, latestVersion):
            VStack(alignment: .leading, spacing: 8) {
                Label(language.text("Madedown is up to date", "已经是最新版本"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14, weight: .semibold))
                Text(language.text(
                    "Current version: \(currentVersion). Latest GitHub version: \(latestVersion).",
                    "当前版本 \(currentVersion)，GitHub 最新版本 \(latestVersion)。"
                ))
                    .foregroundStyle(.secondary)
            }
        case let .available(release, asset):
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("New version available: \(release.tagName)", "发现新版本 \(release.tagName)"))
                    .font(.system(size: 15, weight: .semibold))
                Text(language.text(
                    "Installer: \(asset.name) · \(ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file))",
                    "安装包：\(asset.name) · \(ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file))"
                ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        case let .downloading(release, asset, progress):
            VStack(alignment: .leading, spacing: 10) {
                Text(language.text("Downloading \(release.tagName)", "正在下载 \(release.tagName)"))
                    .font(.system(size: 14, weight: .semibold))
                ProgressView(value: progress)
                HStack {
                    Text(asset.name)
                    Spacer()
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        case let .preparing(release):
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text(
                        "Validating and preparing \(release.tagName)",
                        "正在校验并准备 \(release.tagName)"
                    ))
                        .font(.system(size: 14, weight: .semibold))
                    Text(language.text(
                        "Checking the bundle identifier, version, and code signature. The current app is not being changed yet.",
                        "正在核对 Bundle ID、版本号与代码签名，不会改动当前应用。"
                    ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        case let .readyToInstall(release, update):
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    language.text("\(release.tagName) passed validation", "\(release.tagName) 已通过校验"),
                    systemImage: "checkmark.shield.fill"
                )
                    .foregroundStyle(.green)
                    .font(.system(size: 14, weight: .semibold))
                Text(language.text(
                    "After you choose Install and Relaunch, Madedown will quit and replace the current app in place. The old version is kept only as a temporary rollback copy and is removed after the new version launches successfully, so a second app is not installed.",
                    "点击“安装并重新启动”后，Madedown 会退出并在原路径替换当前版本。旧版本只作为临时回滚副本保留；新版本启动成功后会自动删除，不会再安装出第二份应用。"
                ))
                    .foregroundStyle(.secondary)
                Text(update.targetAppURL.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.tertiary)
            }
        case let .installing(release):
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(language.text(
                    "Quitting and installing \(release.tagName)…",
                    "正在退出并安装 \(release.tagName)…"
                ))
            }
        case let .failure(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(language.text("Unable to Complete Update", "无法完成更新"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14, weight: .semibold))
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            switch controller.state {
            case let .available(release, _):
                Button(language.text("View Release", "查看发布页")) {
                    controller.openReleasePage(release)
                }
                Spacer()
                Button(language.text("Later", "稍后")) {
                    controller.dismiss()
                }
                Button(language.text("Download and Upgrade", "下载并升级")) {
                    controller.startUpgrade()
                }
                .keyboardShortcut(.defaultAction)
            case let .readyToInstall(release, _):
                Button(language.text("View Release", "查看发布页")) {
                    controller.openReleasePage(release)
                }
                Spacer()
                Button(language.text("Later", "稍后")) {
                    controller.dismiss()
                }
                Button(language.text("Install and Relaunch", "安装并重新启动")) {
                    controller.installAndRelaunch()
                }
                .keyboardShortcut(.defaultAction)
            case .checking, .downloading, .preparing:
                Spacer()
                Button(language.text("Cancel", "取消")) {
                    controller.cancelWork()
                }
            case .installing:
                Spacer()
            case .failure:
                Button(language.text("Check Again", "重新检查")) {
                    controller.checkForUpdates()
                }
                Spacer()
                Button(language.text("Close", "关闭")) {
                    controller.dismiss()
                }
            default:
                Spacer()
                Button(language.text("Done", "完成")) {
                    controller.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
