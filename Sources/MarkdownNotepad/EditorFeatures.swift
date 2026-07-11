import AppKit
import Foundation
import ImageIO

struct ImageInsertion: Equatable {
    let altText: String
    let source: String

    var markdown: String {
        "![\(altText)](\(source))"
    }

    static func blockSpacing(in string: NSString, replacing range: NSRange) -> (leading: String, trailing: String) {
        let leading: String
        if range.location == 0 {
            leading = ""
        } else if range.location >= 2,
                  string.character(at: range.location - 1) == 10,
                  string.character(at: range.location - 2) == 10 {
            leading = ""
        } else if string.character(at: range.location - 1) == 10 {
            leading = "\n"
        } else {
            leading = "\n\n"
        }

        let end = NSMaxRange(range)
        let trailing: String
        if end + 1 < string.length,
           string.character(at: end) == 10,
           string.character(at: end + 1) == 10 {
            trailing = ""
        } else if end < string.length, string.character(at: end) == 10 {
            trailing = "\n"
        } else {
            trailing = "\n\n"
        }
        return (leading, trailing)
    }
}

struct SlashCommand: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(Int)
        case unorderedList
        case orderedList
        case quote
        case code
        case rule
        case image
    }

    let title: String
    let detail: String
    let symbol: String
    let kind: Kind

    static let commands: [SlashCommand] = [
        SlashCommand(title: "正文", detail: "普通文本", symbol: "text.alignleft", kind: .paragraph),
        SlashCommand(title: "一级标题", detail: "# 标题", symbol: "textformat.size.larger", kind: .heading(1)),
        SlashCommand(title: "二级标题", detail: "## 标题", symbol: "textformat.size", kind: .heading(2)),
        SlashCommand(title: "三级标题", detail: "### 标题", symbol: "textformat", kind: .heading(3)),
        SlashCommand(title: "无序列表", detail: "- 列表项", symbol: "list.bullet", kind: .unorderedList),
        SlashCommand(title: "有序列表", detail: "1. 列表项", symbol: "list.number", kind: .orderedList),
        SlashCommand(title: "引用", detail: "> 引用内容", symbol: "text.quote", kind: .quote),
        SlashCommand(title: "代码块", detail: "```", symbol: "chevron.left.forwardslash.chevron.right", kind: .code),
        SlashCommand(title: "分割线", detail: "---", symbol: "minus", kind: .rule),
        SlashCommand(title: "图片", detail: "选择并直接显示", symbol: "photo", kind: .image)
    ]

    var sourceTemplate: (text: String, caretOffset: Int) {
        switch kind {
        case .paragraph:
            return ("", 0)
        case let .heading(level):
            let text = String(repeating: "#", count: level) + " "
            return (text, (text as NSString).length)
        case .unorderedList:
            return ("- ", 2)
        case .orderedList:
            return ("1. ", 3)
        case .quote:
            return ("> ", 2)
        case .code:
            return ("```\n\n```", 4)
        case .rule:
            return ("---", 3)
        case .image:
            return ("", 0)
        }
    }
}

@MainActor
final class MarkdownEditorCommandCenter {
    static let shared = MarkdownEditorCommandCenter()

    private weak var activeTextView: NSTextView?

    func activate(_ textView: NSTextView) {
        activeTextView = textView
    }

    func insertImage(_ insertion: ImageInsertion, baseURL: URL?) {
        guard let activeTextView else { return }

        if activeTextView is MarkdownTextView {
            MarkdownRichText.insertImage(
                insertion,
                baseURL: baseURL,
                in: activeTextView,
                replacementRange: activeTextView.selectedRange()
            )
        } else {
            let replacementRange = activeTextView.selectedRange()
            let string = activeTextView.string as NSString
            let spacing = ImageInsertion.blockSpacing(in: string, replacing: replacementRange)
            let block = spacing.leading + insertion.markdown + spacing.trailing
            activeTextView.insertText(block, replacementRange: replacementRange)
        }
    }
}

@MainActor
class SlashCommandTextView: NSTextView {
    var onSlashCommand: ((SlashCommand) -> Void)?
    private var slashMenuController: SlashCommandMenuController?
    var isSlashMenuPresented: Bool { slashMenuController != nil }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            MarkdownEditorCommandCenter.shared.activate(self)
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            dismissSlashMenu()
        }
        return resigned
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if slashMenuController != nil {
            dismissSlashMenu()
        }

        super.insertText(insertString, replacementRange: replacementRange)

        guard let inserted = insertString as? String,
              inserted == "/",
              slashTriggerRange() != nil else {
            return
        }
        showSlashMenu()
    }

    override func keyDown(with event: NSEvent) {
        guard let menu = slashMenuController else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 51, 117: // Delete / forward delete: close the menu and keep the slash.
            dismissSlashMenu()
        case 53: // Escape
            dismissSlashMenu()
        case 125: // Down
            menu.moveSelection(by: 1)
        case 126: // Up
            menu.moveSelection(by: -1)
        case 36, 76: // Return / keypad enter
            menu.chooseSelectedCommand()
        default:
            dismissSlashMenu()
            super.keyDown(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            dismissSlashMenu()
        }
    }

    func slashTriggerRange() -> NSRange? {
        let string = self.string as NSString
        let caret = selectedRange().location
        guard selectedRange().length == 0,
              caret > 0,
              caret <= string.length else {
            return nil
        }

        let lineRange = string.lineRange(for: NSRange(location: caret - 1, length: 0))
        let content = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard content == "/" else { return nil }
        return NSRange(location: lineRange.location, length: 1)
    }

    private func showSlashMenu() {
        guard let triggerRange = slashTriggerRange() else { return }
        let controller = SlashCommandMenuController(textView: self) { [weak self] command in
            guard let self else { return }
            self.slashMenuController = nil
            self.window?.makeFirstResponder(self)
            guard self.slashTriggerRange() == triggerRange else { return }
            self.onSlashCommand?(command)
        }
        slashMenuController = controller
        controller.show()
    }

    private func dismissSlashMenu() {
        slashMenuController?.dismiss()
        slashMenuController = nil
    }
}

