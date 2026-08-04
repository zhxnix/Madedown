# Madedown 1.3.2 Release Validation

**English** | [简体中文](RELEASE_VALIDATION.zh-CN.md)

Validation date: 2026-08-05

## Automated Checks

- `swift build`: passed
- `swift build -c release`: passed
- `swift run Madedown --self-test`: passed
- `.build/release/Madedown --self-test`: passed
- `.build/release/Madedown --dmg-self-test dist/Madedown-1.3.2.dmg`: passed; the staged app validates and the mount directory is empty after extraction
- `swift run MadedownUpdaterHelper --self-test`: passed, including temporary signed-app validation, in-place replacement, and rollback
- `./Scripts/check_performance_budget.sh`: passed
- `plutil -lint Packaging/Info.plist dist/Madedown.app/Contents/Info.plist`: passed; app version is `1.3.2` (build `9`)
- `./Scripts/audit_open_source.sh`: passed
- Strict ad-hoc code-signature verification for the app and bundled `MadedownUpdaterHelper`: passed
- `Madedown-1.3.2.dmg` creation and checksum verification: passed
- DMG SHA-256: `c2281735de0125f347535fe3fbcdf9c91edda1333836fe10b9cd42af323978e8`
- `git diff --check`: passed

The self-test suite continues to cover headings, soft breaks, lists, quotes, code, task lists, images, HTML/PDF export, sessions, per-tab viewports, the outline, and GFM tables. It retains the 1.3.0 regressions below:

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

The 1.3.1 hotfix additionally covers:

- Scanning a marker-only ordered-list item followed by a newline terminates without changing its serialized Markdown
- Backspacing an empty ordered-list marker clears inherited list typing state
- Text and Return entered after ordered-list exit remain normal paragraphs

The 1.3.2 hotfix additionally covers:

- Installation remains in the waiting phase while the update sheet is attached
- The helper launches only after the update sheet has detached
- A failed helper reports its captured error and cleans the prepared workspace instead of leaving an endless installing state
- DMG enumeration resources are released before detachment, with normal retries and a force-detach fallback

## Real macOS UI Validation

The failure was first reproduced in the installed 1.3.0 app: after **Install and Relaunch**, the main process remained alive, the helper disappeared after its 30-second timeout, and AppKit logged `App termination blocked by modal sheet` followed by `Termination aborted`.

The fixed Release build was then exercised through a real online update in a temporary application directory. The temporary app reported version 1.3.0 while running the corrected controller, then downloaded and installed the official 1.3.1 Release asset.

- The update sheet closes before termination is requested
- The original process exits without an AppKit modal-sheet rejection
- The staged app replaces the exact temporary target path and reports version 1.3.1
- The replacement app relaunches automatically with a new process identifier
- The rollback copy is removed after successful launch verification
- Existing session content reopens unchanged; the test does not edit document content

The 1.3.1 ordered-list UI regressions were also rerun. The broader 1.3.0 interface validation remains available in the [v1.3.0 validation record](https://github.com/zhxnix/Madedown/blob/v1.3.0/Docs/RELEASE_VALIDATION.md).

- Return on a non-empty ordered item creates the next numbered item
- Return again on the empty item creates the following number without hanging; the window stays responsive
- Backspace on an empty ordered marker removes the marker and exits the list
- Text and Return entered afterward remain plain paragraphs with no automatic list marker

## Performance and Memory

Latest budget result:

- Release main executable: `3,834,696 B` (budget: `8 MiB`)
- App bundle including updater helper: `5,232 KiB` (budget: `12 MiB`)
- Startup probe: `30 ms` (budget: `750 ms`)
- Startup RSS: `16,416,768 B` (budget: `80 MiB`)

Update work starts only after a user action and adds no resident background process. The helper runs briefly only after **Install and Relaunch** is confirmed. GitHub requests and asset downloads use system `URLSession`; download tasks are released after completion. The title-bar wordmark is decoded near its display size.

These budgets detect regressions; they are not fixed measurements for every macOS version or display configuration.

## Privacy, Updates, and Repository Content

- Session files stay under `~/Library/Application Support/MarkdownNotepad/`, outside the repository
- The language choice is stored separately in local preferences and does not alter document/session schema
- GitHub is contacted only after a manual update check; document content is never sent
- Installer downloads must use approved GitHub HTTPS hosts and are staged under `~/Library/Application Support/Madedown/Updates/`
- The package is validated before the app quits; installation starts only after another explicit confirmation
- The modal update sheet must detach before the helper launches and AppKit is asked to terminate
- Helper failures are captured and presented if the original app remains alive
- The helper replaces only the running app path, removes the rollback copy after a successful launch, and restores the old version after failure
- Administrator authorization is used when needed instead of installing a second copy; same-named apps elsewhere are not scanned or deleted
- The UI test did not save changes to the user's formal documents
- `.build`, `dist`, `.DS_Store`, environment files, and common credential formats remain ignored
- GitHub-facing README, changelog, update announcement, contribution guidance, issue templates, and release validation are English-first with linked Chinese counterparts where applicable
