# Madedown 1.3.3: Preserve Blank Lines and Fix List Editing

**English** | [简体中文](https://github.com/zhxnix/Madedown/blob/v1.3.3/Docs/UPDATE_ANNOUNCEMENT_1.3.3.zh-CN.md)

Madedown 1.3.3 keeps blank lines and trailing Returns intact when switching tabs, changing between source and rendered editing, saving, or reopening the application.

## Fixes

- Preserve leading blank lines, consecutive paragraph breaks, blank lines between list items, and Returns at the end of a document.
- Keep image and code-block spacing stable across repeated render/save cycles.
- Keep the caret on the newly inserted ordered-list item so repeated Returns advance the numbering without moving back to the previous item.
- Include the earlier fix for the empty ordered-list Return hang seen in 1.3.0.
- Include the 1.3.2 in-app updater fixes: dismiss the modal update window before quitting, report helper failures, and clean up mounted installers reliably.

## Installation

Download **Madedown-1.3.3.dmg** and replace `Madedown.app` in Applications. Existing document tabs and session data are retained.

If you are using **1.3.0 or 1.3.1**, install this update manually once: those versions can get stuck during **Install and Relaunch**. Versions 1.3.2 and later can use **Help → Check for Updates…**.

The download is an Apple Silicon app supporting macOS 13 or later. It is ad-hoc signed and is not Apple-notarized.

## Validation

Debug and Release self-tests passed. Native macOS window checks covered consecutive ordered-list Returns, switching tabs and editor modes, saving, and quitting/reopening while retaining the same blank lines.
