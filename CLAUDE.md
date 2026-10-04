# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important: this project deviates from the standard Swift conventions

The parent `~/Projects/swift/CLAUDE.md` describes SPM/XcodeGen/Fastlane/GitLab
registry as the standard. **ClaudeUsageBar does NOT follow that.** It is a single
open-source repo on **GitHub** (`Artzainnn/claudeusagebar`) built from **one single
Swift file** directly with `swiftc`. No Xcode project, no SPM manifest, no Fastlane,
no XcodeGen, no GitLab. Do not try to introduce these tools unless André explicitly
asks for it.

## Git remotes & syncing upstream

This is a fork. The remotes are named unusually:

- **`origin`** = the upstream original (`Artzainnn/ClaudeUsageBar`).
- **`fork`** = André's own fork (`AndreClaassen1/ClaudeUsageBar`).

`main` tracks **`fork/main`**, so plain `git push` / `git pull` on `main` target the
fork — no extra remote argument needed. `fork/main` is André's release line (tags
`v1.4.x`, GitHub releases with notarized DMGs live here).

To pull in changes from the upstream original, do it explicitly:

```bash
git fetch origin
git merge origin/main
```

## Build & Run

Everything runs from the `app/` directory:

```bash
cd app
./build.sh          # compiles a universal binary (arm64 + x86_64), signs it, launches the app
./create_dmg.sh     # builds a DMG installer from build/ClaudeUsageBar.app
```

- `build.sh` builds two per-architecture binaries with `swiftc -parse-as-library` and
  merges them into a universal binary via `lipo`. Frameworks: SwiftUI, AppKit, WebKit.
  Deployment target: **macOS 12.0** (not 26.0 as elsewhere — the app should run widely).
- There are **no unit tests** and no test lane. Verification is manual via the launched
  app (build.sh launches it at the end with `open`).
- **Screenshot for posts and docs:** `ClaudeUsageBar --snapshot out.png` fetches live data,
  renders the popup onto a quiet backdrop and quits (exit 0; exit 1 without data or on a write
  error). It runs next to the installed app without notifications, update banner, timers or
  hotkey. Use the installed binary: `/Applications/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar --snapshot out.png`.
- `make_app_icon.sh` generates `ClaudeUsageBar.icns` (only called by build.sh when needed).

## Code signing & notarization

`build.sh` prefers the **Developer ID Application identity** (auto-detected via
`security find-identity`, currently `Developer ID Application: Andre Claassen (CV66WEKNLF)`)
and signs with a **hardened runtime** (`--options runtime`) + **timestamp** — both required
for notarization. Override with the env var `SIGN_IDENTITY`. A stable identity (instead of
ad-hoc) matters because otherwise the designated requirement changes on every build and
macOS re-prompts for the **Accessibility permission** (Cmd+U hotkey via Carbon).

Fallback chain in build.sh: Developer ID → self-signed identity `ClaudeUsageBar
Self-Signed` (dedicated keychain, password `cub-local-signing`, via `setup_signing.sh`) →
ad-hoc (not notarizable, permission must be re-granted).

**Notarization** runs in `create_dmg.sh` via **`asc`** (not `xcrun notarytool`):
`ASC_BYPASS_KEYCHAIN=1 asc notarization submit --file … --wait`, then `xcrun stapler staple`.
`asc` reads the App Store Connect API key from `~/.asc/config.json` (keychain bypass, no
password dialog). The Developer ID certificate **cannot** be created via the ASC API (only
the Account Holder can, via Xcode/portal). Result: a signed, notarized, stapled DMG
(`spctl` → "Notarized Developer ID").

## Architecture

### `app/ClaudeUsageBar.swift` — the whole app in one file (~2400 lines)

Structure, top to bottom:

- **`Loc`**: tiny localization. `Loc.s("English", "Deutsch")` picks based on the system
  language. Every user-facing string goes through it — when adding UI, always supply both
  languages.
- **`BuildInfo`**: build metadata (version, build number, Release/Debug, build date) for the
  discreet footer at the bottom of the popup.
- **`AppDelegate`**: entry point. Manages the `NSStatusItem` (menu-bar icon), an
  **`NSPopover`** (the popup), the settings `NSWindow` (`settingsWindow`, opened via
  `openSettingsWindow()`), and the three managers. Registers Cmd+U as a **Carbon
  `EventHotKey`** (`RegisterEventHotKey`, not a CGEvent tap as in the global Swift rules —
  this project predates that convention). Polling timers: usage + status every 5 min,
  update feed every 3 h. The menu-bar icon is redrawn color-coded (`updateStatusIcon`).
- **`UsageManager`**: the core. Fetches Claude.ai usage data via the **internal API
  endpoints** the claude.ai website itself uses. Auth is solely via the user-pasted
  **session cookie** (in `UserDefaults`, key `claude_session_cookie`). The org ID is
  derived dynamically from the cookie/endpoints (`fetchOrganizationId`), nothing is
  hardcoded. Other fetches: `fetchUsage`, `fetchFreeCredits`, `fetchExtraUsage`. Sends
  threshold notifications (25/50/75/90 %) via **`NSUserNotification`** (deprecated, but
  works without a permission prompt for unsigned/locally signed apps).
- **`StatusManager`**: polls the Anthropic service status (statuspage.io JSON). The user
  selects tracked components (`tracked_component_ids`); only those trigger status
  notifications.
- **`UpdateManager`**: checks the update/announcement feed (see `website/`). Shows in-app
  banners (`AvailableUpdate`, `Announcement`, free-form `Message` channels).
- **`UsageView`**: the SwiftUI popup UI (usage + status). Measures its own height via the
  `ContentHeightKey` preference and reports it back through `onHeightChange` to the
  AppDelegate so the `NSPopover` is sized/positioned correctly (otherwise clipped at the
  top). A gear button calls `AppDelegate.openSettingsWindow()`; a red quit button calls
  `quitApp()` (the app is a menu-bar accessory, so Cmd+Q has no app menu to bind to).
- **`SettingsView`**: dedicated settings window with a `TabView` (tabs: General,
  Notifications, Services, Shortcut), hosted by the `AppDelegate` in an `NSWindow`
  (`settingsWindow`) and opened via the gear button in the popover. The settings used to be
  inline in the popover.
- **`PasteableTextField`**: `NSViewRepresentable` so Cmd+V works reliably in the cookie field.

### `website/` — static landing page + update feed (on Vercel)

- `index.html`, `blog/`, `status/`: marketing and SEO pages for claudeusagebar.com.
- **`latest.json` / `latest-v1.json`**: the feed `UpdateManager` queries in the app. New
  version announcements, banner texts, and announcement messages are maintained **here** and
  reach all installed apps. `nav-status.js`/`.css` embed the live status on the website.

## Conventions for this repo

- **Language = English** (GitHub repo): code comments, commit messages, PR/issue text, and
  script output are in English. The only intentional exception: the **German UI strings** in
  `Loc.s(en, de)` — that is the localization, not a comment. (Parent rule: `~/Projects/CLAUDE.md`,
  "Everything on GitHub is English".)
- **Bilingual UI**: every user-facing string goes through `Loc.s(en, de)`.
- **No em/en dashes** (–/—) in user-facing text and website copy; this was an explicit topic in
  several commits (e.g. `7d14a61 "Copy pass: no em dashes"`). Use comma/colon/rewording; write
  date ranges as "to".
- `app/build/`, `*.dmg`, `*.zip` are gitignored (root `.gitignore`). Also kept local only:
  `NOTIFICATIONS.md` and `internal-docs/` — these do not belong in the public GitHub repo.
