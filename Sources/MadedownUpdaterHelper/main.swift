import AppKit
import Darwin
import Foundation

private let expectedBundleIdentifier = "io.github.zhxnix.Madedown"

private enum HelperError: LocalizedError {
    case invalidArguments(String)
    case unsafePath(String)
    case invalidBundle(String)
    case commandFailed(String)
    case parentDidNotExit
    case replacementFailed(String)
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            return "更新助手参数无效：\(message)"
        case let .unsafePath(path):
            return "更新助手拒绝了不安全的路径：\(path)"
        case let .invalidBundle(message):
            return "更新包校验失败：\(message)"
        case let .commandFailed(message):
            return "系统命令执行失败：\(message)"
        case .parentDidNotExit:
            return "旧版本未能在限定时间内退出。"
        case let .replacementFailed(message):
            return "无法原位替换应用：\(message)"
        case .relaunchFailed:
            return "新版本未能正常启动，已恢复旧版本。"
        }
    }
}

private struct InstallOptions {
    let stagedAppURL: URL
    let targetAppURL: URL
    let workspaceURL: URL
    let expectedVersion: String
    let parentPID: pid_t

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw HelperError.invalidArguments(key)
            }
            values[key] = arguments[index + 1]
            index += 2
        }

        guard let stagedPath = values["--staged-app"],
              let targetPath = values["--target-app"],
              let workspacePath = values["--workspace"],
              let expectedVersion = values["--expected-version"],
              let rawPID = values["--parent-pid"],
              let parentPID = pid_t(rawPID) else {
            throw HelperError.invalidArguments("缺少必需参数")
        }

        stagedAppURL = URL(fileURLWithPath: stagedPath).standardizedFileURL
        targetAppURL = URL(fileURLWithPath: targetPath).standardizedFileURL
        workspaceURL = URL(fileURLWithPath: workspacePath).standardizedFileURL
        self.expectedVersion = expectedVersion
        self.parentPID = parentPID
        try Self.validatePaths(stagedAppURL: stagedAppURL, targetAppURL: targetAppURL, workspaceURL: workspaceURL)
    }

    private static func validatePaths(stagedAppURL: URL, targetAppURL: URL, workspaceURL: URL) throws {
        guard stagedAppURL.pathExtension.lowercased() == "app",
              targetAppURL.pathExtension.lowercased() == "app" else {
            throw HelperError.unsafePath("应用路径必须以 .app 结尾")
        }
        guard targetAppURL.pathComponents.count >= 3,
              targetAppURL.deletingLastPathComponent().path != "/" else {
            throw HelperError.unsafePath(targetAppURL.path)
        }
        let workspacePrefix = workspaceURL.path.hasSuffix("/") ? workspaceURL.path : workspaceURL.path + "/"
        guard stagedAppURL.path.hasPrefix(workspacePrefix) else {
            throw HelperError.unsafePath("暂存应用不在更新工作目录中")
        }
    }
}

private enum ProcessRunner {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(status: process.terminationStatus, output: output)
    }

    static func requireSuccess(_ executable: String, _ arguments: [String]) throws {
        let result = try run(executable, arguments)
        guard result.status == 0 else {
            throw HelperError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

private enum BundleValidator {
    static func validate(_ appURL: URL, expectedVersion: String, requireExpectedVersion: Bool = true) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HelperError.invalidBundle("找不到 \(appURL.lastPathComponent)")
        }

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String,
              let executableName = info["CFBundleExecutable"] as? String else {
            throw HelperError.invalidBundle("Bundle ID、版本号或可执行文件字段不正确")
        }

        if requireExpectedVersion, normalizedVersion(version) != normalizedVersion(expectedVersion) {
            throw HelperError.invalidBundle("安装包版本 \(version) 与 GitHub Release \(expectedVersion) 不一致")
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw HelperError.invalidBundle("主程序不存在或不可执行")
        }

        try ProcessRunner.requireSuccess("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
    }

    private static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.first == "v" || trimmed.first == "V" ? trimmed.dropFirst() : Substring(trimmed)).lowercased()
    }
}

private final class ReplacementInstaller {
    private let options: InstallOptions
    private let fileManager = FileManager.default
    private let incomingURL: URL
    private let backupURL: URL
    private var usedPrivileges = false

