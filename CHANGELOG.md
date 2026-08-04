# Changelog

**English** | [简体中文](CHANGELOG.zh-CN.md)

This project follows the basic structure of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.3.2] - 2026-08-05

### Fixed

- The in-app updater now dismisses and waits for its modal update sheet before asking AppKit to quit, preventing **Install and Relaunch** from remaining on an endless spinner.
- The update controller retains and monitors the helper process, surfaces helper failures, and cleans the prepared workspace instead of silently timing out.
- DMG preparation now releases directory-enumerator resources and retries detachment, preventing installer images and update workspaces from remaining mounted after preparation.

## [1.3.1] - 2026-08-05

### Fixed

- Prevented the rendered editor from hanging when its Markdown shortcut scanner revisited an empty ordered-list item followed by a newline.
- Backspacing an empty ordered-list marker now reliably exits to paragraph input; subsequent typing and Return do not restart the list.

## [1.3.0] - 2026-08-02

### Added

- The rendered editor now offers **Convert to Markdown**, **Paste Source**, and **Cancel** when pasted text looks like Markdown source.
- Added bold (`⌘B`) and strikethrough (`⇧⌘X`) shortcuts in both source and rendered modes.
- **Check for Updates** connects to GitHub Releases, compares stable versions, shows release notes and download progress, and prepares a validated macOS app for in-place replacement.
- Added a standalone update helper with quit-time replacement, launch verification, rollback, administrator authorization, and temporary-file cleanup.
- Added English and Simplified Chinese UI localization. Fresh installations default to English, and the selected language persists locally.

### Changed

- Increased the editor's horizontal safe spacing slightly and standardized tabs, content containers, buttons, and the floating outline on a 6 pt small-radius visual language.
- Removed all Open, Save, Copy, and Image text buttons from the window. Document tabs now share the compact top editor bar with the remaining icon controls.
- Tightened the floating outline's dimensions, spacing, and hierarchy to reduce document obstruction.
- Online updates no longer open a DMG for another drag-install step; confirmation replaces the currently running app at its existing path.
- GitHub-facing documentation is English-first, with complete linked Simplified Chinese versions. Future issues use English titles and English-first bodies.

### Fixed

- Table paragraph terminators retain native table layout attributes so adjacent borders remain connected after layout, resizing, or editing.
- Tables redraw a complete pixel-aligned row/column grid during scrolling, preventing horizontal and vertical borders from breaking into segments.
- The continuous table overlay now uses AppKit's native border box directly, preventing duplicate horizontal lines inside the first and last rows while preserving outer spacing.
- Tab switching restores a top-visible character anchor plus its pixel offset, keeping the same text in view as well as the caret.
- The title-bar wordmark uses a template tint that follows the system label color and remains visible in dark mode.
- A single soft line break inside a paragraph is no longer collapsed into a space after reparsing.

## [1.2.1] - 2026-07-11

### Changed

- Moved the floating heading outline to the editor's upper-right corner and used a lighter, more transparent background.
- Every cold app launch now starts in rendered mode instead of restoring source mode from the previous session.

## [1.2.0] - 2026-07-11

### Added

- Added a floating H1–H6 outline with click-to-jump and collapse controls.
- Expanded the `/` menu to H1–H6, common inline formats, task lists, and tables in a two-column layout.
- Allowed images to be inserted before a document is saved and migrated them to a relative asset directory on first save.
- Added image drag-and-drop from Finder plus pasted screenshots and copied image files.
- Added native find/replace, `⌘P` recent-file quick open, and HTML/PDF export.
- Saved caret and scroll positions separately for source and rendered modes in each tab.
- Added startup-time, memory, executable-size, and app-bundle performance budgets.

### Changed

- Reused editor instances and removed transition animations during tab switches.
- Clarified in the README that the implementation is AI-coded.
- Added CI performance-budget gates while keeping all new features free of additional third-party dependencies.

## [1.1.0] - 2026-07-11

### Added

- Added a line-start `/` Markdown formatting menu with keyboard and mouse support.
- Backspace closes the `/` menu while preserving a literal slash.
- Added local image insertion, asset-directory management, and direct display in the rendered editor.
- Added the open-source license, contribution guide, security policy, CI, and sensitive-file audit script.

### Changed

- Coalesced session snapshot writes to reduce disk I/O during continuous input.
- Limited style refreshes to affected lines.
- Added count and memory limits to the image cache.
- Removed personalized copy from the About panel.
