import AppKit
import Foundation
import Markdown
import SwiftUI
import UniformTypeIdentifiers

@main
struct MadedownApp: App {
    @StateObject private var store: MarkdownStore

    init() {
        if CommandLine.arguments.contains("--self-test") {
            MarkdownSelfTest.run()
            Foundation.exit(0)
        }
        if CommandLine.arguments.contains("--startup-probe") {
            let probeStore = MarkdownStore()
            _ = probeStore.markdown
            print("Madedown startup_probe=ready")
            Foundation.exit(0)
        }
        _store = StateObject(wrappedValue: MarkdownStore(opening: Self.launchDocumentURL()))
    }

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 520)
                .onOpenURL { url in
                    store.openDocument(at: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flushSession()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建") {
                    store.newDocument()
                }
                .keyboardShortcut("n")
            }

            CommandGroup(after: .newItem) {
                Button("打开...") {
                    store.openDocument()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .printItem) {
                Button("快速打开最近文件…") {
                    store.presentQuickOpen()
                }
                .keyboardShortcut("p")
            }

            CommandGroup(replacing: .saveItem) {
                Button("保存") {
                    store.saveDocument()
                }
                .keyboardShortcut("s")

                Button("另存为...") {
                    store.saveDocumentAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("导出 HTML…") {
                    store.exportHTML()
                }

                Button("导出 PDF…") {
                    store.exportPDF()
                }
            }

            CommandGroup(after: .pasteboard) {
                Button("插入图片…") {
                    store.insertImage()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("查找与替换…") {
                    MarkdownEditorCommandCenter.shared.performFindAction(.showFindInterface)
                }
                .keyboardShortcut("f")

                Button("查找下一个") {
                    MarkdownEditorCommandCenter.shared.performFindAction(.nextMatch)
                }
                .keyboardShortcut("g")

                Button("查找上一个") {
                    MarkdownEditorCommandCenter.shared.performFindAction(.previousMatch)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("关于 Madedown") {
                    MadedownApplicationController.showAboutPanel()
                }

                Divider()

                Button("检查更新…") {
                    MadedownApplicationController.checkForUpdates()
                }
            }
        }
    }

    private static func launchDocumentURL() -> URL? {
        CommandLine.arguments.dropFirst().compactMap { argument -> URL? in
            guard !argument.hasPrefix("-") else { return nil }
            let url = URL(fileURLWithPath: argument)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return nil
            }
            return url
        }.first
    }
}

enum EditorMode: String, CaseIterable, Identifiable, Codable {
    case rendered
    case source

    var id: String { rawValue }
}

struct MarkdownDocumentTab: Identifiable, Codable, Equatable {
    var id: UUID
    var markdown: String
    var mode: EditorMode
    var filePath: String?
    var untitledName: String
    var customTitle: String?
    var isDirty: Bool
    var renderedCaretLocation: Int?
    var renderedScrollOffset: Double?
    var sourceCaretLocation: Int?
    var sourceScrollOffset: Double?

    init(
        id: UUID = UUID(),
        markdown: String = "",
        mode: EditorMode = .rendered,
        fileURL: URL? = nil,
        untitledName: String = "未命名",
        isDirty: Bool = false
    ) {
        self.id = id
        self.markdown = markdown
        self.mode = mode
        self.filePath = fileURL?.path
        self.untitledName = untitledName
        self.customTitle = nil
        self.isDirty = isDirty
        self.renderedCaretLocation = nil
        self.renderedScrollOffset = nil
        self.sourceCaretLocation = nil
        self.sourceScrollOffset = nil
    }

    var fileURL: URL? {
        filePath.map { URL(fileURLWithPath: $0) }
    }

    var displayTitle: String {
        customTitle ?? fileURL?.lastPathComponent ?? untitledName
    }

    var suggestedSaveFilename: String {
        let title = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = title.isEmpty ? "未命名" : title
        return (fallback as NSString).pathExtension.isEmpty ? "\(fallback).md" : fallback
    }
}

struct EditorViewport: Equatable {
    var caretLocation: Int
    var scrollOffset: Double
}

@MainActor
final class MarkdownStore: ObservableObject {
    @Published private(set) var tabs: [MarkdownDocumentTab]
    @Published var activeTabID: UUID {
        didSet { persistSession() }
    }
    @Published var isAlwaysOnTop: Bool {
        didSet { persistSession() }
    }
    @Published var isFullWidth: Bool {
        didSet { persistSession() }
    }
    @Published var isQuickOpenPresented = false
    @Published private(set) var recentDocumentURLs: [URL] = []

    private struct Session: Codable {
        var version = 1
        var tabs: [MarkdownDocumentTab]
        var activeTabID: UUID
        var isAlwaysOnTop: Bool
        var isFullWidth: Bool?
    }

    private let markdownTypes: [UTType] = [
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        .plainText
    ]
    private var sessionPersistenceTask: Task<Void, Never>?

    init(opening initialURL: URL? = nil) {
        if let session = Self.loadSession(), !session.tabs.isEmpty {
            tabs = session.tabs
            activeTabID = session.tabs.contains(where: { $0.id == session.activeTabID })
                ? session.activeTabID
                : session.tabs[0].id
            isAlwaysOnTop = session.isAlwaysOnTop
            isFullWidth = session.isFullWidth ?? true
        } else {
            let tab = MarkdownDocumentTab()
            tabs = [tab]
            activeTabID = tab.id
            isAlwaysOnTop = false
            isFullWidth = true
        }

        if let initialURL {
            openDocument(at: initialURL)
        }
        refreshRecentDocuments()
    }

    var markdown: String {
        get { activeTab?.markdown ?? "" }
        set {
            updateActiveTab { tab in
                guard tab.markdown != newValue else { return }
                tab.markdown = newValue
                tab.isDirty = true
            }
        }
    }

    var mode: EditorMode {
        get { activeTab?.mode ?? .rendered }
        set {
            updateActiveTab { $0.mode = newValue }
        }
    }

    var fileURL: URL? {
        activeTab?.fileURL
    }

    var status: String {
        activeTab?.displayTitle ?? "未命名"
    }

    var activeTab: MarkdownDocumentTab? {
        tabs.first { $0.id == activeTabID }
    }

    func newDocument() {
        let tab = MarkdownDocumentTab(untitledName: nextUntitledName())
        tabs.append(tab)
        activeTabID = tab.id
        persistSession()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    func viewport(for mode: EditorMode) -> EditorViewport {
        guard let tab = activeTab else { return EditorViewport(caretLocation: 0, scrollOffset: 0) }
        switch mode {
        case .rendered:
            return EditorViewport(
                caretLocation: tab.renderedCaretLocation ?? 0,
                scrollOffset: tab.renderedScrollOffset ?? 0
            )
        case .source:
            return EditorViewport(
                caretLocation: tab.sourceCaretLocation ?? 0,
                scrollOffset: tab.sourceScrollOffset ?? 0
            )
        }
    }

    func updateViewport(tabID: UUID, mode: EditorMode, caretLocation: Int, scrollOffset: Double) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let normalizedCaret = max(0, caretLocation)
        let normalizedOffset = max(0, scrollOffset)
        let previousCaret: Int?
        let previousOffset: Double?

        switch mode {
        case .rendered:
            previousCaret = tabs[index].renderedCaretLocation
            previousOffset = tabs[index].renderedScrollOffset
            guard previousCaret != normalizedCaret || abs((previousOffset ?? 0) - normalizedOffset) > 8 else { return }
            tabs[index].renderedCaretLocation = normalizedCaret
            tabs[index].renderedScrollOffset = normalizedOffset
        case .source:
            previousCaret = tabs[index].sourceCaretLocation
            previousOffset = tabs[index].sourceScrollOffset
            guard previousCaret != normalizedCaret || abs((previousOffset ?? 0) - normalizedOffset) > 8 else { return }
            tabs[index].sourceCaretLocation = normalizedCaret
            tabs[index].sourceScrollOffset = normalizedOffset
        }
        persistSession()
    }

    func requestCloseTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let hasUnsavedContent = tab.isDirty || (tab.fileURL == nil && !tab.markdown.isEmpty)
        guard hasUnsavedContent else {
            closeTabImmediately(id)
            return
        }

        activeTabID = id
        let alert = NSAlert()
        alert.messageText = "关闭标签页？"
        alert.informativeText = "关闭以后，尚未保存的内容将会遗失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "直接关闭")
        alert.addButton(withTitle: "保存")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            closeTabImmediately(id)
        case .alertSecondButtonReturn:
            if saveActiveDocument() {
                closeTabImmediately(id)
            }
        default:
            break
        }
    }

    func renameTab(_ id: UUID, to proposedTitle: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tabs[index].customTitle = title
        persistSession()
    }

    private func closeTabImmediately(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: index)
        try? FileManager.default.removeItem(at: Self.stagedAssetsDirectory(for: id))

        if tabs.isEmpty {
            let tab = MarkdownDocumentTab()
            tabs = [tab]
            activeTabID = tab.id
        } else if wasActive {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }
        persistSession()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = markdownTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(at: url)
    }

    func openDocument(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        if let existing = tabs.first(where: { $0.fileURL?.standardizedFileURL == standardizedURL }) {
            activeTabID = existing.id
            noteRecentDocument(standardizedURL)
            return
        }

        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let markdown = try String(contentsOf: url, encoding: .utf8)
            let tab = MarkdownDocumentTab(
                markdown: markdown,
                mode: .rendered,
                fileURL: standardizedURL,
                isDirty: false
            )
            tabs.append(tab)
            activeTabID = tab.id
            noteRecentDocument(standardizedURL)
            persistSession()
        } catch {
            showAlert(title: "无法打开文件", message: error.localizedDescription)
        }
    }

    func saveDocument() {
        _ = saveActiveDocument()
    }

    func saveDocumentAs() {
        _ = saveActiveDocumentAs()
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(exportBaseName).html"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try MarkdownExporter.writeHTML(markdown: markdown, baseURL: fileURL, to: url)
        } catch {
            showAlert(title: "无法导出 HTML", message: error.localizedDescription)
        }
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(exportBaseName).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try MarkdownExporter.writePDF(markdown: markdown, baseURL: fileURL, to: url)
        } catch {
            showAlert(title: "无法导出 PDF", message: error.localizedDescription)
        }
    }

    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = fileURL == nil
            ? "选择一张图片。无需先保存文档，首次保存时会自动整理到附件目录。"
            : "选择一张图片。Madedown 会将副本保存到 Markdown 文件旁的附件目录。"

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        _ = insertImageFiles([selectedURL])
    }

    func insertImageFiles(_ urls: [URL]) -> Bool {
        let imageURLs = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        guard !imageURLs.isEmpty else { return false }

        do {
            for imageURL in imageURLs {
                let insertion = try imageInsertion(for: imageURL)
                MarkdownEditorCommandCenter.shared.insertImage(insertion, baseURL: fileURL)
            }
            return true
        } catch {
            showAlert(title: "无法插入图片", message: error.localizedDescription)
            return true
        }
    }

    func insertImages(from pasteboard: NSPasteboard) -> Bool {
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if insertImageFiles(fileURLs) {
            return true
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("madedown-pasted-\(UUID().uuidString).png")
        do {
            try pngData.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            return insertImageFiles([temporaryURL])
        } catch {
            showAlert(title: "无法粘贴图片", message: error.localizedDescription)
            return true
        }
    }

    func presentQuickOpen() {
        refreshRecentDocuments()
        isQuickOpenPresented = true
    }

    func dismissQuickOpen() {
        isQuickOpenPresented = false
    }

    func openRecentDocument(_ url: URL) {
        isQuickOpenPresented = false
        openDocument(at: url)
    }

    private func saveActiveDocument() -> Bool {
        guard let activeTab else { return false }
        guard let fileURL = activeTab.fileURL else {
            return saveActiveDocumentAs()
        }

        if activeTab.customTitle != nil,
           activeTab.suggestedSaveFilename.caseInsensitiveCompare(fileURL.lastPathComponent) != .orderedSame {
            return saveActiveDocumentAs()
        }
        return write(to: fileURL)
    }

    private func saveActiveDocumentAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = markdownTypes
        panel.nameFieldStringValue = activeTab?.suggestedSaveFilename ?? "未命名.md"

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url)
    }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
    }

    func toggleFullWidth() {
        isFullWidth.toggle()
    }

    private func write(to url: URL) -> Bool {
        guard let index = activeTabIndex else { return false }
        let tabID = tabs[index].id
        do {
            let preparedMarkdown = try Self.materializeStagedImages(
                in: tabs[index].markdown,
                tabID: tabID,
                documentURL: url
            )
            try preparedMarkdown.write(to: url, atomically: true, encoding: .utf8)
            guard let savedIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
            tabs[savedIndex].markdown = preparedMarkdown
            tabs[savedIndex].filePath = url.standardizedFileURL.path
            tabs[savedIndex].isDirty = false
            try? FileManager.default.removeItem(at: Self.stagedAssetsDirectory(for: tabID))
            noteRecentDocument(url.standardizedFileURL)
            persistSession()
            return true
        } catch {
            showAlert(title: "无法保存文件", message: error.localizedDescription)
            return false
        }
    }

    private var activeTabIndex: Int? {
        tabs.firstIndex { $0.id == activeTabID }
    }

    private func updateActiveTab(_ update: (inout MarkdownDocumentTab) -> Void) {
        guard let index = activeTabIndex else { return }
        let previous = tabs[index]
        update(&tabs[index])
        if tabs[index] != previous {
            persistSession()
        }
    }

    private func nextUntitledName() -> String {
        let existing = Set(tabs.filter { $0.filePath == nil }.map(\.untitledName))
        if !existing.contains("未命名") {
            return "未命名"
        }

        var number = 2
        while existing.contains("未命名 \(number)") {
            number += 1
        }
        return "未命名 \(number)"
    }

    private func imageInsertion(for sourceURL: URL) throws -> ImageInsertion {
        if let documentURL = fileURL {
            return try Self.copyImageToAssetFolder(sourceURL, documentURL: documentURL)
        }
        return try Self.stageImage(sourceURL, tabID: activeTabID)
    }

    private var exportBaseName: String {
        let filename = activeTab?.suggestedSaveFilename ?? "未命名.md"
        let base = (filename as NSString).deletingPathExtension
        return base.isEmpty ? "未命名" : base
    }

    private func noteRecentDocument(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentDocuments()
    }

    private func refreshRecentDocuments() {
        recentDocumentURLs = NSDocumentController.shared.recentDocumentURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    func flushSession() {
        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = nil
        writeSession(makeSessionSnapshot())
    }

    private func persistSession() {
        let session = makeSessionSnapshot()
        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writeSession(session)
            self.sessionPersistenceTask = nil
        }
    }

    private func makeSessionSnapshot() -> Session {
        Session(
            tabs: tabs,
            activeTabID: activeTabID,
            isAlwaysOnTop: isAlwaysOnTop,
            isFullWidth: isFullWidth
        )
    }

    private func writeSession(_ session: Session) {
        do {
            let directory = Self.sessionURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(session)
            try data.write(to: Self.sessionURL, options: .atomic)
        } catch {
            NSLog("Madedown: unable to persist session: %@", error.localizedDescription)
        }
    }

    private static func copyImageToAssetFolder(_ sourceURL: URL, documentURL: URL) throws -> ImageInsertion {
        let documentName = documentURL.deletingPathExtension().lastPathComponent
        let assetsDirectory = documentURL.deletingLastPathComponent()
            .appendingPathComponent("\(documentName).assets", isDirectory: true)
        let destination = try copyImage(sourceURL, to: assetsDirectory)
        let relativePath = "\(assetsDirectory.lastPathComponent)/\(destination.lastPathComponent)"
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
        return ImageInsertion(altText: imageBaseName(for: sourceURL), source: encodedPath)
    }

    fileprivate static func stageImage(_ sourceURL: URL, tabID: UUID) throws -> ImageInsertion {
        let destination = try copyImage(sourceURL, to: Self.stagedAssetsDirectory(for: tabID))
        return ImageInsertion(
            altText: imageBaseName(for: sourceURL),
            source: destination.absoluteURL.absoluteString
        )
    }

    fileprivate static func materializeStagedImages(
        in markdown: String,
        tabID: UUID,
        documentURL: URL
    ) throws -> String {
        let manager = FileManager.default
        let stagingDirectory = Self.stagedAssetsDirectory(for: tabID)
        guard manager.fileExists(atPath: stagingDirectory.path) else { return markdown }

        let documentName = documentURL.deletingPathExtension().lastPathComponent
        let assetsDirectory = documentURL.deletingLastPathComponent()
            .appendingPathComponent("\(documentName).assets", isDirectory: true)
        let stagedFiles = try manager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var result = markdown
        for stagedFile in stagedFiles {
            let stagedSource = stagedFile.absoluteURL.absoluteString
            guard result.contains(stagedSource) else { continue }
            let destination = try copyImage(stagedFile, to: assetsDirectory)
            let relativePath = "\(assetsDirectory.lastPathComponent)/\(destination.lastPathComponent)"
            let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
            result = result.replacingOccurrences(of: stagedSource, with: encodedPath)
        }
        return result
    }

    private static func copyImage(_ sourceURL: URL, to directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = imageBaseName(for: sourceURL)
        let pathExtension = sourceURL.pathExtension.lowercased()

        var destination = directory.appendingPathComponent(
            pathExtension.isEmpty ? baseName : "\(baseName).\(pathExtension)"
        )
        var suffix = 2
        while manager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(
                pathExtension.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(pathExtension)"
            )
            suffix += 1
        }

        if sourceURL.standardizedFileURL != destination.standardizedFileURL {
            try manager.copyItem(at: sourceURL, to: destination)
        }
        return destination
    }

    private static func imageBaseName(for sourceURL: URL) -> String {
        let originalBaseName = sourceURL.deletingPathExtension().lastPathComponent
        let cleanedBaseName = originalBaseName
            .replacingOccurrences(of: #"[^\p{L}\p{N}._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return cleanedBaseName.isEmpty ? "image" : cleanedBaseName
    }

    private static func stagedAssetsDirectory(for tabID: UUID) -> URL {
        sessionURL.deletingLastPathComponent()
            .appendingPathComponent("StagedAssets", isDirectory: true)
            .appendingPathComponent(tabID.uuidString, isDirectory: true)
    }

    private static func loadSession() -> Session? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static var sessionURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["MADEDOWN_SESSION_PATH"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("MarkdownNotepad", isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
enum MarkdownExporter {
    static func writeHTML(markdown: String, baseURL: URL?, to destination: URL) throws {
        let body = embedLocalImages(in: HTMLFormatter.format(markdown), baseURL: baseURL)
        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedHTML(destination.deletingPathExtension().lastPathComponent))</title>
          <style>
            :root { color-scheme: light dark; }
            body { max-width: 860px; margin: 48px auto; padding: 0 24px; font: 16px/1.7 -apple-system, BlinkMacSystemFont, sans-serif; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin-top: 1.5em; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            pre { overflow-x: auto; padding: 14px; background: color-mix(in srgb, CanvasText 7%, Canvas); border-radius: 8px; }
            blockquote { margin-left: 0; padding-left: 16px; border-left: 3px solid #8888; color: color-mix(in srgb, CanvasText 72%, Canvas); }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #8886; padding: 7px 10px; text-align: left; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
        try Data(html.utf8).write(to: destination, options: .atomic)
    }

    static func writePDF(markdown: String, baseURL: URL?, to destination: URL) throws {
        let attributed = MarkdownRichText.attributedDocument(markdown: markdown, baseURL: baseURL)
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842)
        printInfo.leftMargin = 42
        printInfo.rightMargin = 42
        printInfo.topMargin = 46
        printInfo.bottomMargin = 46
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let contentWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 100))
        textView.appearance = NSAppearance(named: .aqua)
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textStorage?.setAttributedString(attributed)

        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(100, usedHeight))
        }

        let pdfData = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(
            with: textView,
            inside: textView.bounds,
            to: pdfData,
            printInfo: printInfo
        )
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try (pdfData as Data).write(to: destination, options: .atomic)
    }

    private static func embedLocalImages(in html: String, baseURL: URL?) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(<img\b[^>]*\bsrc=")([^"]+)(")"#) else {
            return html
        }
        let source = html as NSString
        var result = html
        let matches = expression.matches(
            in: html,
            range: NSRange(location: 0, length: source.length)
        )

        for match in matches.reversed() {
            let valueRange = match.range(at: 2)
            let imageSource = source.substring(with: valueRange)
            guard let imageURL = resolvedLocalURL(imageSource, baseURL: baseURL),
                  let data = try? Data(contentsOf: imageURL) else {
                continue
            }
            let mimeType = UTType(filenameExtension: imageURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
            guard let swiftRange = Range(valueRange, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: dataURL)
        }
        return result
    }

    private static func resolvedLocalURL(_ source: String, baseURL: URL?) -> URL? {
        let decoded = source.removingPercentEncoding ?? source
        if let url = URL(string: decoded), url.isFileURL {
            return url
        }
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded)
        }
        guard let baseURL else { return nil }
        return URL(
            fileURLWithPath: decoded,
            relativeTo: baseURL.deletingLastPathComponent()
        ).standardizedFileURL
    }

    private static func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct EditorView: View {
    @EnvironmentObject private var store: MarkdownStore
    @FocusState private var sourceFocused: Bool
    @State private var isOutlineCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
            TabBarView()

            ZStack {
                if store.mode == .rendered {
                    let viewport = store.viewport(for: .rendered)
                    RenderedMarkdownEditor(
                        text: $store.markdown,
                        tabID: store.activeTabID,
                        isFullWidth: store.isFullWidth,
                        documentURL: store.fileURL,
                        caretLocation: viewport.caretLocation,
                        scrollOffset: viewport.scrollOffset,
                        onRequestImage: store.insertImage,
                        onPasteImages: store.insertImages,
                        onDropImageFiles: store.insertImageFiles,
                        onViewportChange: store.updateViewport
                    )
                } else {
                    let viewport = store.viewport(for: .source)
                    SourceEditor(
                        text: $store.markdown,
                        tabID: store.activeTabID,
                        isFullWidth: store.isFullWidth,
                        caretLocation: viewport.caretLocation,
                        scrollOffset: viewport.scrollOffset,
                        onRequestImage: store.insertImage,
                        onPasteImages: store.insertImages,
                        onDropImageFiles: store.insertImageFiles,
                        onViewportChange: store.updateViewport
                    )
                        .focused($sourceFocused)
                }

                FloatingOutlineView(
                    markdown: store.markdown,
                    isCollapsed: $isOutlineCollapsed
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            EditorStatusBar(markdown: store.markdown)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .background(
            WindowConfigurationView(
                title: "Madedown",
                isAlwaysOnTop: store.isAlwaysOnTop
            )
        )
        .onChange(of: store.mode) { newMode in
            sourceFocused = newMode == .source
        }
        .sheet(isPresented: $store.isQuickOpenPresented) {
            QuickOpenView()
                .environmentObject(store)
        }
    }
}

struct QuickOpenView: View {
    @EnvironmentObject private var store: MarkdownStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filteredURLs: [URL] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.recentDocumentURLs }
        return store.recentDocumentURLs.filter {
            $0.lastPathComponent.localizedCaseInsensitiveContains(trimmed) ||
                $0.deletingLastPathComponent().path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索最近打开的 Markdown 文件", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                Button {
                    store.dismissQuickOpen()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MinimalIconButtonStyle(size: 24))
            }
            .padding(.horizontal, 12)
            .frame(height: 42)

            Divider()

            if filteredURLs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "还没有最近文件" : "没有匹配的最近文件")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredURLs, id: \.path) { url in
                            Button {
                                store.openRecentDocument(url)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Text(url.deletingLastPathComponent().path)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }

            Divider()

            HStack {
                Text("⌘P")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("浏览其他文件…") {
                    store.dismissQuickOpen()
                    DispatchQueue.main.async {
                        store.openDocument()
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
        }
        .frame(width: 520, height: 420)
        .onAppear { searchFocused = true }
        .onExitCommand { store.dismissQuickOpen() }
    }
}

struct FloatingOutlineView: View {
    let markdown: String
    @Binding var isCollapsed: Bool

    var body: some View {
        let outlineHeadings = isCollapsed ? [] : MarkdownOutlineParser.headings(in: markdown)
        VStack {
            HStack {
                if isCollapsed {
                    Button {
                        isCollapsed = false
                    } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .buttonStyle(MinimalIconButtonStyle(size: 28))
                    .help("展开标题目录")
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.indent")
                                .foregroundStyle(.secondary)
                            Text("标题目录")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 8)
                            Button {
                                isCollapsed = true
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(MinimalIconButtonStyle(size: 24))
                            .help("收起标题目录")
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)

                        Divider()

                        if outlineHeadings.isEmpty {
                            Text("暂无标题")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(outlineHeadings) { heading in
                                        Button {
                                            MarkdownEditorCommandCenter.shared.scrollToHeading(heading)
                                        } label: {
                                            HStack(spacing: 5) {
                                                Text("H\(heading.level)")
                                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(.tertiary)
                                                    .frame(width: 18)
                                                Text(heading.title)
                                                    .font(.system(size: 11.5))
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 7)
                                            .padding(.horizontal, 6)
                                            .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(4)
                            }
                            .frame(maxHeight: 260)
                        }
                    }
                    .frame(width: 232)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
                Spacer()
            }
            Spacer()
        }
        .padding(8)
    }
}

@MainActor
private enum WindowLayoutController {
    enum Side {
        case left
        case right
    }

    static func tile(_ side: Side) {
        guard let window = activeWindow(), let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let halfWidth = floor(visible.width / 2)
        let frame = NSRect(
            x: side == .left ? visible.minX : visible.maxX - halfWidth,
            y: visible.minY,
            width: halfWidth,
            height: visible.height
        )
        window.setFrame(frame, display: true, animate: true)
    }

    static func resizeToCompactSize() {
        guard let window = activeWindow() else { return }
        // macOS window frames use points. On a 2× Retina display this is
        // approximately 1800 × 1600 physical pixels.
        let targetSize = NSSize(width: 900, height: 800)
        let currentCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let targetFrame = NSRect(
            x: currentCenter.x - targetSize.width / 2,
            y: currentCenter.y - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        window.setFrame(targetFrame, display: true, animate: true)
    }

    static func toggleMaximize() {
        activeWindow()?.zoom(nil)
    }

    private static func activeWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
    }
}

@MainActor
private enum MadedownApplicationController {
    static func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Madedown",
            .applicationVersion: version,
            .credits: NSAttributedString(
                string: "一款由 AI 协助打造的轻量、免费、开源 Markdown 编辑器。",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ]

        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func checkForUpdates() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let alert = NSAlert()
        alert.messageText = "检查更新"
        alert.informativeText = "当前版本：\(version)\n\n最新版本和安装包发布在 Madedown 的 GitHub Releases 页面。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往 GitHub Releases")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://github.com/zhxnix/Madedown/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
private enum MadedownBrandAssets {
    static let titlebarWordmark = loadImage(
        resource: "MadedownWordmark",
        projectFallback: "Assets/Logo/madedown-titlebar-wordmark.png",
        maximumDisplaySize: NSSize(width: 232, height: 36)
    )

    private static func loadImage(
        resource: String,
        projectFallback: String,
        maximumDisplaySize: NSSize? = nil
    ) -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: resource, withExtension: "png") {
            if let maximumDisplaySize {
                return ImageThumbnailLoader.load(url: bundledURL, maximumDisplaySize: maximumDisplaySize)
            }
            if let image = NSImage(contentsOf: bundledURL) {
                return image
            }
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(projectFallback)
        if let maximumDisplaySize {
            return ImageThumbnailLoader.load(url: fallbackURL, maximumDisplaySize: maximumDisplaySize)
        }
        return NSImage(contentsOf: fallbackURL)
    }
}