    init(options: InstallOptions) {
        self.options = options
        let parent = options.targetAppURL.deletingLastPathComponent()
        let token = UUID().uuidString
        incomingURL = parent.appendingPathComponent(".Madedown-update-\(token).app")
        backupURL = parent.appendingPathComponent(".Madedown-backup-\(token).app")
    }

    func run() throws {
        try waitForParentToExit()

        do {
            try BundleValidator.validate(options.stagedAppURL, expectedVersion: options.expectedVersion)
            try BundleValidator.validate(
                options.targetAppURL,
                expectedVersion: options.expectedVersion,
                requireExpectedVersion: false
            )
            if fileManager.isWritableFile(atPath: options.targetAppURL.deletingLastPathComponent().path) {
                try replaceDirectly()
            } else {
                usedPrivileges = true
                try replaceWithPrivileges()
            }
            try BundleValidator.validate(options.targetAppURL, expectedVersion: options.expectedVersion)
        } catch {
            try? rollback()
            _ = try? openApplication(options.targetAppURL)
            throw error
        }

        guard let runningApplication = relaunchAndWait() else {
            try? rollback()
            _ = try? openApplication(options.targetAppURL)
            throw HelperError.relaunchFailed
        }

        usleep(1_000_000)
        guard !runningApplication.isTerminated else {
            try? rollback()
            _ = try? openApplication(options.targetAppURL)
            throw HelperError.relaunchFailed
        }

        try removeBackup()
        try? fileManager.removeItem(at: options.workspaceURL)
    }

    func runReplacementSelfTest() throws {
        try BundleValidator.validate(options.stagedAppURL, expectedVersion: options.expectedVersion)
        try BundleValidator.validate(
            options.targetAppURL,
            expectedVersion: options.expectedVersion,
            requireExpectedVersion: false
        )
        try replaceDirectly()
        try BundleValidator.validate(options.targetAppURL, expectedVersion: options.expectedVersion)
        try removeBackup()
    }

    func runRollbackSelfTest(originalVersion: String) throws {
        try replaceDirectly()
        try rollback()
        try BundleValidator.validate(options.targetAppURL, expectedVersion: originalVersion)
    }

    private func waitForParentToExit() throws {
        guard options.parentPID > 1 else { return }
        for _ in 0..<300 {
            if Darwin.kill(options.parentPID, 0) != 0, errno == ESRCH {
                return
            }
            usleep(100_000)
        }
        throw HelperError.parentDidNotExit
    }

