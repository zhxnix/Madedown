# Madedown 1.3.1: Ordered-List Editing Hotfix

**English** | [简体中文](https://github.com/zhxnix/Madedown/blob/v1.3.1/Docs/UPDATE_ANNOUNCEMENT_1.3.1.zh-CN.md)

Madedown 1.3.1 is a focused stability update for ordered-list editing in the rendered editor.

## What Was Fixed

- The Markdown shortcut scanner now always advances beyond the current line after recognizing an ordered-list marker.
- A marker-only ordered item followed by a newline can no longer trap the main thread in a repeated scan.
- Backspacing an empty ordered-list marker exits to normal paragraph input.
- Text and line breaks entered after leaving the list remain paragraphs instead of silently restarting list continuation.

## Regression Coverage

Automated tests now reproduce the marker-only ordered-line scan and verify that ordered-list Backspace clears inherited list typing state. Debug and Release self-tests, the updater-helper transaction tests, performance budgets, open-source auditing, DMG mounting, and strict ad-hoc signature verification all run before publication.

Madedown continues to support macOS 13 and later. The downloadable app is ad-hoc signed and is not Apple-notarized, so macOS may require confirmation in **System Settings → Privacy & Security** on first launch.

## Download

Download `Madedown-1.3.1.dmg` from GitHub Releases and drag `Madedown.app` into Applications. Existing 1.3.0 installations can also use **Help → Check for Updates…** for validated in-place replacement.

SHA-256: `9e23b7d5c0940358c6d3bd0c3fb2c01d319edcebdb9ffc09db728db09a474e93`