struct WindowConfigurationView: NSViewRepresentable {
    let title: String
    let isAlwaysOnTop: Bool

    func makeNSView(context: Context) -> WindowConfigurationNSView {
        let view = WindowConfigurationNSView()
        view.title = title
        view.isAlwaysOnTop = isAlwaysOnTop
        return view
    }

    func updateNSView(_ nsView: WindowConfigurationNSView, context: Context) {
        nsView.title = title
        nsView.isAlwaysOnTop = isAlwaysOnTop
        nsView.applyConfiguration()
    }
}

@MainActor
final class PassthroughWindowTitleImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
final class WindowConfigurationNSView: NSView {
    var title = ""
    var isAlwaysOnTop = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    func applyConfiguration() {
        guard let window else { return }
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        installCenteredTitle(in: window)
        window.level = isAlwaysOnTop ? .floating : .normal
        if isAlwaysOnTop {
            window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        } else {
            window.collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
    }

    private func installCenteredTitle(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebar = closeButton.superview else {
            return
        }

        let identifier = NSUserInterfaceItemIdentifier("Madedown.CenteredWindowTitle")
        let imageView: PassthroughWindowTitleImageView
        if let existing = titlebar.subviews.first(where: { $0.identifier == identifier }) as? PassthroughWindowTitleImageView {
            imageView = existing
        } else {
            titlebar.subviews
                .filter { $0.identifier == identifier }
                .forEach { $0.removeFromSuperview() }

            imageView = PassthroughWindowTitleImageView()
            imageView.identifier = identifier
            imageView.imageAlignment = .alignCenter
            imageView.imageScaling = .scaleProportionallyDown
            imageView.setAccessibilityLabel("Madedown")
            imageView.translatesAutoresizingMaskIntoConstraints = false
            titlebar.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 116),
                imageView.heightAnchor.constraint(equalToConstant: 18)
            ])
        }
        imageView.image = MadedownBrandAssets.titlebarWordmark
    }
}

struct ToolbarView: View {
    @EnvironmentObject private var store: MarkdownStore

    var body: some View {
        HStack(spacing: 2) {
            Button("新建") {
                store.newDocument()
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .help("新建")

            Button("打开") {
                store.openDocument()
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .help("打开")

            Button("保存") {
                store.saveDocument()
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .help("保存")

            Button("复制") {
                store.copyMarkdown()
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .help("复制 Markdown")

            Button("图片") {
                store.insertImage()
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .help("插入图片（⇧⌘I）")

            Spacer(minLength: 0)

            Button {
                store.mode = store.mode == .rendered ? .source : .rendered
            } label: {
                Image(systemName: store.mode == .rendered ? "curlybraces" : "text.alignleft")
            }
            .buttonStyle(WindowIconButtonStyle(isActive: store.mode == .source))
            .help(store.mode == .rendered ? "切换到源码" : "返回渲染编辑")

            Button {
                store.toggleFullWidth()
            } label: {
                Image(systemName: "arrow.left.and.right")
            }
            .buttonStyle(WindowIconButtonStyle(isActive: store.isFullWidth))
            .help(store.isFullWidth ? "关闭全宽，使用舒适阅读宽度" : "开启全宽")

            Divider()
                .frame(height: 15)
                .padding(.horizontal, 4)

            Button {
                WindowLayoutController.resizeToCompactSize()
            } label: {
                Image(systemName: "rectangle.center.inset.filled")
            }
            .buttonStyle(WindowIconButtonStyle())
            .help("缩为小窗口（900 × 800）")

            Button {
                WindowLayoutController.tile(.left)
            } label: {
                Image(systemName: "rectangle.lefthalf.filled")
            }
            .buttonStyle(WindowIconButtonStyle())
            .help("铺满左半屏")

            Button {
                WindowLayoutController.tile(.right)
            } label: {
                Image(systemName: "rectangle.righthalf.filled")
            }
            .buttonStyle(WindowIconButtonStyle())
            .help("铺满右半屏")

            Button {
                WindowLayoutController.toggleMaximize()
            } label: {
                Image(systemName: "rectangle.inset.filled")
            }
            .buttonStyle(WindowIconButtonStyle())
            .help("最大化 / 恢复")

            Button {
                store.toggleAlwaysOnTop()
            } label: {
                Image(systemName: store.isAlwaysOnTop ? "pin.fill" : "pin")
            }
            .buttonStyle(WindowIconButtonStyle(isActive: store.isAlwaysOnTop))
            .help(store.isAlwaysOnTop ? "取消置顶" : "固定在最上层")
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.86))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.42))
                .frame(height: 0.5)
        }
    }
}

struct TabBarView: View {
    @EnvironmentObject private var store: MarkdownStore
    @State private var editingTabID: UUID?
    @State private var editingTitle = ""
    @FocusState private var titleEditorFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.tabs) { tab in
                    let isActive = tab.id == store.activeTabID
                    HStack(spacing: 6) {
                        if tab.isDirty {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                        }

                        if editingTabID == tab.id {
                            TextField("标签名称", text: $editingTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 120)
                                .focused($titleEditorFocused)
                                .onSubmit {
                                    commitTabRename()
                                }
                                .onExitCommand {
                                    cancelTabRename()
                                }
                        } else {
                            SwiftUI.Text(tab.displayTitle)
                                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 150)
                                .onTapGesture(count: 2) {
                                    beginTabRename(tab)
                                }
                        }

                        Button {
                            store.requestCloseTab(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(MinimalIconButtonStyle(size: 20))
                        .help("关闭标签页")
                    }
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .padding(.leading, 10)
                    .padding(.trailing, 3)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isActive
                                    ? Color.accentColor.opacity(0.12)
                                    : Color(nsColor: .controlBackgroundColor).opacity(0.42)
                            )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isActive
                                    ? Color.accentColor.opacity(0.28)
                                    : Color(nsColor: .separatorColor).opacity(0.22),
                                lineWidth: 0.75
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectTab(tab.id)
                    }
                }

                Button {
                    store.newDocument()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(TabAddButtonStyle())
                .help("新建标签页")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.78))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.4))
                .frame(height: 0.5)
        }
        .onChange(of: titleEditorFocused) { focused in
            if !focused, editingTabID != nil {
                commitTabRename()
            }
        }
    }

    private func beginTabRename(_ tab: MarkdownDocumentTab) {
        store.selectTab(tab.id)
        editingTabID = tab.id
        editingTitle = tab.displayTitle
        DispatchQueue.main.async {
            titleEditorFocused = true
        }
    }

    private func commitTabRename() {
        guard let editingTabID else { return }
        store.renameTab(editingTabID, to: editingTitle)
        self.editingTabID = nil
        titleEditorFocused = false
    }

    private func cancelTabRename() {
        editingTabID = nil
        titleEditorFocused = false
    }
}

struct ToolbarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

struct TabAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 27, height: 27)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.85 : 0.48))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
    }
}

struct EditorStatusBar: View {
    let markdown: String

    private var characterCount: Int {
        markdown.unicodeScalars.reduce(into: 0) { count, scalar in
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                count += 1
            }
        }
    }

    var body: some View {
        HStack {
            Spacer()
            SwiftUI.Text("\(characterCount) 字")
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.28))
                .frame(height: 0.5)
        }
    }
}

struct WindowIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.12)
                            : configuration.isPressed ? Color(nsColor: .controlBackgroundColor) : Color.clear
                    )
            )
            .contentShape(Rectangle())
    }
}