    private func replaceDirectly() throws {
        try removeIfPresent(incomingURL)
        try removeIfPresent(backupURL)
        try fileManager.copyItem(at: options.stagedAppURL, to: incomingURL)
        try BundleValidator.validate(incomingURL, expectedVersion: options.expectedVersion)

        do {
            try fileManager.moveItem(at: options.targetAppURL, to: backupURL)
            try fileManager.moveItem(at: incomingURL, to: options.targetAppURL)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path),
               !fileManager.fileExists(atPath: options.targetAppURL.path) {
                try? fileManager.moveItem(at: backupURL, to: options.targetAppURL)
            }
            throw HelperError.replacementFailed(error.localizedDescription)
        }
    }

    private func replaceWithPrivileges() throws {
        let script = """
        on run argv
            set stagedPath to item 1 of argv
            set incomingPath to item 2 of argv
            set targetPath to item 3 of argv
            set backupPath to item 4 of argv
            set commandText to "set -e; /bin/rm -rf " & quoted form of incomingPath & " " & quoted form of backupPath & "; /usr/bin/ditto " & quoted form of stagedPath & " " & quoted form of incomingPath & "; /usr/bin/codesign --verify --deep --strict " & quoted form of incomingPath & "; /bin/mv " & quoted form of targetPath & " " & quoted form of backupPath & "; /bin/mv " & quoted form of incomingPath & " " & quoted form of targetPath
            do shell script commandText with administrator privileges
        end run
        """
        try runAppleScript(script, arguments: [
            options.stagedAppURL.path,
            incomingURL.path,
            options.targetAppURL.path,
            backupURL.path
        ])
    }

    private func rollback() throws {
        if usedPrivileges {
            let script = """
            on run argv
                set incomingPath to item 1 of argv
                set targetPath to item 2 of argv
                set backupPath to item 3 of argv
                set commandText to "set -e; /bin/rm -rf " & quoted form of incomingPath & "; if [ -e " & quoted form of backupPath & " ]; then /bin/rm -rf " & quoted form of targetPath & "; /bin/mv " & quoted form of backupPath & " " & quoted form of targetPath & "; fi"
                do shell script commandText with administrator privileges
            end run
            """
            try runAppleScript(script, arguments: [incomingURL.path, options.targetAppURL.path, backupURL.path])
        } else {
            try removeIfPresent(incomingURL)
            if fileManager.fileExists(atPath: backupURL.path) {
                try removeIfPresent(options.targetAppURL)
                try fileManager.moveItem(at: backupURL, to: options.targetAppURL)
            }
        }
    }

    private func removeBackup() throws {
        if usedPrivileges {
            let script = """
            on run argv
                do shell script "/bin/rm -rf " & quoted form of (item 1 of argv) with administrator privileges
            end run
            """
            try runAppleScript(script, arguments: [backupURL.path])
        } else {
            try removeIfPresent(backupURL)
        }
    }

    private func runAppleScript(_ script: String, arguments: [String]) throws {
        let result = try ProcessRunner.run("/usr/bin/osascript", ["-e", script, "--"] + arguments)
        guard result.status == 0 else {
            throw HelperError.replacementFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func relaunchAndWait() -> NSRunningApplication? {
        guard (try? openApplication(options.targetAppURL)) != nil else { return nil }
        let standardizedTarget = options.targetAppURL.standardizedFileURL
        for _ in 0..<100 {
            if let application = NSRunningApplication
                .runningApplications(withBundleIdentifier: expectedBundleIdentifier)
                .first(where: { $0.bundleURL?.standardizedFileURL == standardizedTarget && !$0.isTerminated }) {
                return application
            }
            usleep(100_000)
        }
        return nil
    }

    @discardableResult
    private func openApplication(_ appURL: URL) throws -> ProcessRunner.Result {
        let result = try ProcessRunner.run("/usr/bin/open", ["-n", appURL.path])
        guard result.status == 0 else {
            throw HelperError.commandFailed(result.output)
        }
        return result
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

private enum HelperSelfTest {
    static func run() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("MadedownUpdater-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let target = root.appendingPathComponent("Madedown.app", isDirectory: true)
        let staged = workspace.appendingPathComponent("Madedown.app", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try createTestBundle(at: target, version: "1.0.0")
        try createTestBundle(at: staged, version: "2.0.0")
        try BundleValidator.validate(staged, expectedVersion: "v2.0.0")

        let malformed = workspace.appendingPathComponent("Broken.app")
        try fileManager.createDirectory(at: malformed, withIntermediateDirectories: true)
        var rejectedMalformedBundle = false
        do {
            try BundleValidator.validate(malformed, expectedVersion: "2.0.0")
        } catch {
            rejectedMalformedBundle = true
        }
        precondition(rejectedMalformedBundle, "A malformed application bundle must be rejected")

        let options = try InstallOptions(arguments: [
            "--staged-app", staged.path,
            "--target-app", target.path,
            "--workspace", workspace.path,
            "--expected-version", "2.0.0",
            "--parent-pid", "0"
        ])
        precondition(options.targetAppURL == target.standardizedFileURL)
        try ReplacementInstaller(options: options).runReplacementSelfTest()
        try BundleValidator.validate(target, expectedVersion: "2.0.0")
        try fileManager.removeItem(at: target)
        try createTestBundle(at: target, version: "1.0.0")
        try ReplacementInstaller(options: options).runRollbackSelfTest(originalVersion: "1.0.0")
    }

    private static func createTestBundle(at url: URL, version: String) throws {
        let fileManager = FileManager.default
        let macOSDirectory = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fileManager.createDirectory(at: macOSDirectory, withIntermediateDirectories: true)
        let executableURL = macOSDirectory.appendingPathComponent("Madedown")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        let info: [String: Any] = [
            "CFBundleIdentifier": expectedBundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
            "CFBundleExecutable": "Madedown",
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try ProcessRunner.requireSuccess("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", url.path])
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try HelperSelfTest.run()
        print("Madedown updater helper self-test passed")
    } else {
        let options = try InstallOptions(arguments: arguments)
        try ReplacementInstaller(options: options).run()
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