@MainActor
private final class SlashCommandMenuController: NSObject {
    private weak var textView: NSTextView?
    private let panel: NSPanel
    private let buttons: [NSButton]
    private let onSelect: (SlashCommand) -> Void
    private var selectedIndex = 0

    init(textView: NSTextView, onSelect: @escaping (SlashCommand) -> Void) {
        self.textView = textView
        self.onSelect = onSelect

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        var createdButtons: [NSButton] = []
        for (index, command) in SlashCommand.commands.enumerated() {
            let button = NSButton(title: "", target: nil, action: nil)
            button.tag = index
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.alignment = .left
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title)
            button.attributedTitle = Self.buttonTitle(for: command)
            button.setButtonType(.momentaryChange)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 244).isActive = true
            button.heightAnchor.constraint(equalToConstant: 31).isActive = true
            stack.addArrangedSubview(button)
            createdButtons.append(button)
        }
        buttons = createdButtons

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 258, height: CGFloat(SlashCommand.commands.count * 33 + 14)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effectView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle]

        super.init()

        for button in buttons {
            button.target = self
            button.action = #selector(chooseCommand(_:))
        }
        updateSelectionAppearance()
    }

    func show() {
        guard let textView, let parentWindow = textView.window else { return }
        var actualRange = NSRange()
        let caretRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: &actualRange)
        let visibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: caretRect.minX, y: caretRect.minY - panel.frame.height - 4)
        origin.x = min(max(visibleFrame.minX + 8, origin.x), max(visibleFrame.minX + 8, visibleFrame.maxX - panel.frame.width - 8))
        if origin.y < visibleFrame.minY + 8 {
            origin.y = min(visibleFrame.maxY - panel.frame.height - 8, caretRect.maxY + 4)
        }
        panel.setFrameOrigin(origin)
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    func dismiss() {
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
    }

    func moveSelection(by offset: Int) {
        let count = SlashCommand.commands.count
        selectedIndex = (selectedIndex + offset + count) % count
        updateSelectionAppearance()
    }

    func chooseSelectedCommand() {
        choose(index: selectedIndex)
    }

    @objc private func chooseCommand(_ sender: NSButton) {
        choose(index: sender.tag)
    }

    private func choose(index: Int) {
        guard SlashCommand.commands.indices.contains(index) else { return }
        let command = SlashCommand.commands[index]
        dismiss()
        onSelect(command)
    }

    private func updateSelectionAppearance() {
        for (index, button) in buttons.enumerated() {
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.layer?.backgroundColor = index == selectedIndex
                ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
                : NSColor.clear.cgColor
        }
    }

    private static func buttonTitle(for command: SlashCommand) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: command.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        result.append(NSAttributedString(
            string: "   \(command.detail)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        return result
    }
}

@MainActor
final class MarkdownImageAttachment: NSTextAttachment {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func make(source: String, altText: String, baseURL: URL?) -> MarkdownImageAttachment? {
        guard let url = resolvedURL(source: source, baseURL: baseURL),
              url.isFileURL else {
            return nil
        }

        let cacheKey = url.standardizedFileURL as NSURL
        let image: NSImage
        if let cached = cache.object(forKey: cacheKey) {
            image = cached
        } else {
            guard let thumbnail = ImageThumbnailLoader.load(
                url: url,
                maximumDisplaySize: NSSize(width: 760, height: 560)
            ) else { return nil }
            image = thumbnail
            let pixelsWide = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
            let pixelsHigh = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
            let cost = max(1, pixelsWide * pixelsHigh * 4)
            cache.setObject(image, forKey: cacheKey, cost: cost)
        }

        let attachment = MarkdownImageAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        attachment.fileWrapper = nil
        return attachment
    }

    private static func resolvedURL(source: String, baseURL: URL?) -> URL? {
        let decoded = source.removingPercentEncoding ?? source
        if let url = URL(string: decoded), url.isFileURL {
            return url
        }
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded)
        }
        guard let baseURL else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: baseURL.deletingLastPathComponent()).standardizedFileURL
    }

}

@MainActor
enum ImageThumbnailLoader {
    static func load(url: URL, maximumDisplaySize: NSSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0,
              height > 0 else {
            return nil
        }

        let displayScale = min(
            1,
            maximumDisplaySize.width / width,
            maximumDisplaySize.height / height
        )
        let displaySize = NSSize(
            width: max(1, floor(width * displayScale)),
            height: max(1, floor(height * displayScale))
        )
        let maximumPixelSize = max(1, Int(ceil(max(displaySize.width, displaySize.height))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: thumbnail, size: displaySize)
    }
}