struct MinimalIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(isEnabled ? .secondary : .tertiary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed && isEnabled ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

@MainActor
final class TableCommandCenter: ObservableObject {
    static let shared = TableCommandCenter()

    @Published private(set) var isInTable = false
    private weak var activeTextView: NSTextView?

    func activate(_ textView: NSTextView) {
        activeTextView = textView
        updateContext(from: textView)
    }

    func updateContext(from textView: NSTextView) {
        activeTextView = textView
        isInTable = MarkdownRichText.isSelectionInTable(textView)
    }

    func insertRowBelow() {
        perform { MarkdownRichText.insertTableRowBelow(in: $0) }
    }

    func deleteRow() {
        perform { MarkdownRichText.deleteTableRow(in: $0) }
    }

    func insertColumnRight() {
        perform { MarkdownRichText.insertTableColumnRight(in: $0) }
    }

    func deleteColumn() {
        perform { MarkdownRichText.deleteTableColumn(in: $0) }
    }

    private func perform(_ action: (NSTextView) -> Void) {
        guard let activeTextView else { return }
        action(activeTextView)
        updateContext(from: activeTextView)
    }
}

@MainActor
final class TableEdgeControls: NSView {
    private let rowPlusButton = NSButton(title: "", target: nil, action: nil)
    private let columnPlusButton = NSButton(title: "", target: nil, action: nil)
    private let rowHandleButton = TableHandleButton(title: "行", target: nil, action: nil)
    private let columnHandleButton = TableHandleButton(title: "列", target: nil, action: nil)

    var onRowMenu: ((NSPoint) -> Void)?
    var onColumnMenu: ((NSPoint) -> Void)?

    override var isFlipped: Bool { true }

    init(target: AnyObject) {
        super.init(frame: .zero)

        autoresizingMask = [.width, .height]
        configurePlus(rowPlusButton, target: target, action: #selector(RenderedMarkdownEditor.Coordinator.insertRowAtHover))
        configurePlus(columnPlusButton, target: target, action: #selector(RenderedMarkdownEditor.Coordinator.insertColumnAtHover))
        configureHandle(rowHandleButton, target: target, action: #selector(RenderedMarkdownEditor.Coordinator.selectHoverRow))
        configureHandle(columnHandleButton, target: target, action: #selector(RenderedMarkdownEditor.Coordinator.selectHoverColumn))

        rowHandleButton.onRightMouseDown = { [weak self] event in
            guard let self else { return }
            self.onRowMenu?(self.convert(event.locationInWindow, from: nil))
        }
        columnHandleButton.onRightMouseDown = { [weak self] event in
            guard let self else { return }
            self.onColumnMenu?(self.convert(event.locationInWindow, from: nil))
        }

        [rowPlusButton, columnPlusButton, rowHandleButton, columnHandleButton].forEach {
            $0.isHidden = true
            addSubview($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for view in [rowPlusButton, columnPlusButton, rowHandleButton, columnHandleButton] where !view.isHidden && view.frame.contains(point) {
            return view
        }
        return nil
    }

    func update(with info: MarkdownRichText.TableHoverInfo?, in textView: NSTextView) {
        frame = textView.bounds
        autoresizingMask = [.width, .height]

        guard let info else {
            hide()
            return
        }

        position(rowPlusButton, frame: info.rowPlusFrame)
        position(columnPlusButton, frame: info.columnPlusFrame)
        position(rowHandleButton, frame: info.rowHandleFrame)
        position(columnHandleButton, frame: info.columnHandleFrame)
    }

    func hide() {
        rowPlusButton.isHidden = true
        columnPlusButton.isHidden = true
        rowHandleButton.isHidden = true
        columnHandleButton.isHidden = true
    }

    private func position(_ button: NSButton, frame: NSRect?) {
        guard let frame else {
            button.isHidden = true
            return
        }

        button.frame = frame.integral
        button.isHidden = false
    }

    private func configurePlus(_ button: NSButton, target: AnyObject, action: Selector) {
        button.target = target
        button.action = action
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.72).cgColor
    }

    private func configureHandle(_ button: NSButton, target: AnyObject, action: Selector) {
        button.target = target
        button.action = action
        button.bezelStyle = .rounded
        button.isBordered = false
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.contentTintColor = .controlAccentColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
    }
}

@MainActor
final class TableHandleButton: NSButton {
    var onRightMouseDown: ((NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?(event)
    }
}

@MainActor
final class SourceMarkdownTextView: SlashCommandTextView {
    private let maximumContentWidth: CGFloat = 980
    private let minimumHorizontalInset: CGFloat = 10
    var usesFullWidth = true {
        didSet {
            guard oldValue != usesFullWidth else { return }
            updateContentInsets(for: frame.size)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        updateContentInsets(for: newSize)
        if widthChanged {
            invalidateTextLayout()
        }
    }

    private func updateContentInsets(for size: NSSize) {
        let horizontalInset = usesFullWidth
            ? minimumHorizontalInset
            : max(minimumHorizontalInset, floor((size.width - maximumContentWidth) / 2))
        let desiredInset = NSSize(width: horizontalInset, height: 15)
        if textContainerInset != desiredInset {
            textContainerInset = desiredInset
            invalidateTextLayout()
        }
    }

    private func invalidateTextLayout() {
        guard let layoutManager, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        needsLayout = true
        needsDisplay = true
    }
}

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    var tabID: UUID
    var isFullWidth = true
    var caretLocation = 0
    var scrollOffset = 0.0
    var onRequestImage: () -> Void = {}
    var onPasteImages: (NSPasteboard) -> Bool = { _ in false }
    var onDropImageFiles: ([URL]) -> Bool = { _ in false }
    var onViewportChange: (UUID, EditorMode, Int, Double) -> Void = { _, _, _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true

        let textView = SourceMarkdownTextView()
        context.coordinator.textView = textView
        textView.usesFullWidth = isFullWidth
        textView.delegate = context.coordinator
        textView.onSlashCommand = { [weak coordinator = context.coordinator] command in
            coordinator?.applySlashCommand(command)
        }
        textView.onPasteImages = { [weak coordinator = context.coordinator] pasteboard in
            coordinator?.parent.onPasteImages(pasteboard) ?? false
        }
        textView.onDropImageFiles = { [weak coordinator = context.coordinator] urls in
            coordinator?.parent.onDropImageFiles(urls) ?? false
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 14.5, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 15)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 2
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        textView.string = text
        context.coordinator.lastText = text
        context.coordinator.lastTabID = tabID
        scrollView.documentView = textView
        context.coordinator.observeScrollView(scrollView)
        context.coordinator.restoreViewport(in: scrollView)
        MarkdownEditorCommandCenter.shared.activate(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SourceMarkdownTextView else {
            return
        }
        textView.usesFullWidth = isFullWidth
        MarkdownEditorCommandCenter.shared.activate(textView)
        let tabChanged = context.coordinator.lastTabID != tabID
        guard tabChanged || context.coordinator.lastText != text else {
            return
        }

        context.coordinator.isApplyingChange = true
        let selectionLocation = tabChanged ? caretLocation : textView.selectedRange().location
        textView.string = text
        textView.setSelectedRange(
            NSRange(location: min(selectionLocation, (text as NSString).length), length: 0)
        )
        context.coordinator.lastText = text
        context.coordinator.lastTabID = tabID
        context.coordinator.isApplyingChange = false
        if tabChanged {
            context.coordinator.restoreViewport(in: scrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        weak var textView: SourceMarkdownTextView?
        weak var scrollView: NSScrollView?
        var lastText = ""
        var lastTabID: UUID?
        var isApplyingChange = false

        init(_ parent: SourceEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observeScrollView(_ scrollView: NSScrollView) {
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func restoreViewport(in scrollView: NSScrollView) {
            guard let textView else { return }
            isApplyingChange = true
            textView.setSelectedRange(NSRange(
                location: min(parent.caretLocation, (textView.string as NSString).length),
                length: 0
            ))
            isApplyingChange = false
            let y = max(0, parent.scrollOffset)
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        @objc private func clipViewBoundsChanged() {
            reportViewport()
        }

        private func reportViewport() {
            guard !isApplyingChange, let textView, let scrollView else { return }
            parent.onViewportChange(
                parent.tabID,
                .source,
                textView.selectedRange().location,
                Double(scrollView.contentView.bounds.minY)
            )
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else { return true }

            if replacementString == "\n" || replacementString == "\r" || replacementString == "\r\n" {
                guard let prefix = sourceListContinuationPrefix(
                    in: textView.string,
                    at: affectedCharRange.location
                ) else {
                    return true
                }

                let replacement = "\n\(prefix)"
                textView.textStorage?.replaceCharacters(in: affectedCharRange, with: replacement)
                textView.setSelectedRange(
                    NSRange(location: affectedCharRange.location + (replacement as NSString).length, length: 0)
                )
                textView.didChangeText()
                return false
            }

            if replacementString.isEmpty,
               removeSourceListMarkerIfNeeded(
                   in: textView,
                   replacementRange: affectedCharRange
               ) {
                return false
            }

            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingChange,
                  let textView = notification.object as? NSTextView else {
                return
            }
            lastText = textView.string
            parent.text = textView.string
            reportViewport()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            reportViewport()
        }

        func applySlashCommand(_ command: SlashCommand) {
            guard let textView,
                  let triggerRange = textView.slashTriggerRange() else {
                return
            }

            let template = command.sourceTemplate
            textView.textStorage?.replaceCharacters(in: triggerRange, with: template.text)
            textView.setSelectedRange(
                NSRange(location: triggerRange.location + template.caretOffset, length: 0)
            )
            textView.didChangeText()

            if command.kind == .image {
                parent.onRequestImage()
            }
        }

        private func sourceListContinuationPrefix(in text: String, at location: Int) -> String? {
            let string = text as NSString
            guard location <= string.length else { return nil }
            let lookup = min(location, max(0, string.length - 1))
            let lineRange = string.length == 0
                ? NSRange(location: 0, length: 0)
                : string.lineRange(for: NSRange(location: lookup, length: 0))
            let line = string.substring(with: lineRange)
                .trimmingCharacters(in: .newlines)

            if let match = firstMatch(pattern: #"^(\s*)([-+*])\s+"#, in: line) {
                let indent = (line as NSString).substring(with: match.range(at: 1))
                let bullet = (line as NSString).substring(with: match.range(at: 2))
                return "\(indent)\(bullet) "
            }

            if let match = firstMatch(pattern: #"^(\s*)(\d+)([.)])\s+"#, in: line) {
                let source = line as NSString
                let indent = source.substring(with: match.range(at: 1))
                let number = Int(source.substring(with: match.range(at: 2))) ?? 1
                let delimiter = source.substring(with: match.range(at: 3))
                return "\(indent)\(number + 1)\(delimiter) "
            }

            return nil
        }

        private func removeSourceListMarkerIfNeeded(
            in textView: NSTextView,
            replacementRange: NSRange
        ) -> Bool {
            guard replacementRange.length == 1 else { return false }
            let string = textView.string as NSString
            let lookup = min(replacementRange.location, max(0, string.length - 1))
            guard string.length > 0 else { return false }
            let lineRange = string.lineRange(for: NSRange(location: lookup, length: 0))
            let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let match = firstMatch(pattern: #"^(\s*)(?:[-+*]|\d+[.)])\s+"#, in: line)
            guard let match else { return false }

            let markerRange = NSRange(
                location: lineRange.location + match.range.location,
                length: match.range.length
            )
            guard NSMaxRange(replacementRange) == NSMaxRange(markerRange) else { return false }

            textView.textStorage?.deleteCharacters(in: markerRange)
            textView.setSelectedRange(NSRange(location: markerRange.location, length: 0))
            textView.didChangeText()
            return true
        }

        private func firstMatch(pattern: String, in string: String) -> NSTextCheckingResult? {
            try? NSRegularExpression(pattern: pattern)
                .firstMatch(
                    in: string,
                    range: NSRange(location: 0, length: (string as NSString).length)
                )
        }
    }
}

@MainActor
final class MarkdownTextView: SlashCommandTextView {
    enum TableOverlayAction {
        case insertRow
        case insertColumn
        case selectRow
        case selectColumn
    }

    var onMouseMovedInTextView: ((NSPoint) -> Void)?
    var onMouseExitedTextView: (() -> Void)?
    var onRightMouseDownInTextView: ((NSEvent, NSPoint) -> Bool)?
    var onVisibleRectChanged: (() -> Void)?
    var onTableOverlayAction: ((TableOverlayAction, MarkdownRichText.TableHoverInfo) -> Void)?
    var tableEdgeOverlayInfo: MarkdownRichText.TableHoverInfo? {
        didSet {
            if oldValue?.tableFrame != tableEdgeOverlayInfo?.tableFrame ||
                oldValue?.rowIndex != tableEdgeOverlayInfo?.rowIndex ||
                oldValue?.columnIndex != tableEdgeOverlayInfo?.columnIndex {
                needsDisplay = true
            }
        }
    }

    private var mouseTrackingArea: NSTrackingArea?
    private let maximumContentWidth: CGFloat = 920
    private let minimumHorizontalInset: CGFloat = 10
    var usesFullWidth = true {
        didSet {
            guard oldValue != usesFullWidth else { return }
            updateContentInsets(for: frame.size)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        updateContentInsets(for: newSize)
        if widthChanged {
            invalidateTextLayout()
        }
    }

    private func updateContentInsets(for size: NSSize) {
        let horizontalInset = usesFullWidth
            ? minimumHorizontalInset
            : max(minimumHorizontalInset, floor((size.width - maximumContentWidth) / 2))
        let desiredInset = NSSize(width: horizontalInset, height: 15)
        if textContainerInset != desiredInset {
            textContainerInset = desiredInset
            invalidateTextLayout()
        }
    }

    private func invalidateTextLayout() {
        guard let layoutManager, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        needsLayout = true
        needsDisplay = true
    }

    override var bounds: NSRect {
        didSet {
            if oldValue.origin != bounds.origin || oldValue.size != bounds.size {
                onVisibleRectChanged?()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTableEdgeOverlay()
    }

    override func updateTrackingAreas() {
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        mouseTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMovedInTextView?(convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if performOverlayAction(at: point) {
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedTextView?()
        super.mouseExited(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onRightMouseDownInTextView?(event, point) == true {
            return
        }
        super.rightMouseDown(with: event)
    }

    private func performOverlayAction(at point: NSPoint) -> Bool {
        guard let info = tableEdgeOverlayInfo else { return false }

        if info.rowPlusFrame?.contains(point) == true {
            onTableOverlayAction?(.insertRow, info)
            return true
        }

        if info.columnPlusFrame?.contains(point) == true {
            onTableOverlayAction?(.insertColumn, info)
            return true
        }

        if info.rowHandleFrame?.contains(point) == true {
            onTableOverlayAction?(.selectRow, info)
            return true
        }

        if info.columnHandleFrame?.contains(point) == true {
            onTableOverlayAction?(.selectColumn, info)
            return true
        }

        return false
    }

    private func drawTableEdgeOverlay() {
        guard let info = tableEdgeOverlayInfo else { return }

        drawHandle(info.rowHandleFrame, orientation: .horizontal)
        drawHandle(info.columnHandleFrame, orientation: .vertical)
        drawPlus(info.rowPlusFrame)
        drawPlus(info.columnPlusFrame)
    }

    private enum HandleOrientation {
        case horizontal
        case vertical
    }

    private func drawHandle(_ frame: NSRect?, orientation: HandleOrientation) {
        guard let frame else { return }

        let background = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.34).setFill()
        background.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.86).setStroke()
        background.lineWidth = 1
        background.stroke()

        let label = orientation == .horizontal ? "行" : "列"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(
            at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawPlus(_ frame: NSRect?) {
        guard let frame else { return }

        let circle = NSBezierPath(ovalIn: frame)
        NSColor.controlAccentColor.withAlphaComponent(0.72).setFill()
        circle.fill()
    }
}

struct RenderedMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var tabID: UUID
    var isFullWidth = true
    var documentURL: URL? = nil
    var caretLocation = 0
    var scrollOffset = 0.0
    var onRequestImage: () -> Void = {}
    var onPasteImages: (NSPasteboard) -> Bool = { _ in false }
    var onDropImageFiles: ([URL]) -> Bool = { _ in false }
    var onViewportChange: (UUID, EditorMode, Int, Double) -> Void = { _, _, _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true

        let textView = MarkdownTextView()
        textView.usesFullWidth = isFullWidth
        textView.delegate = context.coordinator
        textView.onSlashCommand = { [weak coordinator = context.coordinator] command in
            coordinator?.applySlashCommand(command)
        }
        textView.onPasteImages = { [weak coordinator = context.coordinator] pasteboard in
            coordinator?.parent.onPasteImages(pasteboard) ?? false
        }
        textView.onDropImageFiles = { [weak coordinator = context.coordinator] urls in
            coordinator?.parent.onDropImageFiles(urls) ?? false
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = CGSize(width: 10, height: 15)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.textView = textView
        textView.onMouseMovedInTextView = { [weak coordinator = context.coordinator] point in
            coordinator?.mouseMoved(at: point)
        }
        textView.onMouseExitedTextView = { [weak coordinator = context.coordinator] in
            coordinator?.mouseExited()
        }
        textView.onRightMouseDownInTextView = { [weak coordinator = context.coordinator] event, point in
            coordinator?.rightMouseDown(event: event, at: point) ?? false
        }
        textView.onVisibleRectChanged = { [weak coordinator = context.coordinator] in
            coordinator?.updateEdgeControls()
        }
        textView.onTableOverlayAction = { [weak coordinator = context.coordinator] action, info in
            coordinator?.performTableOverlayAction(action, info: info)
        }
        context.coordinator.installEdgeControls(in: textView)
        TableCommandCenter.shared.activate(textView)
        MarkdownEditorCommandCenter.shared.activate(textView)
        context.coordinator.lastMarkdown = text
        context.coordinator.lastDocumentURL = documentURL
        context.coordinator.lastTabID = tabID
        MarkdownRichText.load(markdown: text, baseURL: documentURL, into: textView)
        context.coordinator.updateEdgeControls()

        scrollView.documentView = textView
        context.coordinator.observeScrollView(scrollView)
        context.coordinator.restoreViewport(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.usesFullWidth = isFullWidth
        MarkdownEditorCommandCenter.shared.activate(textView)

        let tabChanged = context.coordinator.lastTabID != tabID
        let documentChanged = context.coordinator.lastDocumentURL?.standardizedFileURL != documentURL?.standardizedFileURL
        if !context.coordinator.isApplyingChange,
           context.coordinator.lastMarkdown != text || documentChanged || tabChanged {
            context.coordinator.isApplyingStyle = true
            context.coordinator.lastMarkdown = text
            context.coordinator.lastDocumentURL = documentURL
            context.coordinator.lastTabID = tabID
            MarkdownRichText.load(markdown: text, baseURL: documentURL, into: textView)
            context.coordinator.isApplyingStyle = false
            context.coordinator.updateEdgeControls()
            if tabChanged {
                context.coordinator.restoreViewport(in: scrollView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RenderedMarkdownEditor
        weak var textView: NSTextView?
        private var edgeControls: TableEdgeControls?
        private var hoverInfo: MarkdownRichText.TableHoverInfo?
        private var menuInfo: MarkdownRichText.TableHoverInfo?
        var isApplyingStyle = false
        var isApplyingChange = false
        var lastMarkdown = ""
        var lastDocumentURL: URL?
        var lastTabID: UUID?
        weak var scrollView: NSScrollView?
        private var pendingEditedRange: NSRange?

        init(_ parent: RenderedMarkdownEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observeScrollView(_ scrollView: NSScrollView) {
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func restoreViewport(in scrollView: NSScrollView) {
            guard let textView else { return }
            isApplyingStyle = true
            textView.setSelectedRange(NSRange(
                location: min(parent.caretLocation, textView.textStorage?.length ?? 0),
                length: 0
            ))
            isApplyingStyle = false
            let y = max(0, parent.scrollOffset)
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        @objc private func clipViewBoundsChanged() {
            reportViewport()
        }

        private func reportViewport() {
            guard !isApplyingStyle, !isApplyingChange, let textView, let scrollView else { return }
            parent.onViewportChange(
                parent.tabID,
                .rendered,
                textView.selectedRange().location,
                Double(scrollView.contentView.bounds.minY)
            )
        }

        func installEdgeControls(in textView: NSTextView) {
            let controls = TableEdgeControls(target: self)
            controls.onRowMenu = { [weak self, weak controls, weak textView] point in
                guard let controls, let textView else { return }
                self?.showRowMenu(at: textView.convert(point, from: controls))
            }
            controls.onColumnMenu = { [weak self, weak controls, weak textView] point in
                guard let controls, let textView else { return }
                self?.showColumnMenu(at: textView.convert(point, from: controls))
            }
            textView.addSubview(controls)
            edgeControls = controls
            (textView as? MarkdownTextView)?.tableEdgeOverlayInfo = nil
        }

        func updateEdgeControls() {
            guard let textView else { return }
            let info = currentTableInfo()
            edgeControls?.update(with: info, in: textView)
            (textView as? MarkdownTextView)?.tableEdgeOverlayInfo = edgeControls == nil ? info : nil
        }

        func mouseMoved(at point: NSPoint) {
            guard let textView else { return }
            hoverInfo = MarkdownRichText.tableHoverInfo(in: textView, at: point)
            updateEdgeControls()
        }

        func mouseExited() {
            hoverInfo = nil
            updateEdgeControls()
        }

        func performTableOverlayAction(
            _ action: MarkdownTextView.TableOverlayAction,
            info: MarkdownRichText.TableHoverInfo
        ) {
            hoverInfo = info
            switch action {
            case .insertRow:
                insertRowAtHover()
            case .insertColumn:
                insertColumnAtHover()
            case .selectRow:
                selectHoverRow()
            case .selectColumn:
                selectHoverColumn()
            }
        }

        func rightMouseDown(event: NSEvent, at point: NSPoint) -> Bool {
            guard let textView else { return false }
            let info = MarkdownRichText.tableHoverInfo(in: textView, at: point) ??
                MarkdownRichText.selectedTableEdgeInfo(in: textView)
            hoverInfo = info
            updateEdgeControls()

            guard let info else { return false }
            let localPoint = point

            if info.rowHandleFrame?.contains(localPoint) == true || info.rowIndex != nil && point.x < info.tableFrame.minX {
                showRowMenu(at: localPoint)
                return true
            }

            if info.columnHandleFrame?.contains(localPoint) == true || info.columnIndex != nil && point.y < info.tableFrame.minY {
                showColumnMenu(at: localPoint)
                return true
            }

            return false
        }

        @objc func insertRowAtHover() {
            guard let textView, let info = currentTableInfo(), let rowIndex = info.rowInsertionIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: min(max(rowIndex, 0), max(0, info.rowCount - 1)), column: info.columnIndex ?? 0)
            MarkdownRichText.insertTableRow(in: textView, at: rowIndex)
            updateAfterTableCommand()
        }

        @objc func insertColumnAtHover() {
            guard let textView, let info = currentTableInfo(), let columnIndex = info.columnInsertionIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: info.rowIndex ?? 0, column: min(max(columnIndex, 0), max(0, info.columnCount - 1)))
            MarkdownRichText.insertTableColumn(in: textView, at: columnIndex)
            updateAfterTableCommand()
        }

        @objc func selectHoverRow() {
            guard let textView, let info = currentTableInfo(), let rowIndex = info.rowIndex else { return }
            MarkdownRichText.selectTableRow(in: textView, tableID: info.tableID, row: rowIndex)
            TableCommandCenter.shared.updateContext(from: textView)
        }

        @objc func selectHoverColumn() {
            guard let textView, let info = currentTableInfo(), let columnIndex = info.columnIndex else { return }
            MarkdownRichText.selectTableColumn(in: textView, tableID: info.tableID, column: columnIndex)
            TableCommandCenter.shared.updateContext(from: textView)
        }

        @objc func insertRowAboveFromMenu() {
            guard let textView, let info = menuInfo, let row = info.rowIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: row, column: info.columnIndex ?? 0)
            MarkdownRichText.insertTableRow(in: textView, at: row)
            updateAfterTableCommand()
        }

        @objc func insertRowBelowFromMenu() {
            guard let textView, let info = menuInfo, let row = info.rowIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: row, column: info.columnIndex ?? 0)
            MarkdownRichText.insertTableRow(in: textView, at: row + 1)
            updateAfterTableCommand()
        }

        @objc func deleteRowFromMenu() {
            guard let textView, let info = menuInfo, let row = info.rowIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: row, column: info.columnIndex ?? 0)
            MarkdownRichText.deleteTableRow(in: textView, row: row)
            updateAfterTableCommand()
        }

        @objc func insertColumnLeftFromMenu() {
            guard let textView, let info = menuInfo, let column = info.columnIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: info.rowIndex ?? 0, column: column)
            MarkdownRichText.insertTableColumn(in: textView, at: column)
            updateAfterTableCommand()
        }

        @objc func insertColumnRightFromMenu() {
            guard let textView, let info = menuInfo, let column = info.columnIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: info.rowIndex ?? 0, column: column)
            MarkdownRichText.insertTableColumn(in: textView, at: column + 1)
            updateAfterTableCommand()
        }

        @objc func deleteColumnFromMenu() {
            guard let textView, let info = menuInfo, let column = info.columnIndex else { return }
            MarkdownRichText.selectTableCell(in: textView, tableID: info.tableID, row: info.rowIndex ?? 0, column: column)
            MarkdownRichText.deleteTableColumn(in: textView, column: column)
            updateAfterTableCommand()
        }

        private func showRowMenu(at point: NSPoint) {
            guard let textView, let info = currentTableInfo(), info.rowIndex != nil else { return }
            menuInfo = info
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "上面加一行", action: #selector(insertRowAboveFromMenu), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "下面加一行", action: #selector(insertRowBelowFromMenu), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "删除此行", action: #selector(deleteRowFromMenu), keyEquivalent: ""))
            menu.items.forEach { $0.target = self }
            menu.popUp(positioning: nil, at: point, in: textView)
        }

        private func showColumnMenu(at point: NSPoint) {
            guard let textView, let info = currentTableInfo(), info.columnIndex != nil else { return }
            menuInfo = info
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "左侧加一列", action: #selector(insertColumnLeftFromMenu), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "右侧加一列", action: #selector(insertColumnRightFromMenu), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "删除此列", action: #selector(deleteColumnFromMenu), keyEquivalent: ""))
            menu.items.forEach { $0.target = self }
            menu.popUp(positioning: nil, at: point, in: textView)
        }

        private func updateAfterTableCommand() {
            guard let textView else { return }
            MarkdownRichText.applyDisplayStyles(to: textView)
            let markdown = MarkdownRichText.serialize(textView.attributedString())
            lastMarkdown = markdown
            isApplyingChange = true
            parent.text = markdown
            isApplyingChange = false
            TableCommandCenter.shared.updateContext(from: textView)
            hoverInfo = nil
            updateEdgeControls()
        }

        private func currentTableInfo() -> MarkdownRichText.TableHoverInfo? {
            guard let textView,
                  MarkdownRichText.isSelectionInTable(textView),
                  let selectedInfo = MarkdownRichText.selectedTableEdgeInfo(in: textView) else {
                return nil
            }
            if let hoverInfo, hoverInfo.tableID == selectedInfo.tableID {
                return hoverInfo
            }
            return selectedInfo
        }

        func applySlashCommand(_ command: SlashCommand) {
            guard let textView else { return }
            if command.kind == .image {
                MarkdownRichText.applySlashCommand(
                    SlashCommand(title: "正文", detail: "", symbol: "", kind: .paragraph),
                    in: textView
                )
                parent.onRequestImage()
                return
            }
            MarkdownRichText.applySlashCommand(command, in: textView)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingStyle, let replacementString else { return true }
            pendingEditedRange = NSRange(
                location: affectedCharRange.location,
                length: (replacementString as NSString).length
            )

            if replacementString == "\n" || replacementString == "\r" || replacementString == "\r\n" {
                if MarkdownRichText.insertContinuedListLineBreakIfNeeded(
                    in: textView,
                    replacementRange: affectedCharRange
                ) {
                    return false
                }

                return !MarkdownRichText.insertResetLineBreakIfNeeded(
                    in: textView,
                    replacementRange: affectedCharRange
                )
            }

            if replacementString.isEmpty,
               MarkdownRichText.removeListMarkerIfNeeded(
                   in: textView,
                   replacementRange: affectedCharRange
               ) {
                return false
            }

            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingStyle, let textView else { return }

            isApplyingStyle = true
            let selectedRanges = textView.selectedRanges
            let editedRange = pendingEditedRange ?? textView.selectedRange()
            pendingEditedRange = nil
            let shortcutTypingAttributes = MarkdownRichText.consumeMarkdownShortcuts(in: textView, around: editedRange)
            MarkdownRichText.applyDisplayStyles(to: textView, around: editedRange)
            if shortcutTypingAttributes == nil {
                textView.selectedRanges = selectedRanges
            }
            if let shortcutTypingAttributes {
                textView.typingAttributes = shortcutTypingAttributes
            } else {
                MarkdownRichText.refreshTypingAttributes(in: textView)
            }

            let markdown = MarkdownRichText.serialize(textView.attributedString())
            lastMarkdown = markdown
            isApplyingChange = true
            parent.text = markdown
            isApplyingChange = false
            isApplyingStyle = false
            TableCommandCenter.shared.updateContext(from: textView)
            updateEdgeControls()
            reportViewport()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            TableCommandCenter.shared.updateContext(from: textView)
            updateEdgeControls()
            reportViewport()
        }
    }
}

@MainActor
enum MarkdownRichText {
    private enum Block {
        static let paragraph = "paragraph"
        static let heading = "heading"
        static let unorderedList = "unorderedList"
        static let orderedList = "orderedList"
        static let quote = "quote"
        static let code = "code"
        static let rule = "rule"
        static let table = "table"
    }

    private enum Inline {
        static let bold = "bold"
        static let italic = "italic"
        static let code = "code"
        static let link = "link"
        static let strikethrough = "strikethrough"
        static let image = "image"
    }

    struct TableHoverInfo {
        let tableID: String
        let tableFrame: NSRect
        let rowIndex: Int?
        let columnIndex: Int?
        let rowCount: Int
        let columnCount: Int
        let rowHandleFrame: NSRect?
        let columnHandleFrame: NSRect?
        let rowPlusFrame: NSRect?
        let columnPlusFrame: NSRect?
        let rowInsertionIndex: Int?
        let columnInsertionIndex: Int?
    }

    private struct TableCellLayout {
        let tableID: String
        let row: Int
        let column: Int
        let columnCount: Int
        let range: NSRange
        let frame: NSRect
    }

    private enum TableEdgeControlMetrics {
        static let edgeGap: CGFloat = 8
        static let plusSize = NSSize(width: 10, height: 10)
        static let rowHandleWidth: CGFloat = 20
        static let columnHandleHeight: CGFloat = 20
    }

    private static let codeTextBlock: NSTextBlock = {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setBorderColor(NSColor.separatorColor.withAlphaComponent(0.28))
        block.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68)
        return block
    }()

    private static let quoteTextBlock: NSTextBlock = {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(7, type: .absoluteValueType, for: .padding)
        block.setWidth(14, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(NSColor.controlAccentColor.withAlphaComponent(0.48))
        block.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.045)
        return block
    }()

    static func load(markdown: String, baseURL: URL? = nil, into textView: NSTextView) {
        let attributed = parse(markdown: markdown, baseURL: baseURL)
        textView.textStorage?.setAttributedString(attributed)
        applyDisplayStyles(to: textView)
        refreshTypingAttributes(in: textView)
    }

    static func attributedDocument(markdown: String, baseURL: URL? = nil) -> NSAttributedString {
        let textView = NSTextView()
        load(markdown: markdown, baseURL: baseURL, into: textView)
        return NSAttributedString(attributedString: textView.attributedString())
    }

    static func consumeMarkdownShortcuts(
        in textView: NSTextView,
        around editedRange: NSRange? = nil
    ) -> [NSAttributedString.Key: Any]? {
        guard let storage = textView.textStorage else { return nil }
        var typingAttributes: [NSAttributedString.Key: Any]?
        var selectedLocation = textView.selectedRange().location
        guard storage.length > 0 else { return nil }

        let string = storage.string as NSString
        let requestedRange = editedRange ?? textView.selectedRange()
        let start = min(requestedRange.location, storage.length)
        let safeLength = min(requestedRange.length, storage.length - start)
        let targetRange = string.lineRange(for: NSRange(location: start, length: safeLength))
        var location = targetRange.location
        var targetEnd = NSMaxRange(targetRange)

        storage.beginEditing()
        while location < storage.length, location < targetEnd {
            let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: location, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: storage.string as NSString, lineRange: lineRange)
            let line = (storage.string as NSString).substring(with: contentRange)

            if let heading = sourceHeading(in: line) {
                let markerLength = heading.level + 1
                let markerRange = NSRange(location: contentRange.location, length: min(markerLength, contentRange.length))
                storage.deleteCharacters(in: markerRange)
                targetEnd -= markerRange.length
                selectedLocation = max(contentRange.location, selectedLocation - markerRange.length)
                let newLineLength = max(0, contentRange.length - markerRange.length)
                let newRange = NSRange(location: contentRange.location, length: newLineLength)
                applyBlockAttributes(style: Block.heading, level: heading.level, range: newRange, storage: storage)
                typingAttributes = typingAttributesFor(style: Block.heading, level: heading.level)
                location = NSMaxRange(newRange)
                continue
            }

            if line == "- " || line == "* " || line == "+ " {
                storage.replaceCharacters(in: contentRange, with: "\u{2022} ")
                selectedLocation = contentRange.location + 2
                let newRange = NSRange(location: contentRange.location, length: 2)
                applyBlockAttributes(style: Block.unorderedList, range: newRange, storage: storage)
                typingAttributes = typingAttributesFor(style: Block.unorderedList)
                location = NSMaxRange(newRange)
                continue
            }

            if sourceQuote(in: line) {
                let markerRange = NSRange(location: contentRange.location, length: min(2, contentRange.length))
                storage.deleteCharacters(in: markerRange)
                targetEnd -= markerRange.length
                selectedLocation = max(contentRange.location, selectedLocation - markerRange.length)
                let newRange = NSRange(location: contentRange.location, length: max(0, contentRange.length - markerRange.length))
                applyBlockAttributes(style: Block.quote, range: newRange, storage: storage)
                typingAttributes = typingAttributesFor(style: Block.quote)
                location = NSMaxRange(newRange)
                continue
            }

            if let ordered = sourceOrderedList(in: line), line == "\(ordered). " {
                let newText = "\(ordered). "
                storage.replaceCharacters(in: contentRange, with: newText)
                selectedLocation = contentRange.location + (newText as NSString).length
                let newRange = NSRange(location: contentRange.location, length: (newText as NSString).length)
                applyBlockAttributes(style: Block.orderedList, index: ordered, range: newRange, storage: storage)
                typingAttributes = typingAttributesFor(style: Block.orderedList, index: ordered)
                location = NSMaxRange(newRange)
                continue
            }

            location = NSMaxRange(lineRange)
        }
        storage.endEditing()

        if selectedLocation <= storage.length {
            textView.setSelectedRange(NSRange(location: selectedLocation, length: 0))
        }
        return typingAttributes
    }

    static func applyDisplayStyles(to textView: NSTextView, around editedRange: NSRange? = nil) {
        guard let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let fullRange = NSRange(location: 0, length: storage.length)

        guard fullRange.length > 0 else {
            textView.typingAttributes = typingAttributesFor(style: Block.paragraph)
            return
        }

        let stylingRange: NSRange
        if let editedRange {
            let start = min(editedRange.location, storage.length)
            let safeLength = min(editedRange.length, storage.length - start)
            stylingRange = string.lineRange(for: NSRange(location: start, length: safeLength))
        } else {
            stylingRange = fullRange
        }

        storage.beginEditing()
        var location = stylingRange.location
        let stylingEnd = min(storage.length, NSMaxRange(stylingRange))
        while location < storage.length, location < stylingEnd {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: string, lineRange: lineRange)
            let style = blockStyle(in: storage, range: contentRange)
            let level = headingLevel(in: storage, range: contentRange)
            let index = orderedIndex(in: storage, range: contentRange)
            let blockRange = contentRange.length > 0 ? contentRange : lineRange

            applyBlockAttributes(style: style, level: level, index: index, range: blockRange, storage: storage)
            applyVisualAttributes(style: style, level: level, range: blockRange, storage: storage)
            applyInlineVisualAttributes(in: contentRange, storage: storage)
            location = NSMaxRange(lineRange)
        }
        storage.endEditing()

        refreshTypingAttributes(in: textView)
        textView.setNeedsDisplay(textView.bounds)
    }

    static func insertImage(
        _ insertion: ImageInsertion,
        baseURL: URL?,
        in textView: NSTextView,
        replacementRange: NSRange
    ) {
        guard let storage = textView.textStorage else { return }
        let paragraphAttributes = typingAttributesFor(style: Block.paragraph)
        let image = attributedImage(
            source: insertion.source,
            altText: insertion.altText,
            baseURL: baseURL,
            style: Block.paragraph,
            isBlock: true
        )

        let string = storage.string as NSString
        let leading = replacementRange.location > 0 && string.character(at: replacementRange.location - 1) != 10
            ? "\n"
            : ""
        let end = NSMaxRange(replacementRange)
        let trailing = end >= storage.length || string.character(at: end) != 10
            ? "\n"
            : ""
        let block = NSMutableAttributedString()
        if !leading.isEmpty {
            block.append(NSAttributedString(string: leading, attributes: paragraphAttributes))
        }
        block.append(image)
        if !trailing.isEmpty {
            block.append(NSAttributedString(string: trailing, attributes: paragraphAttributes))
        }

        storage.replaceCharacters(in: replacementRange, with: block)
        textView.setSelectedRange(NSRange(location: replacementRange.location + block.length, length: 0))
        textView.didChangeText()
        textView.typingAttributes = paragraphAttributes
    }

    static func applySlashCommand(_ command: SlashCommand, in textView: NSTextView) {
        guard let storage = textView.textStorage,
              let slashTextView = textView as? SlashCommandTextView,
              let triggerRange = slashTextView.slashTriggerRange() else {
            return
        }

        let replacement: NSAttributedString
        let typingAttributes: [NSAttributedString.Key: Any]

        switch command.kind {
        case .paragraph, .image:
            typingAttributes = typingAttributesFor(style: Block.paragraph)
            replacement = NSAttributedString(string: "", attributes: typingAttributes)
        case let .heading(level):
            typingAttributes = typingAttributesFor(style: Block.heading, level: level)
            replacement = NSAttributedString(string: "", attributes: typingAttributes)
        case .bold, .italic, .strikethrough, .inlineCode, .link:
            typingAttributes = typingAttributesFor(style: Block.paragraph)
            var inlineAttributes = typingAttributes
            let inlineStyle: String
            let placeholder: String
            switch command.kind {
            case .bold:
                inlineStyle = Inline.bold
                placeholder = "粗体"
            case .italic:
                inlineStyle = Inline.italic
                placeholder = "斜体"
            case .strikethrough:
                inlineStyle = Inline.strikethrough
                placeholder = "删除线"
            case .inlineCode:
                inlineStyle = Inline.code
                placeholder = "代码"
            default:
                inlineStyle = Inline.link
                placeholder = "链接文字"
                inlineAttributes[.markdownLinkURL] = "https://"
            }
            inlineAttributes[.markdownInlineStyle] = inlineStyle
            replacement = NSAttributedString(string: placeholder, attributes: inlineAttributes)
        case .unorderedList:
            typingAttributes = typingAttributesFor(style: Block.unorderedList)
            replacement = NSAttributedString(string: "\u{2022} ", attributes: typingAttributes)
        case .orderedList:
            typingAttributes = typingAttributesFor(style: Block.orderedList, index: 1)
            replacement = NSAttributedString(string: "1. ", attributes: typingAttributes)
        case .taskList:
            typingAttributes = typingAttributesFor(style: Block.unorderedList)
            var taskAttributes = typingAttributes
            taskAttributes[.markdownTaskState] = "unchecked"
            replacement = NSAttributedString(string: "☐ 待办事项", attributes: taskAttributes)
        case .quote:
            typingAttributes = typingAttributesFor(style: Block.quote)
            replacement = NSAttributedString(string: "", attributes: typingAttributes)
        case .code:
            typingAttributes = typingAttributesFor(style: Block.code)
            replacement = NSAttributedString(string: "", attributes: typingAttributes)
        case .table:
            typingAttributes = typingAttributesFor(style: Block.paragraph)
            replacement = parse(
                markdown: "| 标题 1 | 标题 2 |\n| --- | --- |\n| 内容 1 | 内容 2 |",
                baseURL: nil
            )
        case .rule:
            typingAttributes = typingAttributesFor(style: Block.rule)
            replacement = NSAttributedString(string: "――――――――", attributes: typingAttributes)
        }

        storage.replaceCharacters(in: triggerRange, with: replacement)
        let caret = triggerRange.location + replacement.length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.didChangeText()
        textView.typingAttributes = typingAttributes
    }

    static func refreshTypingAttributes(in textView: NSTextView) {
        guard let storage = textView.textStorage else {
            textView.typingAttributes = typingAttributesFor(style: Block.paragraph)
            return
        }

        let selected = min(textView.selectedRange().location, storage.length)
        guard storage.length > 0 else {
            textView.typingAttributes = typingAttributesFor(style: Block.paragraph)
            return
        }

        let lookup = max(0, min(selected == storage.length ? selected - 1 : selected, storage.length - 1))
        let style = storage.attribute(.markdownBlockStyle, at: lookup, effectiveRange: nil) as? String ?? Block.paragraph
        let level = (storage.attribute(.markdownHeadingLevel, at: lookup, effectiveRange: nil) as? NSNumber)?.intValue
        let index = (storage.attribute(.markdownOrderedIndex, at: lookup, effectiveRange: nil) as? NSNumber)?.intValue
        textView.typingAttributes = typingAttributesFor(style: style, level: level, index: index)
    }

    static func insertResetLineBreakIfNeeded(
        in textView: NSTextView,
        replacementRange: NSRange
    ) -> Bool {
        let styleFromTyping = textView.typingAttributes[.markdownBlockStyle] as? String
        let style = styleFromTyping ?? blockStyleAtInsertion(in: textView, location: replacementRange.location)

        guard style != Block.paragraph else { return false }

        let paragraphAttributes = typingAttributesFor(style: Block.paragraph)
        let lineBreak = NSAttributedString(string: "\n", attributes: paragraphAttributes)

        textView.textStorage?.replaceCharacters(in: replacementRange, with: lineBreak)
        textView.setSelectedRange(NSRange(location: replacementRange.location + 1, length: 0))
        textView.typingAttributes = paragraphAttributes
        textView.didChangeText()
        return true
    }

    static func insertContinuedListLineBreakIfNeeded(
        in textView: NSTextView,
        replacementRange: NSRange
    ) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let string = storage.string as NSString
        let lookup = min(replacementRange.location, max(0, storage.length - 1))
        let lineRange = string.lineRange(for: NSRange(location: lookup, length: 0))
        let contentRange = contentRangeWithoutLineEnding(in: string, lineRange: lineRange)
        let style = blockStyle(in: storage, range: contentRange)
        guard style == Block.unorderedList || style == Block.orderedList else { return false }

        let line = string.substring(with: contentRange)
        let marker: String
        let attributes: [NSAttributedString.Key: Any]

        if style == Block.orderedList {
            let currentIndex = orderedIndex(in: storage, range: contentRange)
                ?? sourceOrderedList(in: line)
                ?? 1
            let nextIndex = currentIndex + 1
            marker = "\(nextIndex). "
            attributes = typingAttributesFor(style: Block.orderedList, index: nextIndex)
        } else {
            marker = line.hasPrefix("☑ ") || line.hasPrefix("☐ ") ? "☐ " : "\u{2022} "
            attributes = typingAttributesFor(style: Block.unorderedList)
        }

        let continuedLine = NSAttributedString(string: "\n\(marker)", attributes: attributes)
        storage.replaceCharacters(in: replacementRange, with: continuedLine)
        let caret = replacementRange.location + continuedLine.length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.typingAttributes = attributes
        textView.didChangeText()
        return true
    }

    static func removeListMarkerIfNeeded(
        in textView: NSTextView,
        replacementRange: NSRange
    ) -> Bool {
        guard replacementRange.length == 1,
              let storage = textView.textStorage,
              storage.length > 0 else {
            return false
        }

        let string = storage.string as NSString
        let lookup = min(replacementRange.location, storage.length - 1)
        let lineRange = string.lineRange(for: NSRange(location: lookup, length: 0))
        let contentRange = contentRangeWithoutLineEnding(in: string, lineRange: lineRange)
        let style = blockStyle(in: storage, range: contentRange)
        guard style == Block.unorderedList || style == Block.orderedList else { return false }

        let markerRange = style == Block.unorderedList
            ? visibleAnyMarkerRange(prefixes: ["\u{2022} ", "☑ ", "☐ "], in: contentRange, storage: storage)
            : visibleOrderedMarkerRange(in: contentRange, storage: storage)
        guard markerRange.length > 0,
              NSMaxRange(replacementRange) == NSMaxRange(markerRange) else {
            return false
        }

        storage.deleteCharacters(in: markerRange)
        let remainingLength = max(0, contentRange.length - markerRange.length)
        let paragraphAttributes = typingAttributesFor(style: Block.paragraph)

        if remainingLength > 0 {
            let remainingRange = NSRange(location: contentRange.location, length: remainingLength)
            applyBlockAttributes(style: Block.paragraph, range: remainingRange, storage: storage)
            storage.removeAttribute(.markdownTaskState, range: remainingRange)
            applyVisualAttributes(style: Block.paragraph, level: nil, range: remainingRange, storage: storage)
        } else if contentRange.location > 0 {
            let precedingCharacterRange = NSRange(location: contentRange.location - 1, length: 1)
            storage.setAttributes(paragraphAttributes, range: precedingCharacterRange)
        }

        textView.setSelectedRange(NSRange(location: contentRange.location, length: 0))
        textView.typingAttributes = paragraphAttributes
        textView.didChangeText()
        return true
    }

    static func isSelectionInTable(_ textView: NSTextView) -> Bool {
        tableSnapshot(in: textView) != nil
    }

    static func selectedTableFrame(in textView: NSTextView) -> NSRect? {
        guard let context = tableContext(in: textView) else { return nil }
        let cells = tableCellLayouts(in: textView).filter { $0.tableID == context.tableID }
        guard !cells.isEmpty else { return nil }
        return tableFrame(from: cells)
    }

    static func tableHoverInfo(in textView: NSTextView, at point: NSPoint) -> TableHoverInfo? {
        let cells = tableCellLayouts(in: textView)
        guard !cells.isEmpty else { return nil }

        let grouped = Dictionary(grouping: cells, by: \.tableID)
        let candidates = grouped.compactMap { tableID, cells -> TableHoverInfo? in
            guard let first = cells.first else { return nil }
            let tableFrame = tableFrame(from: cells)
            let hitFrame = tableFrame.insetBy(dx: -42, dy: -34)
            guard hitFrame.contains(point) else { return nil }

            let rowGroups = Dictionary(grouping: cells, by: \.row)
            let columnGroups = Dictionary(grouping: cells, by: \.column)
            let rowCount = max((rowGroups.keys.max() ?? 0) + 1, 1)
            let columnCount = max(first.columnCount, (columnGroups.keys.max() ?? 0) + 1, 1)
            let rowFrames = rowFrames(from: cells, tableFrame: tableFrame, rowCount: rowCount)
            let columnFrames = columnFrames(from: cells, tableFrame: tableFrame, columnCount: columnCount)

            let rowIndex = rowFrames
                .filter { $0.value.minY - 6 <= point.y && point.y <= $0.value.maxY + 6 }
                .min { abs($0.value.midY - point.y) < abs($1.value.midY - point.y) }?
                .key
            let columnIndex = columnFrames
                .filter { $0.value.minX - 6 <= point.x && point.x <= $0.value.maxX + 6 }
                .min { abs($0.value.midX - point.x) < abs($1.value.midX - point.x) }?
                .key

            let nearLeftEdge = point.x >= tableFrame.minX - 36 && point.x <= tableFrame.minX + 12
            let nearTopEdge = point.y >= tableFrame.minY - 30 && point.y <= tableFrame.minY + 12

            let rowHandleFrame: NSRect? = if let rowIndex, let rowFrame = rowFrames[rowIndex], nearLeftEdge {
                rowHandleFrame(tableFrame: tableFrame, rowFrame: rowFrame)
            } else {
                nil
            }

            let columnHandleFrame: NSRect? = if let columnIndex, let columnFrame = columnFrames[columnIndex], nearTopEdge {
                columnHandleFrame(tableFrame: tableFrame, columnFrame: columnFrame)
            } else {
                nil
            }

            let rowBoundary = nearestHorizontalBoundary(
                to: point.y,
                frames: rowFrames,
                limit: 7
            )
            let rowPlusFrame: NSRect? = if let rowBoundary, nearLeftEdge {
                rowPlusFrame(tableFrame: tableFrame, y: rowBoundary.position)
            } else {
                nil
            }

            let columnBoundary = nearestVerticalBoundary(
                to: point.x,
                frames: columnFrames,
                limit: 7
            )
            let columnPlusFrame: NSRect? = if let columnBoundary, nearTopEdge {
                columnPlusFrame(tableFrame: tableFrame, x: columnBoundary.position)
            } else {
                nil
            }

            let hasAnyControl = rowHandleFrame != nil ||
                columnHandleFrame != nil ||
                rowPlusFrame != nil ||
                columnPlusFrame != nil
            guard hasAnyControl else { return nil }

            return TableHoverInfo(
                tableID: tableID,
                tableFrame: tableFrame,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                rowCount: rowCount,
                columnCount: columnCount,
                rowHandleFrame: rowHandleFrame,
                columnHandleFrame: columnHandleFrame,
                rowPlusFrame: rowPlusFrame,
                columnPlusFrame: columnPlusFrame,
                rowInsertionIndex: rowBoundary?.insertionIndex,
                columnInsertionIndex: columnBoundary?.insertionIndex
            )
        }

        return candidates.min { $0.tableFrame.distance(to: point) < $1.tableFrame.distance(to: point) }
    }

    static func selectedTableEdgeInfo(in textView: NSTextView) -> TableHoverInfo? {
        guard let context = tableContext(in: textView) else { return nil }
        let cells = tableCellLayouts(in: textView).filter { $0.tableID == context.tableID }
        return tableEdgeInfo(
            tableID: context.tableID,
            cells: cells,
            row: context.row,
            column: context.column
        )
    }

    static func visibleTableEdgeInfo(in textView: NSTextView) -> TableHoverInfo? {
        let cells = tableCellLayouts(in: textView)
        guard !cells.isEmpty else { return nil }

        let visibleRect = textView.visibleRect.insetBy(dx: -48, dy: -48)
        let grouped = Dictionary(grouping: cells, by: \.tableID)
        let visibleTables = grouped.compactMap { tableID, cells -> (tableID: String, cells: [TableCellLayout], frame: NSRect)? in
            let tableFrame = tableFrame(from: cells)
            guard tableFrame.intersects(visibleRect) else { return nil }
            return (tableID, cells, tableFrame)
        }

        guard let table = visibleTables.min(by: { $0.frame.minY < $1.frame.minY }) else { return nil }
        return tableEdgeInfo(
            tableID: table.tableID,
            cells: table.cells,
            row: 0,
            column: 0
        )
    }

    private static func tableEdgeInfo(
        tableID: String,
        cells: [TableCellLayout],
        row: Int,
        column: Int
    ) -> TableHoverInfo? {
        guard !cells.isEmpty else { return nil }

        let tableFrame = tableFrame(from: cells)
        let rowGroups = Dictionary(grouping: cells, by: \.row)
        let columnGroups = Dictionary(grouping: cells, by: \.column)
        let rowCount = max((rowGroups.keys.max() ?? 0) + 1, 1)
        let columnCount = max((cells.first?.columnCount ?? 0), (columnGroups.keys.max() ?? 0) + 1, 1)
        let rowFrames = rowFrames(from: cells, tableFrame: tableFrame, rowCount: rowCount)
        let columnFrames = columnFrames(from: cells, tableFrame: tableFrame, columnCount: columnCount)
        let resolvedRow = min(max(row, 0), max(0, rowCount - 1))
        let resolvedColumn = min(max(column, 0), max(0, columnCount - 1))
        let rowFrame = rowFrames[resolvedRow] ?? tableFrame
        let columnFrame = columnFrames[resolvedColumn] ?? tableFrame

        return TableHoverInfo(
            tableID: tableID,
            tableFrame: tableFrame,
            rowIndex: resolvedRow,
            columnIndex: resolvedColumn,
            rowCount: rowCount,
            columnCount: columnCount,
            rowHandleFrame: rowHandleFrame(tableFrame: tableFrame, rowFrame: rowFrame),
            columnHandleFrame: columnHandleFrame(tableFrame: tableFrame, columnFrame: columnFrame),
            rowPlusFrame: rowPlusFrame(tableFrame: tableFrame, y: rowFrame.maxY),
            columnPlusFrame: columnPlusFrame(tableFrame: tableFrame, x: columnFrame.maxX),
            rowInsertionIndex: min(resolvedRow + 1, rowCount),
            columnInsertionIndex: min(resolvedColumn + 1, columnCount)
        )
    }

    private static func rowHandleFrame(tableFrame: NSRect, rowFrame: NSRect) -> NSRect {
        return NSRect(
            x: max(2, tableFrame.minX - TableEdgeControlMetrics.edgeGap - TableEdgeControlMetrics.rowHandleWidth),
            y: rowFrame.minY,
            width: TableEdgeControlMetrics.rowHandleWidth,
            height: rowFrame.height
        )
    }

    private static func columnHandleFrame(tableFrame: NSRect, columnFrame: NSRect) -> NSRect {
        return NSRect(
            x: columnFrame.minX,
            y: tableFrame.minY - TableEdgeControlMetrics.edgeGap - TableEdgeControlMetrics.columnHandleHeight,
            width: columnFrame.width,
            height: TableEdgeControlMetrics.columnHandleHeight
        )
    }

    private static func rowPlusFrame(tableFrame: NSRect, y: CGFloat) -> NSRect {
        let size = TableEdgeControlMetrics.plusSize
        return NSRect(
            x: max(2, tableFrame.minX - TableEdgeControlMetrics.edgeGap - size.width),
            y: y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func columnPlusFrame(tableFrame: NSRect, x: CGFloat) -> NSRect {
        let size = TableEdgeControlMetrics.plusSize
        return NSRect(
            x: x - size.width / 2,
            y: tableFrame.minY - TableEdgeControlMetrics.edgeGap - size.height,
            width: size.width,
            height: size.height
        )
    }

    private static func tableFrame(from cells: [TableCellLayout]) -> NSRect {
        cells
            .map(\.frame)
            .reduce(NSRect.null) { $0.union($1) }
            .integral
    }

    private static func rowFrames(
        from cells: [TableCellLayout],
        tableFrame: NSRect,
        rowCount: Int
    ) -> [Int: NSRect] {
        let fallback = visualRowFrames(tableFrame: tableFrame, rowCount: rowCount)
        let grouped = Dictionary(grouping: cells, by: \.row)
        return fallback.mapValues { frame in frame }.merging(
            grouped.mapValues { rowCells in
                rowCells
                    .map(\.frame)
                    .reduce(NSRect.null) { $0.union($1) }
                    .integral
            },
            uniquingKeysWith: { _, actual in actual }
        )
    }

    private static func columnFrames(
        from cells: [TableCellLayout],
        tableFrame: NSRect,
        columnCount: Int
    ) -> [Int: NSRect] {
        let fallback = visualColumnFrames(tableFrame: tableFrame, columnCount: columnCount)
        let grouped = Dictionary(grouping: cells, by: \.column)
        return fallback.mapValues { frame in frame }.merging(
            grouped.mapValues { columnCells in
                columnCells
                    .map(\.frame)
                    .reduce(NSRect.null) { $0.union($1) }
                    .integral
            },
            uniquingKeysWith: { _, actual in actual }
        )
    }

    private static func visualRowFrames(tableFrame: NSRect, rowCount: Int) -> [Int: NSRect] {
        let count = max(rowCount, 1)
        let height = tableFrame.height / CGFloat(count)
        return Dictionary(uniqueKeysWithValues: (0..<count).map { row in
            let y = tableFrame.minY + CGFloat(row) * height
            return (row, NSRect(x: tableFrame.minX, y: y, width: tableFrame.width, height: height))
        })
    }

    private static func visualColumnFrames(tableFrame: NSRect, columnCount: Int) -> [Int: NSRect] {
        let count = max(columnCount, 1)
        let width = tableFrame.width / CGFloat(count)
        return Dictionary(uniqueKeysWithValues: (0..<count).map { column in
            let x = tableFrame.minX + CGFloat(column) * width
            return (column, NSRect(x: x, y: tableFrame.minY, width: width, height: tableFrame.height))
        })
    }

    static func insertTableRowBelow(in textView: NSTextView) {
        editTable(in: textView) { snapshot in
            let insertAt = min(snapshot.currentRow + 1, snapshot.rows.count)
            let emptyRow = Array(repeating: NSMutableAttributedString(string: ""), count: snapshot.columnCount)
            snapshot.rows.insert(emptyRow, at: insertAt)
            snapshot.currentRow = insertAt
        }
    }

    static func insertTableRow(in textView: NSTextView, at rowIndex: Int) {
        editTable(in: textView) { snapshot in
            let insertAt = min(max(0, rowIndex), snapshot.rows.count)
            let emptyRow = Array(repeating: NSMutableAttributedString(string: ""), count: snapshot.columnCount)
            snapshot.rows.insert(emptyRow, at: insertAt)
            snapshot.currentRow = insertAt
        }
    }

    static func deleteTableRow(in textView: NSTextView) {
        editTable(in: textView) { snapshot in
            guard snapshot.rows.count > 1 else { return }
            snapshot.rows.remove(at: snapshot.currentRow)
            snapshot.currentRow = min(snapshot.currentRow, snapshot.rows.count - 1)
        }
    }

    static func deleteTableRow(in textView: NSTextView, row rowIndex: Int) {
        editTable(in: textView) { snapshot in
            guard snapshot.rows.count > 1 else { return }
            let deleteAt = min(max(0, rowIndex), snapshot.rows.count - 1)
            snapshot.rows.remove(at: deleteAt)
            snapshot.currentRow = min(deleteAt, snapshot.rows.count - 1)
        }
    }

    static func insertTableColumnRight(in textView: NSTextView) {
        editTable(in: textView) { snapshot in
            let insertAt = min(snapshot.currentColumn + 1, snapshot.columnCount)
            for rowIndex in snapshot.rows.indices {
                snapshot.rows[rowIndex].insert(NSMutableAttributedString(string: ""), at: insertAt)
            }
            snapshot.columnCount += 1
            snapshot.currentColumn = insertAt
        }
    }

    static func insertTableColumn(in textView: NSTextView, at columnIndex: Int) {
        editTable(in: textView) { snapshot in
            let insertAt = min(max(0, columnIndex), snapshot.columnCount)
            for rowIndex in snapshot.rows.indices {
                snapshot.rows[rowIndex].insert(NSMutableAttributedString(string: ""), at: insertAt)
            }
            snapshot.columnCount += 1
            snapshot.currentColumn = insertAt
        }
    }

    static func deleteTableColumn(in textView: NSTextView) {
        editTable(in: textView) { snapshot in
            guard snapshot.columnCount > 1 else { return }
            for rowIndex in snapshot.rows.indices {
                snapshot.rows[rowIndex].remove(at: snapshot.currentColumn)
            }
            snapshot.columnCount -= 1
            snapshot.currentColumn = min(snapshot.currentColumn, snapshot.columnCount - 1)
        }
    }

    static func deleteTableColumn(in textView: NSTextView, column columnIndex: Int) {
        editTable(in: textView) { snapshot in
            guard snapshot.columnCount > 1 else { return }
            let deleteAt = min(max(0, columnIndex), snapshot.columnCount - 1)
            for rowIndex in snapshot.rows.indices {
                snapshot.rows[rowIndex].remove(at: deleteAt)
            }
            snapshot.columnCount -= 1
            snapshot.currentColumn = min(deleteAt, snapshot.columnCount - 1)
        }
    }

    static func selectTableCell(in textView: NSTextView, tableID: String, row: Int, column: Int) {
        guard let range = tableCellRange(in: textView, tableID: tableID, row: row, column: column) else { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    static func selectTableRow(in textView: NSTextView, tableID: String, row: Int) {
        let ranges = tableCellRanges(in: textView, tableID: tableID)
            .filter { $0.row == row }
            .map { NSValue(range: $0.range) }
        guard !ranges.isEmpty else { return }
        textView.selectedRanges = ranges
    }

    static func selectTableColumn(in textView: NSTextView, tableID: String, column: Int) {
        let ranges = tableCellRanges(in: textView, tableID: tableID)
            .filter { $0.column == column }
            .map { NSValue(range: $0.range) }
        guard !ranges.isEmpty else { return }
        textView.selectedRanges = ranges
    }

    static func serialize(_ attributed: NSAttributedString) -> String {
        let nsString = attributed.string as NSString
        var lines: [String] = []
        var location = 0
        var inCodeBlock = false

        while location < attributed.length || (attributed.length == 0 && location == 0) {
            let lineRange: NSRange
            if attributed.length == 0 {
                lineRange = NSRange(location: 0, length: 0)
            } else {
                lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
            }

            let contentRange = contentRangeWithoutLineEnding(in: nsString, lineRange: lineRange)
            let style = blockStyle(in: attributed, range: contentRange)
            let level = headingLevel(in: attributed, range: contentRange) ?? 1
            let ordered = orderedIndex(in: attributed, range: contentRange) ?? 1
            let isImageBlock = contentRange.length > 0 &&
                (attributed.attribute(.markdownImageBlock, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.boolValue == true

            if isImageBlock, !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }

            if style == Block.table {
                if inCodeBlock {
                    lines.append("```")
                    inCodeBlock = false
                }

                let table = serializeTable(
                    from: attributed,
                    string: nsString,
                    startingAt: location
                )
                lines.append(contentsOf: table.lines)
                location = table.nextLocation
                continue
            } else if style == Block.code {
                if !inCodeBlock {
                    lines.append("```")
                    inCodeBlock = true
                }
                lines.append(nsString.substring(with: contentRange))
            } else {
                if inCodeBlock {
                    lines.append("```")
                    inCodeBlock = false
                }

                switch style {
                case Block.heading:
                    let marker = String(repeating: "#", count: max(1, min(6, level)))
                    let body = inlineMarkdown(from: attributed, range: contentRange)
                    lines.append(body.isEmpty ? marker : "\(marker) \(body)")
                case Block.unorderedList:
                    let bodyRange = rangeSkippingVisibleListMarker(contentRange, in: nsString)
                    let taskState = bodyRange.length > 0
                        ? attributed.attribute(.markdownTaskState, at: bodyRange.location, effectiveRange: nil) as? String
                        : nil
                    let marker: String
                    switch taskState {
                    case "checked":
                        marker = "- [x] "
                    case "unchecked":
                        marker = "- [ ] "
                    default:
                        marker = "- "
                    }
                    lines.append("\(marker)\(inlineMarkdown(from: attributed, range: bodyRange))")
                case Block.orderedList:
                    lines.append("\(ordered). \(inlineMarkdown(from: attributed, range: rangeSkippingVisibleOrderedMarker(contentRange, in: nsString)))")
                case Block.quote:
                    lines.append("> \(inlineMarkdown(from: attributed, range: contentRange))")
                case Block.rule:
                    lines.append("---")
                default:
                    lines.append(inlineMarkdown(from: attributed, range: contentRange))
                }
            }

            if isImageBlock,
               NSMaxRange(lineRange) < attributed.length,
               lines.last?.isEmpty == false {
                lines.append("")
            }

            if attributed.length == 0 {
                break
            }
            location = NSMaxRange(lineRange)
        }

        if inCodeBlock {
            lines.append("```")
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeTable(
        from attributed: NSAttributedString,
        string nsString: NSString,
        startingAt location: Int
    ) -> (lines: [String], nextLocation: Int) {
        let firstRange = contentRangeWithoutLineEnding(
            in: nsString,
            lineRange: nsString.lineRange(for: NSRange(location: location, length: 0))
        )
        let tableID = attributed.attribute(.markdownTableID, at: firstRange.location, effectiveRange: nil) as? String
        var cursor = location
        var columnCount = 0
        var rows: [Int: [Int: String]] = [:]
        var headerRows = Set<Int>()

        while cursor < attributed.length {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: nsString, lineRange: lineRange)
            guard blockStyle(in: attributed, range: contentRange) == Block.table else { break }

            let currentID = attributed.attribute(.markdownTableID, at: contentRange.location, effectiveRange: nil) as? String
            if tableID != nil, currentID != tableID {
                break
            }

            let row = (attributed.attribute(.markdownTableRow, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let column = (attributed.attribute(.markdownTableColumn, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let declaredColumns = (attributed.attribute(.markdownTableColumnCount, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let isHeader = (attributed.attribute(.markdownTableHeader, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.boolValue ?? false
            let cell = inlineMarkdown(from: attributed, range: contentRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            rows[row, default: [:]][column] = cell
            columnCount = max(columnCount, declaredColumns, column + 1)
            if isHeader {
                headerRows.insert(row)
            }

            cursor = NSMaxRange(lineRange)
        }

        var output: [String] = []
        for row in rows.keys.sorted() {
            let cells = (0..<max(1, columnCount)).map { rows[row]?[$0] ?? "" }
            output.append("| \(cells.joined(separator: " | ")) |")
            if headerRows.contains(row) {
                output.append("| \((0..<max(1, columnCount)).map { _ in "---" }.joined(separator: " | ")) |")
            }
        }

        return (output, cursor)
    }

    private struct TableSnapshot {
        var tableID: String
        var range: NSRange
        var rows: [[NSMutableAttributedString]]
        var columnCount: Int
        var currentRow: Int
        var currentColumn: Int
    }

    private static func editTable(
        in textView: NSTextView,
        mutate: (inout TableSnapshot) -> Void
    ) {
        guard var snapshot = tableSnapshot(in: textView),
              let storage = textView.textStorage else { return }

        mutate(&snapshot)
        snapshot.columnCount = max(1, snapshot.columnCount)
        snapshot.currentRow = min(max(0, snapshot.currentRow), max(0, snapshot.rows.count - 1))
        snapshot.currentColumn = min(max(0, snapshot.currentColumn), max(0, snapshot.columnCount - 1))

        for rowIndex in snapshot.rows.indices {
            while snapshot.rows[rowIndex].count < snapshot.columnCount {
                snapshot.rows[rowIndex].append(NSMutableAttributedString(string: ""))
            }
            while snapshot.rows[rowIndex].count > snapshot.columnCount {
                snapshot.rows[rowIndex].removeLast()
            }
        }

        let rebuilt = attributedTable(
            rows: snapshot.rows,
            tableID: snapshot.tableID,
            columnCount: snapshot.columnCount,
            selectedRow: snapshot.currentRow,
            selectedColumn: snapshot.currentColumn
        )

        storage.replaceCharacters(in: snapshot.range, with: rebuilt.text)
        let selection = NSRange(location: snapshot.range.location + rebuilt.selectionOffset, length: 0)
        textView.setSelectedRange(selection)
        textView.typingAttributes = typingAttributesFor(style: Block.table)
        textView.didChangeText()
    }

    private static func tableSnapshot(in textView: NSTextView) -> TableSnapshot? {
        guard let storage = textView.textStorage,
              storage.length > 0,
              let context = tableContext(in: textView) else { return nil }

        let nsString = storage.string as NSString
        var start = nsString.lineRange(for: NSRange(location: context.location, length: 0)).location
        var end = start

        while start > 0 {
            let previousLine = nsString.lineRange(for: NSRange(location: start - 1, length: 0))
            let previousContent = contentRangeWithoutLineEnding(in: nsString, lineRange: previousLine)
            guard isTableCell(at: previousContent.location, tableID: context.tableID, in: storage) else { break }
            start = previousLine.location
        }

        var cursor = start
        while cursor < storage.length {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: nsString, lineRange: lineRange)
            guard isTableCell(at: contentRange.location, tableID: context.tableID, in: storage) else { break }
            end = NSMaxRange(contentRange)
            cursor = NSMaxRange(lineRange)
        }

        guard end > start else { return nil }

        var rowsByIndex: [Int: [Int: NSMutableAttributedString]] = [:]
        var columnCount = context.columnCount
        cursor = start

        while cursor < end {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: nsString, lineRange: lineRange)
            guard isTableCell(at: contentRange.location, tableID: context.tableID, in: storage) else { break }

            let row = (storage.attribute(.markdownTableRow, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let column = (storage.attribute(.markdownTableColumn, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let declaredColumns = (storage.attribute(.markdownTableColumnCount, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            columnCount = max(columnCount, declaredColumns, column + 1)
            rowsByIndex[row, default: [:]][column] = editableCellContent(from: storage, range: contentRange)

            cursor = NSMaxRange(lineRange)
        }

        let rowCount = max((rowsByIndex.keys.max() ?? 0) + 1, 1)
        var rows: [[NSMutableAttributedString]] = []
        for row in 0..<rowCount {
            var cells: [NSMutableAttributedString] = []
            for column in 0..<max(1, columnCount) {
                cells.append(rowsByIndex[row]?[column] ?? NSMutableAttributedString(string: ""))
            }
            rows.append(cells)
        }

        return TableSnapshot(
            tableID: context.tableID,
            range: NSRange(location: start, length: end - start),
            rows: rows,
            columnCount: max(1, columnCount),
            currentRow: context.row,
            currentColumn: context.column
        )
    }

    private static func tableCellLayouts(in textView: NSTextView) -> [TableCellLayout] {
        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              storage.length > 0 else {
            return []
        }

        layoutManager.ensureLayout(for: textContainer)
        let nsString = storage.string as NSString
        var cursor = 0
        var cells: [TableCellLayout] = []

        while cursor < storage.length {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: nsString, lineRange: lineRange)

            if contentRange.length > 0,
               blockStyle(in: storage, range: contentRange) == Block.table,
               let tableID = storage.attribute(.markdownTableID, at: contentRange.location, effectiveRange: nil) as? String {
                var actualRange = NSRange(location: 0, length: 0)
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: contentRange,
                    actualCharacterRange: &actualRange
                )
                let paragraphStyle = storage.attribute(
                    .paragraphStyle,
                    at: contentRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle
                let tableBlock = paragraphStyle?.textBlocks.compactMap { $0 as? NSTextTableBlock }.last

                var frame = if let tableBlock {
                    layoutManager.boundsRect(for: tableBlock, at: glyphRange.location, effectiveRange: nil)
                } else {
                    layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                        .insetBy(dx: -12, dy: -8)
                }
                frame.origin.x += textView.textContainerOrigin.x
                frame.origin.y += textView.textContainerOrigin.y

                let row = (storage.attribute(.markdownTableRow, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
                let column = (storage.attribute(.markdownTableColumn, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
                let columnCount = (storage.attribute(.markdownTableColumnCount, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 1

                cells.append(
                    TableCellLayout(
                        tableID: tableID,
                        row: row,
                        column: column,
                        columnCount: columnCount,
                        range: contentRange,
                        frame: frame.integral
                    )
                )
            }

            cursor = NSMaxRange(lineRange)
        }

        return cells
    }

    private static func nearestHorizontalBoundary(
        to value: CGFloat,
        frames: [Int: NSRect],
        limit: CGFloat
    ) -> (position: CGFloat, insertionIndex: Int)? {
        var best: (position: CGFloat, insertionIndex: Int, distance: CGFloat)?

        for (index, frame) in frames {
            [
                (frame.minY, index),
                (frame.maxY, index + 1)
            ].forEach { position, insertionIndex in
                let distance = abs(value - position)
                guard distance <= limit else { return }
                if best == nil || distance < best!.distance {
                    best = (position, insertionIndex, distance)
                }
            }
        }

        guard let best else { return nil }
        return (best.position, best.insertionIndex)
    }

    private static func nearestVerticalBoundary(
        to value: CGFloat,
        frames: [Int: NSRect],
        limit: CGFloat
    ) -> (position: CGFloat, insertionIndex: Int)? {
        var best: (position: CGFloat, insertionIndex: Int, distance: CGFloat)?

        for (index, frame) in frames {
            [
                (frame.minX, index),
                (frame.maxX, index + 1)
            ].forEach { position, insertionIndex in
                let distance = abs(value - position)
                guard distance <= limit else { return }
                if best == nil || distance < best!.distance {
                    best = (position, insertionIndex, distance)
                }
            }
        }

        guard let best else { return nil }
        return (best.position, best.insertionIndex)
    }

    private static func tableCellRange(in textView: NSTextView, tableID: String, row: Int, column: Int) -> NSRange? {
        tableCellRanges(in: textView, tableID: tableID)
            .first { $0.row == row && $0.column == column }?
            .range
    }

    private static func tableCellRanges(in textView: NSTextView, tableID: String) -> [(row: Int, column: Int, range: NSRange)] {
        guard let storage = textView.textStorage, storage.length > 0 else { return [] }
        let nsString = storage.string as NSString
        var cursor = 0
        var ranges: [(row: Int, column: Int, range: NSRange)] = []

        while cursor < storage.length {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = contentRangeWithoutLineEnding(in: nsString, lineRange: lineRange)
            if contentRange.length > 0,
               blockStyle(in: storage, range: contentRange) == Block.table,
               storage.attribute(.markdownTableID, at: contentRange.location, effectiveRange: nil) as? String == tableID {
                let row = (storage.attribute(.markdownTableRow, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
                let column = (storage.attribute(.markdownTableColumn, at: contentRange.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
                ranges.append((row, column, contentRange))
            }
            cursor = NSMaxRange(lineRange)
        }

        return ranges
    }

    private static func tableContext(in textView: NSTextView) -> (location: Int, tableID: String, row: Int, column: Int, columnCount: Int)? {
        guard let storage = textView.textStorage, storage.length > 0 else { return nil }
        let selected = textView.selectedRange().location
        let candidates = [
            selected,
            selected - 1,
            selected + 1
        ]

        for location in candidates where location >= 0 && location < storage.length {
            guard blockStyle(in: storage, range: NSRange(location: location, length: 1)) == Block.table,
                  let tableID = storage.attribute(.markdownTableID, at: location, effectiveRange: nil) as? String else {
                continue
            }

            let row = (storage.attribute(.markdownTableRow, at: location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let column = (storage.attribute(.markdownTableColumn, at: location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            let columnCount = (storage.attribute(.markdownTableColumnCount, at: location, effectiveRange: nil) as? NSNumber)?.intValue ?? 1
            return (location, tableID, row, column, columnCount)
        }

        return nil
    }

    private static func isTableCell(at location: Int, tableID: String, in attributed: NSAttributedString) -> Bool {
        guard location >= 0 && location < attributed.length else { return false }
        return blockStyle(in: attributed, range: NSRange(location: location, length: 1)) == Block.table &&
            attributed.attribute(.markdownTableID, at: location, effectiveRange: nil) as? String == tableID
    }

    private static func editableCellContent(
        from attributed: NSAttributedString,
        range: NSRange
    ) -> NSMutableAttributedString {
        guard range.length > 0 else { return NSMutableAttributedString(string: "") }
        let content = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: range))
        let fullRange = NSRange(location: 0, length: content.length)

        [
            NSAttributedString.Key.paragraphStyle,
            .markdownBlockStyle,
            .markdownHeadingLevel,
            .markdownOrderedIndex,
            .markdownTableHeader,
            .markdownTableID,
            .markdownTableRow,
            .markdownTableColumn,
            .markdownTableColumnCount
        ].forEach { content.removeAttribute($0, range: fullRange) }

        if content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSMutableAttributedString(string: "")
        }

        return content
    }

    private static func attributedTable(
        rows: [[NSMutableAttributedString]],
        tableID: String,
        columnCount: Int,
        selectedRow: Int,
        selectedColumn: Int
    ) -> (text: NSAttributedString, selectionOffset: Int) {
        let result = NSMutableAttributedString()
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        var selectionOffset = 0

        for rowIndex in rows.indices {
            for columnIndex in 0..<columnCount {
                if result.length > 0 {
                    result.append(NSAttributedString(string: "\n"))
                }

                if rowIndex == selectedRow && columnIndex == selectedColumn {
                    selectionOffset = result.length
                }

                let cell = columnIndex < rows[rowIndex].count
                    ? rows[rowIndex][columnIndex]
                    : NSMutableAttributedString(string: "")

                result.append(
                    tableCellAttributedString(
                        content: cell,
                        isHeader: rowIndex == 0,
                        table: table,
                        tableID: tableID,
                        rowIndex: rowIndex,
                        columnIndex: columnIndex,
                        columnCount: columnCount,
                        rowCount: rows.count
                    )
                )
            }
        }

        return (result, selectionOffset)
    }

    private static func parse(markdown: String, baseURL: URL?) -> NSMutableAttributedString {
        var renderer = MarkdownASTRenderer(baseURL: baseURL)
        return renderer.render(markdown: markdown)
    }

    @MainActor
    private struct MarkdownASTRenderer {
        let baseURL: URL?
        private var result = NSMutableAttributedString()
        private var listDepth = 0

        init(baseURL: URL?) {
            self.baseURL = baseURL
        }

        mutating func render(markdown: String) -> NSMutableAttributedString {
            let document = Markdown.Document(
                parsing: markdown,
                options: [.disableSmartOpts]
            )
            appendChildren(of: document)
            return result
        }

        private mutating func appendChildren(of markup: Markdown.Markup) {
            for child in markup.children {
                appendBlock(child)
            }
        }

        private mutating func appendBlock(_ markup: Markdown.Markup) {
            if let heading = markup as? Markdown.Heading {
                appendLine(inlineChildren(of: heading, style: Block.heading, level: heading.level))
            } else if let paragraph = markup as? Markdown.Paragraph {
                let line = NSMutableAttributedString(
                    attributedString: inlineChildren(of: paragraph, style: Block.paragraph)
                )
                let paragraphChildren = Array(paragraph.children)
                if paragraphChildren.count == 1,
                   paragraphChildren.first is Markdown.Image,
                   line.length > 0 {
                    line.addAttribute(
                        .markdownImageBlock,
                        value: NSNumber(value: true),
                        range: NSRange(location: 0, length: line.length)
                    )
                }
                appendLine(line)
            } else if let code = markup as? Markdown.CodeBlock {
                appendLine(attributedPlainLine(code.code, style: Block.code))
            } else if markup is Markdown.ThematicBreak {
                appendLine(attributedPlainLine("――――――――", style: Block.rule))
            } else if let quote = markup as? Markdown.BlockQuote {
                appendQuote(quote)
            } else if let list = markup as? Markdown.UnorderedList {
                appendUnorderedList(list)
            } else if let list = markup as? Markdown.OrderedList {
                appendOrderedList(list)
            } else if let table = markup as? Markdown.Table {
                appendTable(table)
            } else if let html = markup as? Markdown.HTMLBlock {
                appendLine(attributedPlainLine(html.rawHTML, style: Block.code))
            } else {
                appendUnknownBlock(markup)
            }
        }

        private mutating func appendLine(_ line: NSAttributedString) {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(line)
        }

        private func inlineChildren(
            of markup: Markdown.Markup,
            style: String,
            level: Int? = nil,
            index: Int? = nil,
            extraAttributes: [NSAttributedString.Key: Any] = [:]
        ) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for child in markup.children {
                output.append(
                    inlineMarkup(
                        child,
                        style: style,
                        level: level,
                        index: index,
                        extraAttributes: extraAttributes
                    )
                )
            }

            if output.length == 0 {
                output.append(NSAttributedString(string: "", attributes: customAttributes(style: style, level: level, index: index)))
            }
            return output
        }

        private func inlineMarkup(
            _ markup: Markdown.Markup,
            style: String,
            level: Int?,
            index: Int?,
            inlineStyle: String? = nil,
            extraAttributes: [NSAttributedString.Key: Any] = [:]
        ) -> NSAttributedString {
            var attributes = customAttributes(style: style, level: level, index: index)
            extraAttributes.forEach { attributes[$0.key] = $0.value }
            if let inlineStyle {
                attributes[.markdownInlineStyle] = inlineStyle
            }

            if let text = markup as? Markdown.Text {
                return NSAttributedString(string: text.string, attributes: attributes)
            }
            if let code = markup as? Markdown.InlineCode {
                attributes[.markdownInlineStyle] = Inline.code
                return NSAttributedString(string: code.code, attributes: attributes)
            }
            if markup is Markdown.SoftBreak {
                return NSAttributedString(string: " ", attributes: attributes)
            }
            if markup is Markdown.LineBreak {
                return NSAttributedString(string: "\n", attributes: attributes)
            }
            if let link = markup as? Markdown.Link {
                var linkAttributes = extraAttributes
                if let destination = link.destination {
                    linkAttributes[.markdownLinkURL] = destination
                }
                return inlineContainer(
                    link,
                    style: style,
                    level: level,
                    index: index,
                    inlineStyle: Inline.link,
                    extraAttributes: linkAttributes
                )
            }
            if let image = markup as? Markdown.Image {
                let label = plainText(from: image)
                return MarkdownRichText.attributedImage(
                    source: image.source ?? "",
                    altText: label.isEmpty ? "image" : label,
                    baseURL: baseURL,
                    style: style,
                    level: level,
                    index: index,
                    extraAttributes: extraAttributes
                )
            }
            if let strong = markup as? Markdown.Strong {
                return inlineContainer(strong, style: style, level: level, index: index, inlineStyle: Inline.bold, extraAttributes: extraAttributes)
            }
            if let emphasis = markup as? Markdown.Emphasis {
                return inlineContainer(emphasis, style: style, level: level, index: index, inlineStyle: Inline.italic, extraAttributes: extraAttributes)
            }
            if let strike = markup as? Markdown.Strikethrough {
                return inlineContainer(strike, style: style, level: level, index: index, inlineStyle: Inline.strikethrough, extraAttributes: extraAttributes)
            }
            if let inlineHTML = markup as? Markdown.InlineHTML {
                return NSAttributedString(string: inlineHTML.rawHTML, attributes: attributes)
            }

            return inlineContainer(markup, style: style, level: level, index: index, inlineStyle: inlineStyle, extraAttributes: extraAttributes)
        }

        private func inlineContainer(
            _ markup: Markdown.Markup,
            style: String,
            level: Int?,
            index: Int?,
            inlineStyle: String?,
            extraAttributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for child in markup.children {
                output.append(
                    inlineMarkup(
                        child,
                        style: style,
                        level: level,
                        index: index,
                        inlineStyle: inlineStyle,
                        extraAttributes: extraAttributes
                    )
                )
            }
            return output
        }

        private mutating func appendQuote(_ quote: Markdown.BlockQuote) {
            for child in quote.children {
                if let paragraph = child as? Markdown.Paragraph {
                    appendLine(inlineChildren(of: paragraph, style: Block.quote))
                } else {
                    appendLine(attributedPlainLine(plainText(from: child), style: Block.quote))
                }
            }
        }

        private mutating func appendUnorderedList(_ list: Markdown.UnorderedList) {
            listDepth += 1
            defer { listDepth -= 1 }

            for child in list.children {
                guard let item = child as? Markdown.ListItem else { continue }
                let checkbox = item.checkbox
                let marker: String
                let taskState: String?

                switch checkbox {
                case .checked:
                    marker = "☑ "
                    taskState = "checked"
                case .unchecked:
                    marker = "☐ "
                    taskState = "unchecked"
                case .none:
                    marker = "\u{2022} "
                    taskState = nil
                }

                appendListItem(item, marker: marker, style: Block.unorderedList, index: nil, taskState: taskState)
            }
        }

        private mutating func appendOrderedList(_ list: Markdown.OrderedList) {
            listDepth += 1
            defer { listDepth -= 1 }

            var index = Int(list.startIndex)
            for child in list.children {
                guard let item = child as? Markdown.ListItem else { continue }
                appendListItem(item, marker: "\(index). ", style: Block.orderedList, index: index, taskState: nil)
                index += 1
            }
        }

        private mutating func appendListItem(
            _ item: Markdown.ListItem,
            marker: String,
            style: String,
            index: Int?,
            taskState: String?
        ) {
            let indent = String(repeating: "  ", count: max(0, listDepth - 1))
            var appendedFirstLine = false
            var extra: [NSAttributedString.Key: Any] = [:]
            if let taskState {
                extra[.markdownTaskState] = taskState
            }

            for child in item.children {
                if let paragraph = child as? Markdown.Paragraph {
                    let line = NSMutableAttributedString(
                        string: indent + marker,
                        attributes: customAttributes(style: style, index: index)
                    )
                    line.append(inlineChildren(of: paragraph, style: style, index: index, extraAttributes: extra))
                    appendLine(line)
                    appendedFirstLine = true
                } else if child is Markdown.UnorderedList || child is Markdown.OrderedList {
                    appendBlock(child)
                } else {
                    let line = NSMutableAttributedString(
                        string: indent + marker,
                        attributes: customAttributes(style: style, index: index)
                    )
                    line.append(NSAttributedString(string: plainText(from: child), attributes: customAttributes(style: style, index: index)))
                    appendLine(line)
                    appendedFirstLine = true
                }
            }

            if !appendedFirstLine {
                appendLine(NSAttributedString(string: indent + marker, attributes: customAttributes(style: style, index: index)))
            }
        }

        private mutating func appendTable(_ table: Markdown.Table) {
            let tableID = "table-\(result.length)-\(UUID().uuidString)"
            let columnCount = max(1, table.maxColumnCount)
            let bodyRows = table.body.children.compactMap { $0 as? Markdown.Table.Row }
            let rowCount = bodyRows.count + 1
            let textTable = NSTextTable()
            textTable.numberOfColumns = columnCount
            textTable.layoutAlgorithm = .automaticLayoutAlgorithm
            textTable.collapsesBorders = true
            textTable.hidesEmptyCells = false

            appendTableRow(
                table.head,
                isHeader: true,
                table: textTable,
                tableID: tableID,
                rowIndex: 0,
                columnCount: columnCount,
                rowCount: rowCount
            )

            var rowIndex = 1
            for tableRow in bodyRows {
                appendTableRow(
                    tableRow,
                    isHeader: false,
                    table: textTable,
                    tableID: tableID,
                    rowIndex: rowIndex,
                    columnCount: columnCount,
                    rowCount: rowCount
                )
                rowIndex += 1
            }
        }

        private mutating func appendTableRow(
            _ row: Markdown.Markup,
            isHeader: Bool,
            table: NSTextTable,
            tableID: String,
            rowIndex: Int,
            columnCount: Int,
            rowCount: Int
        ) {
            var columnIndex = 0
            for cell in row.children {
                guard columnIndex < columnCount else { break }
                appendTableCell(
                    cell,
                    isHeader: isHeader,
                    table: table,
                    tableID: tableID,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    columnCount: columnCount,
                    rowCount: rowCount
                )
                columnIndex += 1
            }

            while columnIndex < columnCount {
                appendTableCell(
                    nil,
                    isHeader: isHeader,
                    table: table,
                    tableID: tableID,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    columnCount: columnCount,
                    rowCount: rowCount
                )
                columnIndex += 1
            }
        }

        private mutating func appendTableCell(
            _ cell: Markdown.Markup?,
            isHeader: Bool,
            table: NSTextTable,
            tableID: String,
            rowIndex: Int,
            columnIndex: Int,
            columnCount: Int,
            rowCount: Int
        ) {
            let content: NSMutableAttributedString
            if let cell {
                content = NSMutableAttributedString(attributedString: inlineChildren(of: cell, style: Block.table))
            } else {
                content = NSMutableAttributedString(string: "")
            }

            appendLine(
                tableCellAttributedString(
                    content: content,
                    isHeader: isHeader,
                    table: table,
                    tableID: tableID,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    columnCount: columnCount,
                    rowCount: rowCount
                )
            )
        }

        private mutating func appendUnknownBlock(_ markup: Markdown.Markup) {
            let text = plainText(from: markup)
            if !text.isEmpty {
                appendLine(attributedPlainLine(text, style: Block.paragraph))
            }
        }

        private func plainText(from markup: Markdown.Markup) -> String {
            if let text = markup as? Markdown.Text { return text.string }
            if let code = markup as? Markdown.InlineCode { return code.code }
            if let code = markup as? Markdown.CodeBlock { return code.code }
            if let html = markup as? Markdown.HTMLBlock { return html.rawHTML }
            if let html = markup as? Markdown.InlineHTML { return html.rawHTML }
            if markup is Markdown.SoftBreak { return " " }
            if markup is Markdown.LineBreak { return "\n" }
            return markup.children.map { plainText(from: $0) }.joined()
        }
    }

    private static func attributedPlainLine(
        _ text: String,
        style: String,
        level: Int? = nil,
        index: Int? = nil
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: customAttributes(style: style, level: level, index: index))
    }

    private static func tableCellAttributedString(
        content: NSAttributedString,
        isHeader: Bool,
        table: NSTextTable,
        tableID: String,
        rowIndex: Int,
        columnIndex: Int,
        columnCount: Int,
        rowCount: Int
    ) -> NSAttributedString {
        let block = NSTextTableBlock(
            table: table,
            startingRow: rowIndex,
            rowSpan: 1,
            startingColumn: columnIndex,
            columnSpan: 1
        )
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        if rowIndex == 0 {
            block.setWidth(16, type: .absoluteValueType, for: .margin, edge: .minY)
        }
        if rowIndex == rowCount - 1 {
            block.setWidth(16, type: .absoluteValueType, for: .margin, edge: .maxY)
        }
        block.setBorderColor(NSColor.separatorColor.withAlphaComponent(0.48))
        if isHeader {
            block.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09)
        } else if rowIndex.isMultiple(of: 2) {
            block.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.16)
        } else {
            block.backgroundColor = NSColor.textBackgroundColor
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 0
        paragraph.textBlocks = [block]

        var attributes = customAttributes(style: Block.table)
        attributes[.paragraphStyle] = paragraph
        attributes[.font] = NSFont.systemFont(ofSize: 15, weight: isHeader ? .semibold : .regular)
        attributes[.markdownTableHeader] = NSNumber(value: isHeader)
        attributes[.markdownTableID] = tableID
        attributes[.markdownTableRow] = NSNumber(value: rowIndex)
        attributes[.markdownTableColumn] = NSNumber(value: columnIndex)
        attributes[.markdownTableColumnCount] = NSNumber(value: columnCount)

        let cell = NSMutableAttributedString(attributedString: content)
        if cell.length == 0 || cell.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSAttributedString(string: " ", attributes: attributes)
        }

        cell.addAttributes(attributes, range: NSRange(location: 0, length: cell.length))
        return cell
    }

    private static func attributedInlineLine(
        _ text: String,
        style: String,
        level: Int? = nil,
        index: Int? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let attributes = customAttributes(style: style, level: level, index: index)
        var cursor = text.startIndex

        func append(_ value: String, inline: String? = nil, link: String? = nil) {
            var segmentAttributes = attributes
            if let inline {
                segmentAttributes[.markdownInlineStyle] = inline
            }
            if let link {
                segmentAttributes[.markdownLinkURL] = link
            }
            result.append(NSAttributedString(string: value, attributes: segmentAttributes))
        }

        while cursor < text.endIndex {
            if text[cursor...].hasPrefix("**"),
               let end = text[text.index(cursor, offsetBy: 2)...].range(of: "**") {
                append(String(text[text.index(cursor, offsetBy: 2)..<end.lowerBound]), inline: Inline.bold)
                cursor = end.upperBound
            } else if text[cursor...].hasPrefix("__"),
                      let end = text[text.index(cursor, offsetBy: 2)...].range(of: "__") {
                append(String(text[text.index(cursor, offsetBy: 2)..<end.lowerBound]), inline: Inline.bold)
                cursor = end.upperBound
            } else if text[cursor] == "`",
                      let end = text[text.index(after: cursor)...].firstIndex(of: "`") {
                append(String(text[text.index(after: cursor)..<end]), inline: Inline.code)
                cursor = text.index(after: end)
            } else if text[cursor] == "[",
                      let closeBracket = text[cursor...].firstIndex(of: "]"),
                      closeBracket < text.index(before: text.endIndex),
                      text[text.index(after: closeBracket)] == "(",
                      let closeParen = text[text.index(closeBracket, offsetBy: 2)...].firstIndex(of: ")") {
                let label = String(text[text.index(after: cursor)..<closeBracket])
                let link = String(text[text.index(closeBracket, offsetBy: 2)..<closeParen])
                append(label, inline: Inline.link, link: link)
                cursor = text.index(after: closeParen)
            } else if text[cursor] == "*",
                      let end = text[text.index(after: cursor)...].firstIndex(of: "*") {
                append(String(text[text.index(after: cursor)..<end]), inline: Inline.italic)
                cursor = text.index(after: end)
            } else if text[cursor] == "_",
                      let end = text[text.index(after: cursor)...].firstIndex(of: "_") {
                append(String(text[text.index(after: cursor)..<end]), inline: Inline.italic)
                cursor = text.index(after: end)
            } else {
                append(String(text[cursor]))
                cursor = text.index(after: cursor)
            }
        }

        return result
    }

    private static func customAttributes(
        style: String,
        level: Int? = nil,
        index: Int? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.markdownBlockStyle: style]
        if let level {
            attributes[.markdownHeadingLevel] = NSNumber(value: level)
        }
        if let index {
            attributes[.markdownOrderedIndex] = NSNumber(value: index)
        }
        return attributes
    }

    private static func applyBlockAttributes(
        style: String,
        level: Int? = nil,
        index: Int? = nil,
        range: NSRange,
        storage: NSMutableAttributedString
    ) {
        guard range.location <= storage.length, range.length >= 0 else { return }
        let safeRange = NSRange(location: range.location, length: min(range.length, storage.length - range.location))
        guard safeRange.length > 0 else { return }

        storage.addAttribute(.markdownBlockStyle, value: style, range: safeRange)
        storage.removeAttribute(.markdownHeadingLevel, range: safeRange)
        storage.removeAttribute(.markdownOrderedIndex, range: safeRange)

        if let level {
            storage.addAttribute(.markdownHeadingLevel, value: NSNumber(value: level), range: safeRange)
        }
        if let index {
            storage.addAttribute(.markdownOrderedIndex, value: NSNumber(value: index), range: safeRange)
        }
    }

    private static func applyVisualAttributes(
        style: String,
        level: Int?,
        range: NSRange,
        storage: NSMutableAttributedString
    ) {
        guard range.location <= storage.length, range.length > 0 else { return }
        let safeRange = NSRange(location: range.location, length: min(range.length, storage.length - range.location))
        var attributes = typingAttributesFor(style: style, level: level)
        if style == Block.table {
            let isHeader = (storage.attribute(.markdownTableHeader, at: safeRange.location, effectiveRange: nil) as? NSNumber)?.boolValue ?? false
            attributes[.font] = NSFont.systemFont(ofSize: 15, weight: isHeader ? .semibold : .regular)
            attributes.removeValue(forKey: .paragraphStyle)
            attributes.removeValue(forKey: .backgroundColor)
        }
        attributes.removeValue(forKey: .markdownBlockStyle)
        attributes.removeValue(forKey: .markdownHeadingLevel)
        attributes.removeValue(forKey: .markdownOrderedIndex)
        storage.addAttributes(attributes, range: safeRange)

        if style == Block.unorderedList {
            let marker = visibleAnyMarkerRange(prefixes: ["\u{2022} ", "☑ ", "☐ "], in: safeRange, storage: storage)
            if marker.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.82), range: marker)
            }
        } else if style == Block.orderedList {
            let marker = visibleOrderedMarkerRange(in: safeRange, storage: storage)
            if marker.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.82), range: marker)
            }
        }
    }

    private static func applyInlineVisualAttributes(in range: NSRange, storage: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.markdownInlineStyle, in: range) { value, subrange, _ in
            guard let style = value as? String else { return }

            switch style {
            case Inline.bold:
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize(at: subrange.location, in: storage), weight: .semibold), range: subrange)
            case Inline.italic:
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize(at: subrange.location, in: storage), weight: .regular).italic(), range: subrange)
            case Inline.code:
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: NSColor.systemIndigo,
                    .backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.82)
                ], range: subrange)
            case Inline.link:
                storage.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .underlineColor: NSColor.controlAccentColor.withAlphaComponent(0.42),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: subrange)
            case Inline.strikethrough:
                storage.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ], range: subrange)
            case Inline.image:
                storage.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: fontSize(at: subrange.location, in: storage), weight: .regular).italic()
                ], range: subrange)
            default:
                break
            }
        }
    }

    private static func typingAttributesFor(
        style: String,
        level: Int? = nil,
        index: Int? = nil
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 8

        if style == Block.heading {
            let level = level ?? 1
            switch level {
            case 1:
                paragraph.paragraphSpacingBefore = 26
                paragraph.paragraphSpacing = 13
            case 2:
                paragraph.paragraphSpacingBefore = 22
                paragraph.paragraphSpacing = 11
            case 3:
                paragraph.paragraphSpacingBefore = 18
                paragraph.paragraphSpacing = 9
            default:
                paragraph.paragraphSpacingBefore = 15
                paragraph.paragraphSpacing = 7
            }
        } else if style == Block.code {
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacingBefore = 8
            paragraph.paragraphSpacing = 8
            paragraph.textBlocks = [codeTextBlock]
        } else if style == Block.rule {
            paragraph.paragraphSpacingBefore = 14
            paragraph.paragraphSpacing = 14
        }

        if style == Block.unorderedList || style == Block.orderedList {
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = 26
            paragraph.paragraphSpacing = 4
        } else if style == Block.quote {
            paragraph.lineSpacing = 6
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 9
            paragraph.textBlocks = [quoteTextBlock]
        }

        let font: NSFont
        switch style {
        case Block.heading:
            font = headingFont(level: level ?? 1)
        case Block.code:
            font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        case Block.rule:
            font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        case Block.table:
            font = NSFont.systemFont(ofSize: 15, weight: .regular)
        case Block.quote:
            font = NSFont.systemFont(ofSize: 16, weight: .regular).italic()
        default:
            font = NSFont.systemFont(ofSize: 16, weight: .regular)
        }

        let foregroundColor: NSColor
        switch style {
        case Block.quote:
            foregroundColor = NSColor.secondaryLabelColor
        case Block.rule:
            foregroundColor = NSColor.separatorColor
        default:
            foregroundColor = NSColor.labelColor
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraph,
            .markdownBlockStyle: style
        ]

        attributes[.backgroundColor] = NSColor.clear

        if let level {
            attributes[.markdownHeadingLevel] = NSNumber(value: level)
        }
        if let index {
            attributes[.markdownOrderedIndex] = NSNumber(value: index)
        }

        return attributes
    }

    private static func inlineMarkdown(from attributed: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        let nsString = attributed.string as NSString
        var result = ""

        attributed.enumerateAttributes(in: range) { attributes, subrange, _ in
            let text = nsString.substring(with: subrange)
            let inline = attributes[.markdownInlineStyle] as? String
            let escaped = text

            switch inline {
            case Inline.bold:
                result += "**\(escaped)**"
            case Inline.italic:
                result += "*\(escaped)*"
            case Inline.code:
                result += "`\(escaped)`"
            case Inline.link:
                let link = attributes[.markdownLinkURL] as? String ?? ""
                result += "[\(escaped)](\(link))"
            case Inline.strikethrough:
                result += "~~\(escaped)~~"
            case Inline.image:
                let source = attributes[.markdownLinkURL] as? String ?? ""
                let storedLabel = attributes[.markdownImageAlt] as? String
                let label = storedLabel ?? escaped.trimmingCharacters(in: CharacterSet(charactersIn: "[]\u{fffc}"))
                result += "![\(label)](\(source))"
            default:
                result += escaped
            }
        }

        return result
    }

    fileprivate static func attributedImage(
        source: String,
        altText: String,
        baseURL: URL?,
        style: String,
        level: Int? = nil,
        index: Int? = nil,
        extraAttributes: [NSAttributedString.Key: Any] = [:],
        isBlock: Bool = false
    ) -> NSAttributedString {
        var attributes = customAttributes(style: style, level: level, index: index)
        extraAttributes.forEach { attributes[$0.key] = $0.value }
        attributes[.markdownInlineStyle] = Inline.image
        attributes[.markdownLinkURL] = source
        attributes[.markdownImageAlt] = altText
        if isBlock {
            attributes[.markdownImageBlock] = NSNumber(value: true)
        }

        let result: NSMutableAttributedString
        if let attachment = MarkdownImageAttachment.make(source: source, altText: altText, baseURL: baseURL) {
            result = NSMutableAttributedString(attachment: attachment)
        } else {
            result = NSMutableAttributedString(string: "[\(altText)]")
        }
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func contentRangeWithoutLineEnding(in string: NSString, lineRange: NSRange) -> NSRange {
        var length = lineRange.length

        while length > 0 {
            let character = string.character(at: lineRange.location + length - 1)
            if character == 10 || character == 13 {
                length -= 1
            } else {
                break
            }
        }

        return NSRange(location: lineRange.location, length: length)
    }

    private static func blockStyle(in attributed: NSAttributedString, range: NSRange) -> String {
        guard attributed.length > 0, range.location < attributed.length, range.length > 0 else {
            return Block.paragraph
        }
        return attributed.attribute(.markdownBlockStyle, at: range.location, effectiveRange: nil) as? String ?? Block.paragraph
    }

    private static func headingLevel(in attributed: NSAttributedString, range: NSRange) -> Int? {
        guard attributed.length > 0, range.location < attributed.length, range.length > 0 else { return nil }
        return (attributed.attribute(.markdownHeadingLevel, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue
    }

    private static func orderedIndex(in attributed: NSAttributedString, range: NSRange) -> Int? {
        guard attributed.length > 0, range.location < attributed.length, range.length > 0 else { return nil }
        return (attributed.attribute(.markdownOrderedIndex, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue
    }

    private static func blockStyleAtInsertion(in textView: NSTextView, location: Int) -> String {
        guard let storage = textView.textStorage, storage.length > 0 else {
            return Block.paragraph
        }

        let lookup = max(0, min(location == storage.length ? location - 1 : location, storage.length - 1))
        return storage.attribute(.markdownBlockStyle, at: lookup, effectiveRange: nil) as? String ?? Block.paragraph
    }

    private static func sourceHeading(in line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func sourceUnorderedList(in line: String) -> String? {
        guard let first = line.first,
              ["-", "*", "+"].contains(first),
              line.dropFirst().first == " " else { return nil }
        return String(line.dropFirst(2))
    }

    private static func sourceOrderedList(in line: String) -> Int? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        let afterDot = line[line.index(after: dot)...]
        guard !number.isEmpty, number.allSatisfy(\.isNumber), afterDot.first == " " else { return nil }
        return Int(number)
    }

    private static func sourceOrderedListItem(in line: String) -> (index: Int, text: String)? {
        guard let index = sourceOrderedList(in: line),
              let dot = line.firstIndex(of: ".") else { return nil }
        return (index, String(line[line.index(dot, offsetBy: 2)...]))
    }

    private static func sourceQuote(in line: String) -> Bool {
        line.hasPrefix("> ")
    }

    private static func sourceQuoteText(in line: String) -> String? {
        guard sourceQuote(in: line) else { return nil }
        return String(line.dropFirst(2))
    }

    private static func sourceRule(in line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } ||
            compact.allSatisfy { $0 == "*" } ||
            compact.allSatisfy { $0 == "_" }
    }

    private static func headingFont(level: Int) -> NSFont {
        let weight: NSFont.Weight = level == 1 ? .bold : .semibold
        let base = NSFont.systemFont(ofSize: headingSize(level), weight: weight)
        guard let roundedDescriptor = base.fontDescriptor.withDesign(.rounded),
              let roundedFont = NSFont(descriptor: roundedDescriptor, size: headingSize(level)) else {
            return base
        }
        return roundedFont
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 32
        case 2: 25
        case 3: 21
        case 4: 18
        case 5: 16.5
        default: 16
        }
    }

    private static func fontSize(at location: Int, in storage: NSAttributedString) -> CGFloat {
        let style = storage.attribute(.markdownBlockStyle, at: location, effectiveRange: nil) as? String ?? Block.paragraph
        let level = (storage.attribute(.markdownHeadingLevel, at: location, effectiveRange: nil) as? NSNumber)?.intValue
        switch style {
        case Block.heading:
            return headingSize(level ?? 1)
        case Block.code:
            return 14
        case Block.table:
            return 15
        default:
            return 16
        }
    }

    private static func visibleMarkerRange(prefix: String, in range: NSRange, storage: NSAttributedString) -> NSRange {
        let nsString = storage.string as NSString
        guard range.length >= (prefix as NSString).length,
              nsString.substring(with: NSRange(location: range.location, length: (prefix as NSString).length)) == prefix else {
            return NSRange(location: range.location, length: 0)
        }
        return NSRange(location: range.location, length: (prefix as NSString).length)
    }

    private static func visibleAnyMarkerRange(prefixes: [String], in range: NSRange, storage: NSAttributedString) -> NSRange {
        for prefix in prefixes {
            let marker = visibleMarkerRange(prefix: prefix, in: range, storage: storage)
            if marker.length > 0 {
                return marker
            }
        }
        return NSRange(location: range.location, length: 0)
    }

    private static func visibleOrderedMarkerRange(in range: NSRange, storage: NSAttributedString) -> NSRange {
        let text = (storage.string as NSString).substring(with: range)
        guard let dot = text.firstIndex(of: ".") else { return NSRange(location: range.location, length: 0) }
        let number = text[..<dot]
        let afterDot = text[text.index(after: dot)...]
        guard !number.isEmpty, number.allSatisfy(\.isNumber), afterDot.first == " " else {
            return NSRange(location: range.location, length: 0)
        }
        return NSRange(location: range.location, length: number.utf16.count + 2)
    }

    private static func rangeSkippingVisibleListMarker(_ range: NSRange, in string: NSString) -> NSRange {
        for visibleMarker in ["\u{2022} ", "☑ ", "☐ "] {
            let marker = visibleMarker as NSString
            if range.length >= marker.length,
               string.substring(with: NSRange(location: range.location, length: marker.length)) == marker as String {
                return NSRange(location: range.location + marker.length, length: range.length - marker.length)
            }
        }
        return range
    }

    private static func rangeSkippingVisibleOrderedMarker(_ range: NSRange, in string: NSString) -> NSRange {
        let text = string.substring(with: range)
        guard let dot = text.firstIndex(of: ".") else { return range }
        let number = text[..<dot]
        let afterDot = text[text.index(after: dot)...]
        guard !number.isEmpty, number.allSatisfy(\.isNumber), afterDot.first == " " else { return range }
        let length = number.utf16.count + 2
        return NSRange(location: range.location + length, length: max(0, range.length - length))
    }
}

private extension NSAttributedString.Key {
    static let markdownBlockStyle = NSAttributedString.Key("MarkdownNotepad.blockStyle")
    static let markdownHeadingLevel = NSAttributedString.Key("MarkdownNotepad.headingLevel")
    static let markdownOrderedIndex = NSAttributedString.Key("MarkdownNotepad.orderedIndex")
    static let markdownInlineStyle = NSAttributedString.Key("MarkdownNotepad.inlineStyle")
    static let markdownLinkURL = NSAttributedString.Key("MarkdownNotepad.linkURL")
    static let markdownImageAlt = NSAttributedString.Key("MarkdownNotepad.imageAlt")
    static let markdownImageBlock = NSAttributedString.Key("MarkdownNotepad.imageBlock")
    static let markdownTaskState = NSAttributedString.Key("MarkdownNotepad.taskState")
    static let markdownTableHeader = NSAttributedString.Key("MarkdownNotepad.tableHeader")
    static let markdownTableID = NSAttributedString.Key("MarkdownNotepad.tableID")
    static let markdownTableRow = NSAttributedString.Key("MarkdownNotepad.tableRow")
    static let markdownTableColumn = NSAttributedString.Key("MarkdownNotepad.tableColumn")
    static let markdownTableColumnCount = NSAttributedString.Key("MarkdownNotepad.tableColumnCount")
}

private extension NSFont {
    func italic() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}

private extension NSRect {
    func distance(to point: NSPoint) -> CGFloat {
        let dx: CGFloat
        if point.x < minX {
            dx = minX - point.x
        } else if point.x > maxX {
            dx = point.x - maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < minY {
            dy = minY - point.y
        } else if point.y > maxY {
            dy = point.y - maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }
}

@MainActor
private enum MarkdownSelfTest {
    static func run() {
        testHeadingMarkdownRendersWithoutSourceMarker()
        testRenderedHeadingShortcutConsumesHashMarker()
        testSlashCommandAppliesHeadingStyle()
        testExpandedSlashCommands()
        testSlashBackspaceKeepsLiteralSlash()
        testOutlineParser()
        testLocalImageRendersAndRoundTrips()
        testInsertedImageUsesOwnParagraph()
        testStagedImagesMaterializeOnSave()
        testClipboardImageInsertion()
        testSessionTabBackwardCompatibility()
        testViewportSessionPersistence()
        testDocumentExport()
        testHeadingReturnResetsToParagraph()
        testUnorderedListReturnContinuesMarker()
        testOrderedListReturnIncrementsMarker()
        testBackspaceRemovesListMarker()
        testSuggestedSaveFilenameUsesTabTitle()
        testFullWidthLayoutToggle()
        testHeadingSpacing()
        testCommonMarkdownRoundTrip()
        testGitHubMarkdownFeaturesRender()
        testTableEditingCommands()
        testTableEditingPreservesFollowingBlocks()
        testTableFloatingControlFrame()
        testTableEdgeHoverControls()
        testSelectedTableShowsEdgeControls()
        testSelectedTableControlsAreActionable()
        print("Madedown self-test passed")
    }

    private static func testSlashCommandAppliesHeadingStyle() {
        let textView = MarkdownTextView()
        textView.string = "/"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        let heading = SlashCommand.commands.first { $0.kind == .heading(1) }!

        MarkdownRichText.applySlashCommand(heading, in: textView)
        textView.insertText("斜杠标题", replacementRange: textView.selectedRange())
        MarkdownRichText.applyDisplayStyles(to: textView)

        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == "# 斜杠标题",
            "Choosing a slash heading should create heading Markdown"
        )
    }

    private static func testExpandedSlashCommands() {
        precondition(
            SlashCommand.commands.contains(where: { $0.kind == .heading(6) }),
            "Slash commands should expose all six heading levels"
        )
        precondition(
            SlashCommand.commands.contains(where: { $0.kind == .table }) &&
                SlashCommand.commands.contains(where: { $0.kind == .taskList }) &&
                SlashCommand.commands.contains(where: { $0.kind == .strikethrough }),
            "Slash commands should cover common block and inline Markdown formats"
        )

        let cases: [(SlashCommand.Kind, String)] = [
            (.bold, "**粗体**"),
            (.taskList, "- [ ] 待办事项"),
            (.table, "| 标题 1 | 标题 2 |")
        ]
        for (kind, expectedMarkdown) in cases {
            let textView = MarkdownTextView()
            textView.string = "/"
            textView.setSelectedRange(NSRange(location: 1, length: 0))
            let command = SlashCommand.commands.first { $0.kind == kind }!
            MarkdownRichText.applySlashCommand(command, in: textView)
            let serialized = MarkdownRichText.serialize(textView.attributedString())
            precondition(serialized.contains(expectedMarkdown), "Expanded slash command should serialize as Markdown")
        }
    }

    private static func testOutlineParser() {
        let markdown = "# 一级标题\n\n```\n## 代码里的伪标题\n```\n\n###### 六级标题 ###"
        let headings = MarkdownOutlineParser.headings(in: markdown)
        precondition(headings.map(\.level) == [1, 6], "Outline should include H1-H6 and ignore fenced code")
        precondition(headings.map(\.title) == ["一级标题", "六级标题"], "Outline should clean optional closing markers")
    }

    private static func testStagedImagesMaterializeOnSave() {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("sample image.png")
        let document = root.appendingPathComponent("draft.md")
        let tabID = UUID()
        try! manager.createDirectory(at: root, withIntermediateDirectories: true)
        try! Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let insertion = try! MarkdownStore.stageImage(source, tabID: tabID)
        let stagingDirectory = URL(string: insertion.source)!.deletingLastPathComponent()
        defer {
            try? manager.removeItem(at: root)
            try? manager.removeItem(at: stagingDirectory)
        }

        let prepared = try! MarkdownStore.materializeStagedImages(
            in: insertion.markdown,
            tabID: tabID,
            documentURL: document
        )
        precondition(!prepared.contains("file://"), "Saving should replace staged absolute image URLs")
        precondition(prepared.contains("draft.assets/sample-image.png"), "Saving should create a portable relative image path")
        precondition(
            manager.fileExists(atPath: root.appendingPathComponent("draft.assets/sample-image.png").path),
            "Saving should copy staged images beside the Markdown document"
        )
    }

    private static func testClipboardImageInsertion() {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionURL = root.appendingPathComponent("session.json")
        try! manager.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("MADEDOWN_SESSION_PATH", sessionURL.path, 1)
        defer {
            unsetenv("MADEDOWN_SESSION_PATH")
            try? manager.removeItem(at: root)
        }

        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        let store = MarkdownStore()
        let textView = SourceMarkdownTextView()
        MarkdownEditorCommandCenter.shared.activate(textView)
        precondition(store.insertImages(from: pasteboard), "Image pasteboard content should be handled")
        precondition(
            textView.string.contains("![madedown-pasted-") && textView.string.contains("file://"),
            "Pasted images should be inserted immediately through the staged attachment flow"
        )
    }

    private static func testSessionTabBackwardCompatibility() {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "markdown": "# Legacy",
          "mode": "source",
          "untitledName": "未命名",
          "isDirty": false
        }
        """
        let decoded = try! JSONDecoder().decode(MarkdownDocumentTab.self, from: Data(legacyJSON.utf8))
        precondition(decoded.sourceCaretLocation == nil, "Older sessions should decode without viewport fields")
        precondition(decoded.markdown == "# Legacy", "Older session content should remain intact")
    }

    private static func testViewportSessionPersistence() {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionURL = root.appendingPathComponent("session.json")
        try! manager.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("MADEDOWN_SESSION_PATH", sessionURL.path, 1)
        defer {
            unsetenv("MADEDOWN_SESSION_PATH")
            try? manager.removeItem(at: root)
        }

        let firstStore = MarkdownStore()
        firstStore.updateViewport(
            tabID: firstStore.activeTabID,
            mode: .source,
            caretLocation: 42,
            scrollOffset: 320
        )
        firstStore.updateViewport(
            tabID: firstStore.activeTabID,
            mode: .rendered,
            caretLocation: 17,
            scrollOffset: 180
        )
        precondition(firstStore.activeTab?.isDirty == false, "Viewport changes must not mark document content dirty")
        firstStore.flushSession()

        let restoredStore = MarkdownStore()
        precondition(
            restoredStore.viewport(for: .source) == EditorViewport(caretLocation: 42, scrollOffset: 320),
            "Source viewport should survive session restoration"
        )
        precondition(
            restoredStore.viewport(for: .rendered) == EditorViewport(caretLocation: 17, scrollOffset: 180),
            "Rendered viewport should survive session restoration"
        )
    }

    private static func testDocumentExport() {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let htmlURL = root.appendingPathComponent("export.html")
        let pdfURL = root.appendingPathComponent("export.pdf")
        let imageURL = root.appendingPathComponent("image.png")
        let documentURL = root.appendingPathComponent("document.md")
        try! manager.createDirectory(at: root, withIntermediateDirectories: true)
        try! Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!.write(to: imageURL)
        defer { try? manager.removeItem(at: root) }

        let markdown = "# 导出标题\n\n正文与 **粗体**。\n\n![图片](image.png)"
        try! MarkdownExporter.writeHTML(markdown: markdown, baseURL: documentURL, to: htmlURL)
        try! MarkdownExporter.writePDF(markdown: markdown, baseURL: documentURL, to: pdfURL)
        let html = try! String(contentsOf: htmlURL, encoding: .utf8)
        let pdf = try! Data(contentsOf: pdfURL)
        precondition(html.localizedCaseInsensitiveContains("<html"), "HTML export should produce a complete document")
        precondition(html.contains("导出标题"), "HTML export should preserve document text")
        precondition(html.localizedCaseInsensitiveContains("<img"), "HTML export should preserve rendered images")
        precondition(html.contains("data:image/png;base64,"), "HTML export should embed local images for portability")
        precondition(pdf.starts(with: Data("%PDF".utf8)), "PDF export should produce a valid PDF header")
        precondition(pdf.count > 1_000, "PDF export should contain rendered document content")
    }

    private static func testSlashBackspaceKeepsLiteralSlash() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = MarkdownTextView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.insertText("/", replacementRange: textView.selectedRange())
        precondition(textView.isSlashMenuPresented, "A slash at line start should show the command menu")

        let deleteEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false,
            keyCode: 51
        )!
        textView.keyDown(with: deleteEvent)

        precondition(textView.string == "/", "Backspace should dismiss the slash menu while preserving a literal slash")
        precondition(!textView.isSlashMenuPresented, "Backspace should dismiss the slash command menu")
    }

    private static func testLocalImageRendersAndRoundTrips() {
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let documentURL = projectURL.appendingPathComponent("image-test.md")
        let source = "Assets/Logo/madedown-app-icon.png"
        let markdown = "![Madedown](\(source))"
        let textView = NSTextView()

        MarkdownRichText.load(markdown: markdown, baseURL: documentURL, into: textView)

        precondition(
            textView.attributedString().attribute(.attachment, at: 0, effectiveRange: nil) is MarkdownImageAttachment,
            "A local Markdown image should render as an image attachment"
        )
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == markdown,
            "A rendered image should serialize back to its original Markdown"
        )
    }

    private static func testInsertedImageUsesOwnParagraph() {
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let documentURL = projectURL.appendingPathComponent("image-test.md")
        let textView = MarkdownTextView()
        MarkdownRichText.load(markdown: "- Existing item", baseURL: documentURL, into: textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        MarkdownRichText.insertImage(
            ImageInsertion(altText: "Madedown", source: "Assets/Logo/madedown-app-icon.png"),
            baseURL: documentURL,
            in: textView,
            replacementRange: textView.selectedRange()
        )

        let serialized = MarkdownRichText.serialize(textView.attributedString())
        precondition(
            serialized == "- Existing item\n\n![Madedown](Assets/Logo/madedown-app-icon.png)",
            "Inserted images should use their own paragraph instead of joining the preceding list item"
        )

        let reloaded = NSTextView()
        MarkdownRichText.load(markdown: serialized, baseURL: documentURL, into: reloaded)
        precondition(
            MarkdownRichText.serialize(reloaded.attributedString()) == serialized,
            "Image block spacing should survive source/rendered round trips"
        )
    }

    private static func testSuggestedSaveFilenameUsesTabTitle() {
        var tab = MarkdownDocumentTab(untitledName: "工作记录")
        precondition(tab.suggestedSaveFilename == "工作记录.md", "Untitled save should use the tab title")

        tab.customTitle = "周报.markdown"
        precondition(tab.suggestedSaveFilename == "周报.markdown", "Existing Markdown extensions should be preserved")
    }

    private static func testHeadingMarkdownRendersWithoutSourceMarker() {
        let textView = NSTextView()
        MarkdownRichText.load(markdown: "# 大标题", into: textView)

        precondition(textView.string == "大标题", "Heading marker should be hidden in rendered editor")
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == "# 大标题",
            "Rendered heading should serialize back to Markdown"
        )
    }

    private static func testFullWidthLayoutToggle() {
        let rendered = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 1_440, height: 800))
        rendered.usesFullWidth = true
        rendered.setFrameSize(NSSize(width: 1_440, height: 800))
        let renderedFullInset = rendered.textContainerInset.width
        rendered.usesFullWidth = false
        let renderedConstrainedInset = rendered.textContainerInset.width

        precondition(renderedFullInset == 10, "Full-width rendered mode should use exactly 10pt horizontal padding")
        precondition(rendered.textContainerInset.height == 15, "Rendered mode should use exactly 15pt vertical padding")
        precondition(renderedConstrainedInset > renderedFullInset, "Constrained rendered mode should center a narrower text column")

        let source = SourceMarkdownTextView(frame: NSRect(x: 0, y: 0, width: 1_440, height: 800))
        source.usesFullWidth = true
        source.setFrameSize(NSSize(width: 1_440, height: 800))
        let sourceFullInset = source.textContainerInset.width
        source.usesFullWidth = false

        precondition(sourceFullInset == 10, "Full-width source mode should use exactly 10pt horizontal padding")
        precondition(source.textContainerInset.height == 15, "Source mode should use exactly 15pt vertical padding")
        precondition(source.textContainerInset.width > sourceFullInset, "Constrained source mode should center a narrower text column")
    }

    private static func testRenderedHeadingShortcutConsumesHashMarker() {
        let textView = NSTextView()
        textView.string = "# "
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        let typingAttributes = MarkdownRichText.consumeMarkdownShortcuts(in: textView)

        precondition(textView.string == "", "Rendered # shortcut should remove the source marker")
        precondition(typingAttributes != nil, "Rendered # shortcut should switch typing style")
        precondition(textView.selectedRange().location == 0, "Rendered # shortcut should keep caret in place")
    }

    private static func testHeadingReturnResetsToParagraph() {
        let textView = NSTextView()
        MarkdownRichText.load(markdown: "# 标题", into: textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let didReset = MarkdownRichText.insertResetLineBreakIfNeeded(
            in: textView,
            replacementRange: textView.selectedRange()
        )
        textView.insertText("正文", replacementRange: textView.selectedRange())
        MarkdownRichText.applyDisplayStyles(to: textView)

        precondition(didReset, "Return after heading should reset to paragraph")
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == """
            # 标题
            正文
            """,
            "Text after heading return should serialize as paragraph, not another heading"
        )
    }

    private static func testUnorderedListReturnContinuesMarker() {
        let textView = NSTextView()
        MarkdownRichText.load(markdown: "- 第一项", into: textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let didContinue = MarkdownRichText.insertContinuedListLineBreakIfNeeded(
            in: textView,
            replacementRange: textView.selectedRange()
        )
        textView.insertText("第二项", replacementRange: textView.selectedRange())
        MarkdownRichText.applyDisplayStyles(to: textView)

        precondition(didContinue, "Return after an unordered item should continue the list")
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == "- 第一项\n- 第二项",
            "Continued unordered item should serialize with another bullet"
        )
    }

    private static func testOrderedListReturnIncrementsMarker() {
        let textView = NSTextView()
        MarkdownRichText.load(markdown: "3. 第三项", into: textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        let didContinue = MarkdownRichText.insertContinuedListLineBreakIfNeeded(
            in: textView,
            replacementRange: textView.selectedRange()
        )
        textView.insertText("第四项", replacementRange: textView.selectedRange())
        MarkdownRichText.applyDisplayStyles(to: textView)

        precondition(didContinue, "Return after an ordered item should continue the list")
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == "3. 第三项\n4. 第四项",
            "Continued ordered item should increment its number"
        )
    }

    private static func testBackspaceRemovesListMarker() {
        let textView = NSTextView()
        MarkdownRichText.load(markdown: "- 第一项", into: textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        _ = MarkdownRichText.insertContinuedListLineBreakIfNeeded(
            in: textView,
            replacementRange: textView.selectedRange()
        )

        let markerEnd = textView.selectedRange().location
        let didRemove = MarkdownRichText.removeListMarkerIfNeeded(
            in: textView,
            replacementRange: NSRange(location: markerEnd - 1, length: 1)
        )
        MarkdownRichText.refreshTypingAttributes(in: textView)
        let typingStyleAfterExit = textView.typingAttributes[.markdownBlockStyle] as? String
        textView.insertText("普通文本", replacementRange: textView.selectedRange())
        MarkdownRichText.applyDisplayStyles(to: textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        let didContinueAfterExit = MarkdownRichText.insertContinuedListLineBreakIfNeeded(
            in: textView,
            replacementRange: textView.selectedRange()
        )

        precondition(didRemove, "Backspace after a list marker should remove the marker")
        precondition(typingStyleAfterExit == "paragraph", "Deleting a list marker should clear the inherited list typing state")
        precondition(!didContinueAfterExit, "Return after an exited list paragraph must not restart the list")
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == "- 第一项\n普通文本",
            "Text entered after deleting a marker should become a paragraph"
        )
    }

    private static func testHeadingSpacing() {
        let textView = NSTextView()
        MarkdownRichText.load(markdown: "# 标题", into: textView)
        guard let paragraph = textView.attributedString().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            preconditionFailure("Heading should have a paragraph style")
        }

        precondition(paragraph.paragraphSpacingBefore >= 16, "Heading should have visible top spacing")
        precondition(paragraph.paragraphSpacing >= 8, "Heading should have visible bottom spacing")
    }

    private static func testCommonMarkdownRoundTrip() {
        let textView = NSTextView()
        let markdown = """
        # 标题
        普通段落
        - 项目
        > 引用
        """

        MarkdownRichText.load(markdown: markdown, into: textView)

        precondition(
            textView.string == """
            标题
            普通段落
            • 项目
            引用
            """,
            "Markdown source should render as readable text"
        )
        precondition(
            MarkdownRichText.serialize(textView.attributedString()) == markdown,
            "Rendered document should serialize back to Markdown"
        )
    }

    private static func testGitHubMarkdownFeaturesRender() {
        let textView = NSTextView()
        MarkdownRichText.load(
            markdown: """
            ~~删除线~~
            - [x] 已完成
            - [ ] 未完成

            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            into: textView
        )

        precondition(textView.string.contains("删除线"), "Strikethrough text should render without tildes")
        precondition(textView.string.contains("☑ 已完成"), "Checked task list should render as a checked item")
        precondition(textView.string.contains("☐ 未完成"), "Unchecked task list should render as an unchecked item")
        let tableCellLocation = (textView.string as NSString).range(of: "A").location
        let paragraphStyle = textView.attributedString().attribute(
            .paragraphStyle,
            at: tableCellLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle
        precondition(
            paragraphStyle?.textBlocks.contains { $0 is NSTextTableBlock } == true,
            "Tables should render as native editable table cells"
        )
        let headerBlock = paragraphStyle?.textBlocks.compactMap { $0 as? NSTextTableBlock }.last
        let lastCellLocation = (textView.string as NSString).range(of: "2", options: .backwards).location
        let lastCellStyle = textView.attributedString().attribute(
            .paragraphStyle,
            at: lastCellLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle
        let lastCellBlock = lastCellStyle?.textBlocks.compactMap { $0 as? NSTextTableBlock }.last
        precondition(headerBlock?.width(for: .border, edge: .minX) == 1, "Table borders should use stable whole-point widths")
        precondition(headerBlock?.width(for: .margin, edge: .minY) ?? 0 >= 16, "Tables should have at least 16pt top spacing")
        precondition(lastCellBlock?.width(for: .margin, edge: .maxY) ?? 0 >= 16, "Tables should have at least 16pt bottom spacing")

        let markdown = MarkdownRichText.serialize(textView.attributedString())
        precondition(markdown.contains("~~删除线~~"), "Strikethrough should serialize back to Markdown")
        precondition(markdown.contains("- [x] 已完成"), "Checked task should serialize back to Markdown")
        precondition(markdown.contains("| A | B |"), "Table should serialize back to Markdown")
    }

    private static func testTableEditingCommands() {
        let textView = NSTextView()
        MarkdownRichText.load(
            markdown: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            into: textView
        )

        let oneLocation = (textView.string as NSString).range(of: "1").location
        textView.setSelectedRange(NSRange(location: oneLocation, length: 0))
        precondition(MarkdownRichText.isSelectionInTable(textView), "Cursor should be inside the table")

        MarkdownRichText.insertTableRowBelow(in: textView)
        var markdown = MarkdownRichText.serialize(textView.attributedString())
        precondition(markdown.components(separatedBy: "\n").filter { $0.hasPrefix("|") }.count == 4, "Adding a row should create another Markdown table row")

        MarkdownRichText.insertTableColumnRight(in: textView)
        markdown = MarkdownRichText.serialize(textView.attributedString())
        precondition(markdown.contains("| A |  | B |"), "Adding a column should create another Markdown table column")

        MarkdownRichText.deleteTableColumn(in: textView)
        markdown = MarkdownRichText.serialize(textView.attributedString())
        precondition(markdown.contains("| A | B |"), "Deleting a column should keep the table valid")

        MarkdownRichText.deleteTableRow(in: textView)
        markdown = MarkdownRichText.serialize(textView.attributedString())
        precondition(markdown.contains("| 1 | 2 |"), "Deleting a row should keep the original data row when an empty row is selected")
    }

    private static func testTableEditingPreservesFollowingBlocks() {
        let textView = NSTextView()
        MarkdownRichText.load(
            markdown: """
            ### 第一张表
            | A | B |
            | --- | --- |
            | 1 | 2 |
            ### 第二张表
            | C | D |
            | --- | --- |
            | 3 | 4 |
            ### 结论
            正文
            """,
            into: textView
        )

        let firstCell = (textView.string as NSString).range(of: "1").location
        textView.setSelectedRange(NSRange(location: firstCell, length: 0))
        MarkdownRichText.insertTableColumnRight(in: textView)

        let secondCell = (textView.string as NSString).range(of: "3").location
        textView.setSelectedRange(NSRange(location: secondCell, length: 0))
        MarkdownRichText.insertTableRowBelow(in: textView)

        let markdown = MarkdownRichText.serialize(textView.attributedString())
        precondition(
            markdown.contains("### 第二张表\n| C | D |"),
            "Editing one table must preserve the separator before the following table heading"
        )
        precondition(
            markdown.contains("### 结论\n正文"),
            "Editing a table must preserve the separator before the following paragraph"
        )
        precondition(
            !markdown.contains("2 | 第二张表") && !markdown.contains("4 | 结论"),
            "Following headings must never be merged into the last table cell"
        )
    }

    private static func testTableFloatingControlFrame() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        MarkdownRichText.load(
            markdown: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            into: textView
        )

        let oneLocation = (textView.string as NSString).range(of: "1").location
        textView.setSelectedRange(NSRange(location: oneLocation, length: 0))

        precondition(
            MarkdownRichText.selectedTableFrame(in: textView) != nil,
            "Table controls should be able to anchor to the selected table"
        )
    }

    private static func testTableEdgeHoverControls() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        MarkdownRichText.load(
            markdown: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            into: textView
        )

        let oneLocation = (textView.string as NSString).range(of: "1").location
        textView.setSelectedRange(NSRange(location: oneLocation, length: 0))
        guard let tableFrame = MarkdownRichText.selectedTableFrame(in: textView) else {
            preconditionFailure("Table frame should be available")
        }

        let rowHover = MarkdownRichText.tableHoverInfo(
            in: textView,
            at: NSPoint(x: tableFrame.minX - 12, y: tableFrame.midY)
        )
        precondition(rowHover?.rowHandleFrame != nil, "Hovering the row header area should expose a row selector")

        let columnHover = MarkdownRichText.tableHoverInfo(
            in: textView,
            at: NSPoint(x: tableFrame.midX, y: tableFrame.minY - 12)
        )
        precondition(columnHover?.columnHandleFrame != nil, "Hovering the column header area should expose a column selector")
    }

    private static func testSelectedTableShowsEdgeControls() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)
        MarkdownRichText.load(
            markdown: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            into: textView
        )

        let oneLocation = (textView.string as NSString).range(of: "1").location
        textView.setSelectedRange(NSRange(location: oneLocation, length: 0))
        let info = MarkdownRichText.selectedTableEdgeInfo(in: textView)

        precondition(info?.rowHandleFrame != nil, "Selected table should show a row handle without hover")
        precondition(info?.columnHandleFrame != nil, "Selected table should show a column handle without hover")
        precondition(info?.rowPlusFrame != nil, "Selected table should show a row add control without hover")
        precondition(info?.columnPlusFrame != nil, "Selected table should show a column add control without hover")
    }

    private static func testSelectedTableControlsAreActionable() {
        var markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        let binding = Binding<String>(
            get: { markdown },
            set: { markdown = $0 }
        )
        let coordinator = RenderedMarkdownEditor.Coordinator(
            RenderedMarkdownEditor(text: binding, tabID: UUID())
        )
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        textView.textContainer?.containerSize = NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude)

        coordinator.textView = textView
        MarkdownRichText.load(markdown: markdown, into: textView)

        let oneLocation = (textView.string as NSString).range(of: "1").location
        textView.setSelectedRange(NSRange(location: oneLocation, length: 0))
        coordinator.insertRowAtHover()

        let tableLines = markdown.components(separatedBy: "\n").filter { $0.hasPrefix("|") }
        precondition(tableLines.count == 4, "Visible row add control should work from selected table state")

        coordinator.insertColumnAtHover()
        precondition(
            markdown.contains("| A | B |  |") || markdown.contains("| A |  | B |"),
            "Visible column add control should work from selected table state"
        )
    }
}
