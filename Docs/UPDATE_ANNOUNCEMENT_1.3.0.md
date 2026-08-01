# Madedown 1.3.0: Smarter Pasting, Bilingual UI, and In-App Updates

**English** | [简体中文](https://github.com/zhxnix/Madedown/blob/v1.3.0/Docs/UPDATE_ANNOUNCEMENT_1.3.0.zh-CN.md)

Madedown 1.3.0 focuses on making everyday writing smoother and long-term maintenance safer. It adds smart Markdown paste, common formatting shortcuts, English/Chinese UI switching, and GitHub-powered in-place updates while tightening tables, tab restoration, dark-mode appearance, and interface consistency.

## Paste Markdown Source as Editable Rendered Content

When plain text pasted into the rendered editor looks like Markdown, Madedown asks how to handle it:

- **Convert to Markdown** turns headings, lists, quotes, code, tables, and inline formatting into editable rendered content.
- **Paste Source** preserves characters such as `#`, `**`, and `~~` verbatim.
- **Cancel** leaves the document unchanged.

Normal text and image paste keep their direct behavior, so unrelated prompts do not interrupt writing.

## Practical Formatting Shortcuts

- `⌘B` toggles bold.
- `⇧⌘X` toggles strikethrough.

Both shortcuts work in source and rendered modes. A selection is formatted directly; without a selection, Madedown inserts and selects a replaceable placeholder.

## English and Simplified Chinese, with English by Default

The interface now supports English and Simplified Chinese. Fresh installations start in English. Use the globe control in the top editor bar or the **Language** menu to switch instantly; the choice persists across relaunches without changing the document-session format.

Localization covers menus, dialogs, tabs, quick open, the outline, table controls, the slash menu, paste prompts, status text, and every updater state. Document content and filenames are never translated.

## A Cleaner Single-Row Top Bar

The Open, Save, Copy, and Image text buttons have been removed from the window. Those actions remain available through normal macOS menus and shortcuts. Document tabs now occupy that space and share one compact row with editor mode, width, window-layout, pin, and language controls.

## Safe In-Place Updates from GitHub

**Help → Check for Updates…** now does more than open a webpage. Madedown can:

1. Query the project's latest stable GitHub Release.
2. Compare it with the installed version using semantic-version rules.
3. Show the version, release notes, installer name, and download progress.
4. Prefer a DMG while also accepting a ZIP containing a complete app.
5. Validate the bundle identifier, release version, main executable, and code signature.
6. Quit after confirmation and let a standalone helper replace the app at its current path.
7. Remove the rollback copy, download, and staging directory after a successful launch—or restore and reopen the old version after failure.

Network access occurs only after a manual update check, and installers must use approved GitHub HTTPS hosts. If the destination needs elevated permission, macOS presents an administrator authorization dialog. The updater replaces the running `Madedown.app`; it neither creates a second installed copy nor searches for same-named apps in other directories.

## Stable Tables and Restored Viewports

- Table paragraph terminators retain AppKit's native table layout attributes.
- Scrolling redraws a complete, pixel-aligned grid so row and column borders stay connected.
- The overlay now uses the true native border box, eliminating the extra horizontal lines that briefly appeared inside the first and last rows.
- Each tab restores the top-visible character and its pixel offset as well as the caret, so returning to a tab shows the same reading context.
- The title-bar wordmark follows the system label color and remains legible in dark mode.
- Editor spacing is slightly wider, and tabs, containers, buttons, and the outline share a restrained 6 pt corner radius.
- Single soft line breaks survive reparsing instead of collapsing into spaces.

## Quality and Compatibility

The release remains native Swift/AppKit/SwiftUI and adds no resident background process. The update helper runs only after installation is confirmed. Automated regressions cover localization defaults and representative translations, smart paste, formatting toggles, table layout and border geometry, viewport anchors, semantic versions, installer selection, unsafe URL rejection, app validation, and transactional replacement with rollback.

Madedown continues to support macOS 13 and later. Open-source builds use ad-hoc signing and are not Apple-notarized, so macOS may still require confirmation in Privacy & Security on first launch.

## Download

Download `Madedown-1.3.0.dmg` from GitHub Releases and drag `Madedown.app` into Applications.

SHA-256: `b2e7dd7b0b127561de17d2505abde203b8b0a7ed36f9f03dc2abf8d13ef3c2fc`
