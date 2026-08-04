# Madedown 1.3.2: In-App Update Installation Hotfix

**English** | [简体中文](https://github.com/zhxnix/Madedown/blob/v1.3.2/Docs/UPDATE_ANNOUNCEMENT_1.3.2.zh-CN.md)

Madedown 1.3.2 fixes the endless spinner that could appear after choosing **Install and Relaunch** in the in-app updater.

## Important: Install This Update Manually

The defect is in the already-running 1.3.0 and 1.3.1 applications, so those versions cannot reliably install this fix from inside the app. **Do not choose Install and Relaunch for this update.** Download `Madedown-1.3.2.dmg` from GitHub Releases and replace `Madedown.app` manually once. Starting with 1.3.2, later releases can use **Help → Check for Updates…** for validated in-place replacement.

## What Was Fixed

- The update sheet is now dismissed before AppKit is asked to terminate the application.
- Installation waits until the modal sheet has fully detached before launching the helper and quitting.
- The helper process remains retained and monitored by the application.
- If the helper exits before installation completes, the updater now reports the error and removes the prepared workspace instead of spinning forever.
- DMG preparation releases its directory-enumerator resources and retries image detachment, so mounted installers no longer prevent workspace cleanup.

## Root Cause and Validation

The previous updater started its helper and immediately requested application termination while the update UI was still attached as a modal sheet. AppKit rejected the request with `App termination blocked by modal sheet`; the helper then timed out waiting for the old process, while the UI had no failure channel.

The fixed build was exercised through a real end-to-end update in a temporary directory: a patched app reporting version 1.3.0 downloaded the official 1.3.1 DMG, validated it, closed the update sheet, exited, replaced itself in place, and relaunched as 1.3.1. The AppKit log contained no modal-sheet termination rejection. A separately observed DMG-detachment failure was also corrected and covered by the final package validation.

Madedown supports macOS 13 and later. The downloadable app is ad-hoc signed and is not Apple-notarized, so macOS may require confirmation in **System Settings → Privacy & Security** on first launch.

SHA-256: `c2281735de0125f347535fe3fbcdf9c91edda1333836fe10b9cd42af323978e8`
