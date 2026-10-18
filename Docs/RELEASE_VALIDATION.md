# Madedown 1.3.3 Release Validation

**English** | [简体中文](RELEASE_VALIDATION.zh-CN.md)

Validated on 2026-10-18. Version: **1.3.3 (build 10)**.

## Functional checks

- Debug and Release builds and application self-tests passed.
- Consecutive ordered-list Returns keep the application responsive, leave the caret on the newest item, and produce increasing item numbers.
- Leading blank lines, repeated paragraph breaks, list-item spacing, and trailing Returns survive repeated render/save cycles.
- Image, table, heading, and code-block cases continue to pass the existing functional checks.

## Native macOS window checks

- Entered blank lines and trailing Returns in an isolated document, switched away to another tab, and returned: the same line breaks remained visible.
- Switched to source editing and back, saved the file, and compared it with the entered content: the saved text matched.
- Quit and reopened the application: the document and blank lines were restored.
- Pressed Return four times after the first ordered-list item: items 2 through 5 appeared, and typing continued in item 5 without a hang.
- Replaced the installed app with 1.3.3 and relaunched it: existing document content and the active tab were retained.

## Build environment

Built for Apple Silicon with Swift 6.4 and the installed macOS 26.5 SDK. The default macOS 27 command-line SDK on this machine lacks the SwiftUI macro plugin, so packaging used `MADEDOWN_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.

The packaging script now asks Swift for the actual executable directory and accepts `MADEDOWN_SDK_PATH`, avoiding an outdated cached binary when the build engine changes its output location.

Earlier updater validation is retained in the [1.3.2 source snapshot](https://github.com/zhxnix/Madedown/blob/71f3499/Docs/RELEASE_VALIDATION.md).
