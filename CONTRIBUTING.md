# Contributing to Madedown

**English** | [简体中文](CONTRIBUTING.zh-CN.md)

Thank you for helping improve Madedown.

## Before You Start

1. Search existing issues to avoid duplicate work.
2. Open an issue before a feature change to explain the goal and proposed interaction.
3. Keep each pull request focused on one clear problem.

### Language policy

- Use an English title and English-first body for new issues and pull requests.
- A complete Simplified Chinese translation is welcome inside a collapsible `<details><summary>简体中文</summary>…</details>` section.
- User-facing repository documents default to English and link to their `.zh-CN.md` counterparts.
- This policy keeps the public project accessible while preserving first-class Chinese documentation.

## Local Development

```bash
swift build
swift run Madedown --self-test
swift run Madedown
```

Also run this before submitting:

```bash
./Scripts/audit_open_source.sh
```

For UI changes, complete the relevant real-interface checks in [Release Validation](Docs/RELEASE_VALIDATION.md).

## Code Requirements

- Support macOS 13 and later.
- Prefer system frameworks and add third-party dependencies cautiously.
- Do not perform networking or sustained large-file I/O on the main thread.
- Add `--self-test` coverage for new behavior, or document the manual verification in the pull request.
- Do not commit personal documents, session files, credentials, build caches, app bundles, or DMGs.
- Keep English and Simplified Chinese user-visible strings equivalent when changing localized UI.
- Keep paired English and `.zh-CN.md` documents synchronized when changing GitHub-facing content.

## Pull Requests

Describe:

- What changed and why
- User-visible impact
- Verification commands and results
- Screenshots or a recording for UI changes

By submitting a contribution, you agree to license it under the project's MIT License.
