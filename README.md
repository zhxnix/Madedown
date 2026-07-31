# Madedown

**English** | [简体中文](README.zh-CN.md)

[![CI](https://github.com/zhxnix/Madedown/actions/workflows/ci.yml/badge.svg)](https://github.com/zhxnix/Madedown/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/zhxnix/Madedown)](https://github.com/zhxnix/Madedown/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="Assets/Logo/madedown-wordmark-transparent.png" alt="Madedown" width="420">
</p>

A lightweight, free, open-source native Markdown editor for macOS. Madedown opens in an editable, live-rendered view by default and can switch to Markdown source at any time.

## Why Madedown

I missed the simple, direct, open-and-write feel of the Windows 11 text editor on macOS, but could not find a Markdown editor that was simultaneously comfortable, lightweight, and free. I handed the small tool I had in mind to AI to implement and decided to open-source the result.

> This project is coded entirely by AI; I am only the courier.

Madedown is not trying to become a knowledge base or project-management suite. It focuses on one job: open a Markdown file on your Mac and make writing pleasant.

The name is officially pronounced like the Chinese phrase **“玛德蛋”**.

## Highlights

- Native Swift, AppKit, and SwiftUI for quick startup and modest resource use
- English and Simplified Chinese UI, with English as the default and instant in-app switching
- Editable live rendering by default, with one-click Markdown source mode
- Smart Markdown paste in the rendered editor: convert pasted source into rich content or preserve it verbatim
- Multiple tabs, create/open/save/save-as workflows, and session restoration
- A compact top editor bar that combines document tabs with mode, width, window-layout, pin, and language controls
- A `/` formatting menu at the beginning of a line
  - Two-column layout with paragraphs, H1–H6, bold, italic, strikethrough, inline code, and links
  - Bulleted, numbered, and task lists; quotes; code blocks; tables; dividers; and images
  - Backspace closes the menu while preserving the literal `/`
  - Arrow-key navigation, Return to choose, and Escape to close
- A floating H1–H6 outline in the editor's upper-right corner
  - Click a heading to jump to it
  - Collapse the outline into a small button when it is not needed
- Images displayed directly in the editor
  - Insert with `⇧⌘I` or the `/` menu, drag files from Finder, or paste screenshots and copied image files
  - Images can be inserted before a document is saved and are organized on first save
  - Copies live in a `<filename>.assets` directory beside the Markdown file
  - Relative paths keep the document portable when the file and asset directory move together
- CommonMark and commonly used GitHub Flavored Markdown
  - Headings, emphasis, strikethrough, links, quotes, code, and dividers
  - Ordered, unordered, and task lists
  - Native editable tables with a continuous grid and row/column controls
- Always-on-top, left/right tiling, compact size, maximize, and full/reading-width layouts
- Native find and replace (`⌘F`) and recent-file quick open (`⌘P`)
- Common formatting shortcuts including bold (`⌘B`) and strikethrough (`⇧⌘X`)
- GitHub Releases update checks with validation, safe in-place replacement, rollback, and automatic relaunch
- Per-tab caret and viewport restoration for both source and rendered modes
- On-demand HTML and PDF export without a resident background service
- Confirmation before closing an unsaved tab

## Install and Run

### Install a release

Download the latest DMG from [GitHub Releases](https://github.com/zhxnix/Madedown/releases/latest), then drag `Madedown.app` into Applications.

After installation, choose **Help → Check for Updates…**. Madedown queries GitHub's public Releases API, compares stable versions, and can download a matching DMG or ZIP. Before installation it validates the bundle identifier, release version, main executable, and code signature.

When you choose **Install and Relaunch**, a standalone helper waits for Madedown to quit, creates a temporary rollback copy, and replaces the app at its **current path**. After the new version launches successfully, the old version, download, and staging directory are removed. A failed replacement or launch restores and reopens the previous version. If the target directory requires elevated permission, macOS shows an administrator authorization dialog instead of installing a second copy.

An in-place update touches only the currently running `Madedown.app`. It does not scan for or silently delete same-named apps elsewhere. If you previously installed multiple copies manually, keep any documents you need and remove the extras yourself; then run future updates from the copy you intend to keep.

A development process launched with `swift run Madedown` may check versions but refuses in-place replacement so it cannot overwrite `.build` or the source tree. Use the packaged app for online upgrades.

### Run from source

Requirements: macOS 13 or later and Swift 6 / Xcode 16, or a compatible toolchain.

```bash
git clone https://github.com/zhxnix/Madedown.git
cd Madedown
swift run Madedown
```

### Build an `.app`

```bash
./Scripts/build_app_bundle.sh
open dist/Madedown.app
```

### Build a DMG

```bash
./Scripts/build_dmg.sh
```

Local builds use ad-hoc signing and are not notarized with an Apple Developer certificate. On first launch, macOS may ask you to confirm the app in **System Settings → Privacy & Security**.

## Keyboard Shortcuts

| Action | Shortcut |
| --- | --- |
| New document | `⌘N` |
| Open | `⌘O` |
| Save | `⌘S` |
| Save As | `⇧⌘S` |
| Bold | `⌘B` |
| Strikethrough | `⇧⌘X` |
| Insert image | `⇧⌘I` |
| Line-start formatting menu | `/` |
| Find and replace | `⌘F` |
| Quick-open recent file | `⌘P` |

## Performance Design

Madedown aims to stay small and fast:

- Session snapshots use short-delay coalesced writes instead of writing on every keystroke
- Tab switches reuse editor instances rather than rebuilding the full text view
- Edits restyle only affected lines instead of repeatedly walking the entire document
- ImageIO decodes images near their display size, with a 32 MiB in-memory cache limit
- Relative image references avoid Base64 expansion in documents and memory
- Release builds use Swift compiler optimization
- CI enforces budgets for startup time, peak memory, executable size, and app-bundle size; see [Performance Budget](Docs/PERFORMANCE_BUDGET.md)

## Privacy and Open-Source Safety

The repository does not contain your edited content, recent files, or session data.

- Sessions stay local at `~/Library/Application Support/MarkdownNotepad/session.json`
- Build caches, apps, DMGs, `.DS_Store`, environment files, and common secret files are ignored
- Images inserted into personal documents stay beside those documents and are not copied into the source repository
- Madedown has no analytics, account system, or telemetry and does not upload document content
- Network access occurs only when you explicitly check for updates; downloads must use approved GitHub HTTPS hosts
- Update downloads and staging files live under `~/Library/Application Support/Madedown/Updates/` and are removed after a successful replacement; interrupted workspaces older than seven days are cleaned during a later update
- Run `./Scripts/audit_open_source.sh` before committing for basic secret and large-file checks

If you deliberately create Markdown documents, attachments, or credentials inside the source directory, inspect `git status` before committing. Open-source safety ultimately depends on the files actually published.

## Technology

- Swift 6
- SwiftUI + AppKit
- [swift-markdown](https://github.com/swiftlang/swift-markdown) 0.8.0, including cmark-gfm for CommonMark/GFM parsing

## Validation

```bash
swift build
swift run Madedown --self-test
swift run MadedownUpdaterHelper --self-test
./Scripts/check_performance_budget.sh
./Scripts/audit_open_source.sh
```

Automated, real-UI, and performance release checks are recorded in [Release Validation](Docs/RELEASE_VALIDATION.md).

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; report security concerns through [SECURITY.md](SECURITY.md).

## License

Madedown is available under the [MIT License](LICENSE).
