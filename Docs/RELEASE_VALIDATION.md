# Madedown 1.3.0 Release Validation

**English** | [简体中文](RELEASE_VALIDATION.zh-CN.md)

Validation date: 2026-08-01

## Automated Checks

- `swift build`: passed
- `swift build -c release`: passed
- `swift run Madedown --self-test`: passed
- `.build/release/Madedown --self-test`: passed
- `swift run MadedownUpdaterHelper --self-test`: passed, including temporary signed-app validation, in-place replacement, and rollback
- `./Scripts/check_performance_budget.sh`: passed
- `plutil -lint Packaging/Info.plist dist/Madedown.app/Contents/Info.plist`: passed; app version is `1.3.0` (build `7`)
- `./Scripts/audit_open_source.sh`: passed
- Strict ad-hoc code-signature verification for the app and bundled `MadedownUpdaterHelper`: passed
- `Madedown-1.3.0.dmg` creation and checksum verification: passed
- DMG SHA-256: `b2e7dd7b0b127561de17d2505abde203b8b0a7ed36f9f03dc2abf8d13ef3c2fc`
- `git diff --check`: passed

The self-test suite continues to cover headings, soft breaks, lists, quotes, code, task lists, images, HTML/PDF export, sessions, per-tab viewports, the outline, and GFM tables. The 1.3.0 regressions additionally cover:

- Markdown paste classification for headings, lists, tables, inline formatting, and ordinary-text false positives
- Converted Markdown paste retaining serializable headings and lists
- Applying and removing bold with `⌘B` and strikethrough with `⇧⌘X`
- English as the no-preference default, language persistence in an independent preferences domain, and representative English/Chinese UI and slash-command translations
- Table paragraph terminators retaining the same `NSTextTableBlock` and table identifier
- A two-column, two-row table producing three ordered vertical and horizontal grid boundaries
- The continuous overlay using the exact native table border box instead of reapplying 16 pt outer margins
- Viewport persistence using the top-visible character anchor and pixel offset, including backward-compatible session decoding
- Semantic-version ordering and stable/prerelease priority
- DMG asset preference and rejection of unsafe non-HTTPS/non-GitHub download URLs
- Updater validation of bundle identifier, version, executable, and signature; corrupted apps are rejected
- The helper's temporary transaction: old-version backup → in-place replacement → target validation → backup removal, with rollback on failure

## Real macOS UI Validation

The Release app was exercised through the real macOS interface. Test-only content stayed in temporary tabs, and the final empty test tab was removed.

- The Open, Save, Copy, and Image text buttons are absent from the window
- Document tabs occupy the former action-button area and share one 38 pt top row with mode, width, window-layout, pin, and language controls
- Horizontal tab behavior, close controls, dirty indicators, and the add-tab button remain available
- A new document in English mode is named `Untitled`
- The globe control exposes English and Simplified Chinese; switching updates menus, tab help, the outline, empty-state text, status counts, and other visible labels after the menu closes
- Switching back to English and relaunching restores English, confirming preference persistence
- Existing document titles and contents are not translated
- Repeated vertical table scrolling keeps every visible boundary connected
- The first and last table rows have exactly one outer boundary; no extra line is drawn inside either margin
- Dark-mode wordmark contrast and the shared small-radius visual language remain correct
- Existing source/rendered switching, layout controls, outline navigation, and tab session restoration remain intact

## Performance and Memory

Latest budget result:

- Release main executable: `3,810,968 B` (budget: `8 MiB`)
- App bundle including updater helper: `5,208 KiB` (budget: `12 MiB`)
- Startup probe: `20 ms` (budget: `750 ms`)
- Startup RSS: `16,777,216 B` (budget: `80 MiB`)

Update work starts only after a user action and adds no resident background process. The helper runs briefly only after **Install and Relaunch** is confirmed. GitHub requests and asset downloads use system `URLSession`; download tasks are released after completion. The title-bar wordmark is decoded near its display size.

These budgets detect regressions; they are not fixed measurements for every macOS version or display configuration.

## Privacy, Updates, and Repository Content

- Session files stay under `~/Library/Application Support/MarkdownNotepad/`, outside the repository
- The language choice is stored separately in local preferences and does not alter document/session schema
- GitHub is contacted only after a manual update check; document content is never sent
- Installer downloads must use approved GitHub HTTPS hosts and are staged under `~/Library/Application Support/Madedown/Updates/`
- The package is validated before the app quits; installation starts only after another explicit confirmation
- The helper replaces only the running app path, removes the rollback copy after a successful launch, and restores the old version after failure
- Administrator authorization is used when needed instead of installing a second copy; same-named apps elsewhere are not scanned or deleted
- The UI test did not save changes to the user's formal documents
- `.build`, `dist`, `.DS_Store`, environment files, and common credential formats remain ignored
- GitHub-facing README, changelog, update announcement, contribution guidance, issue templates, and release validation are English-first with linked Chinese counterparts where applicable
