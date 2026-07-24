# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Wichtig: Dieses Projekt weicht von den Standard-Swift-Konventionen ab

Die übergeordneten `~/Projects/swift/CLAUDE.md` beschreiben SPM/XcodeGen/Fastlane/GitLab-
Registry als Standard. **ClaudeUsageBar folgt dem NICHT.** Es ist ein einzelnes
Open-Source-Repo auf **GitHub** (`Artzainnn/claudeusagebar`), das aus **einer einzigen
Swift-Datei** direkt mit `swiftc` gebaut wird. Kein Xcode-Projekt, kein SPM-Manifest,
kein Fastlane, kein XcodeGen, kein GitLab. Nicht versuchen, diese Werkzeuge einzuführen,
außer André fragt ausdrücklich danach.

## Build & Run

Alles läuft im `app/`-Verzeichnis:

```bash
cd app
./build.sh          # kompiliert Universal-Binary (arm64 + x86_64), signiert, startet die App
./create_dmg.sh     # baut DMG-Installer aus build/ClaudeUsageBar.app
```

- `build.sh` baut zwei Architektur-Binaries mit `swiftc -parse-as-library` und fügt sie
  per `lipo` zu einem Universal-Binary zusammen. Frameworks: SwiftUI, AppKit, WebKit.
  Deployment-Target: **macOS 12.0** (nicht 26.0 wie sonst üblich — die App soll breit laufen).
- Es gibt **keine Unit-Tests** und keine Test-Lane. Verifikation läuft manuell über die
  gestartete App (build.sh startet sie am Ende mit `open`).
- `make_app_icon.sh` erzeugt `ClaudeUsageBar.icns` (wird von build.sh nur bei Bedarf aufgerufen).

## Code-Signatur & Notarisierung

`build.sh` bevorzugt die **Developer-ID-Application-Identität** (auto-erkannt via
`security find-identity`, aktuell `Developer ID Application: Andre Claassen (CV66WEKNLF)`)
und signiert mit **Hardened Runtime** (`--options runtime`) + **Timestamp** — beides Pflicht
für die Notarisierung. Override per Env-Var `SIGN_IDENTITY`. Eine stabile Identität (statt
ad-hoc) ist wichtig, weil sich der Designated Requirement sonst bei jedem Build ändert und
macOS die **Bedienungshilfen-Freigabe** (Cmd+U-Hotkey via Carbon) neu anfordert.

Fallback-Kette in build.sh: Developer ID → selbstsignierte Identität `ClaudeUsageBar
Self-Signed` (dedizierter Keychain, Passwort `cub-local-signing`, via `setup_signing.sh`) →
ad-hoc (nicht notarisierbar, Freigabe muss neu erteilt werden).

**Notarisierung** läuft in `create_dmg.sh` über **`asc`** (nicht `xcrun notarytool`):
`ASC_BYPASS_KEYCHAIN=1 asc notarization submit --file … --wait`, dann `xcrun stapler staple`.
`asc` liest den App-Store-Connect-API-Key aus `~/.asc/config.json` (Keychain-Bypass, kein
Passwort-Dialog). Das Developer-ID-Zertifikat lässt sich **nicht** über die ASC-API anlegen
(nur der Account-Holder via Xcode/Portal). Ergebnis: signierte, notarisierte, gestapelte DMG
(`spctl` → „Notarized Developer ID").

## Architektur

### `app/ClaudeUsageBar.swift` — die gesamte App in einer Datei (~2300 Zeilen)

Aufbau von oben nach unten:

- **`Loc`** (Z. 15): Mini-Lokalisierung. `Loc.s("English", "Deutsch")` wählt anhand der
  Systemsprache. Jeder nutzersichtbare String läuft hierdurch — beim Ergänzen von UI immer
  beide Sprachen mitliefern.
- **`AppDelegate`** (Z. 24): Einstiegspunkt. Verwaltet `NSStatusItem` (Menüleisten-Icon),
  eine **`NSPopover`** (das Popup) und die drei Manager. Registriert Cmd+U als
  **Carbon-`EventHotKey`** (`RegisterEventHotKey`, nicht CGEvent-Tap wie in den globalen
  Swift-Regeln — dieses Projekt kam vor der Konvention). Polling-Timer: Usage + Status alle
  5 min, Update-Feed alle 3 h. Das Menüleisten-Icon wird farbcodiert neu gezeichnet
  (`updateStatusIcon`).
- **`UsageManager`** (Z. 355): Kern. Holt die Claude.ai-Nutzungsdaten über die **internen
  API-Endpunkte**, die die claude.ai-Website selbst nutzt. Auth ausschließlich über das vom
  Nutzer eingefügte **Session-Cookie** (in `UserDefaults`, Key `claude_session_cookie`). Die
  Org-ID wird dynamisch aus dem Cookie/den Endpunkten ermittelt (`fetchOrganizationId`), nichts
  ist hartkodiert. Weitere Fetches: `fetchUsage`, `fetchFreeCredits`, `fetchExtraUsage`. Sendet
  Schwellenwert-Benachrichtigungen (25/50/75/90 %) via **`NSUserNotification`** (deprecated, aber
  funktioniert ohne Permission-Prompt bei unsignierten/lokal signierten Apps).
- **`StatusManager`** (Z. 945): Pollt den Anthropic-Service-Status (statuspage.io-JSON).
  Nutzer wählt beobachtete Komponenten (`tracked_component_ids`); nur diese lösen
  Status-Benachrichtigungen aus.
- **`UpdateManager`** (Z. 1151): Prüft den Update-/Announcement-Feed (siehe `website/`).
  Zeigt In-App-Banner (`AvailableUpdate`, `Announcement`, freie `Message`-Kanäle).
- **`UsageView`**: Die SwiftUI-Oberfläche des Popups (Nutzung + Status). Misst ihre eigene
  Höhe per `ContentHeightKey`-Preference und meldet sie über `onHeightChange` zurück an den
  AppDelegate, damit die `NSPopover` korrekt dimensioniert/positioniert wird (sonst oben
  abgeschnitten). Ein Zahnrad-Button ruft `AppDelegate.openSettingsWindow()` auf.
- **`SettingsView`**: Eigenes Einstellungsfenster mit `TabView` (Tabs: Allgemein, Hinweise,
  Dienste, Kürzel), vom `AppDelegate` in einem `NSWindow` (`settingsWindow`) gehostet und
  über das Zahnrad im Popover geöffnet. Früher waren die Settings inline im Popover.
- **`PasteableTextField`** (Z. 1389): `NSViewRepresentable`, damit Cmd+V im Cookie-Feld sicher
  funktioniert.

### `website/` — statische Landing-Page + Update-Feed (auf Vercel)

- `index.html`, `blog/`, `status/`: Marketing- und SEO-Seiten für claudeusagebar.com.
- **`latest.json` / `latest-v1.json`**: der Feed, den `UpdateManager` in der App abfragt.
  Neue Versionsankündigungen, Banner-Texte und Announcement-Nachrichten werden **hier**
  gepflegt und gehen so an alle installierten Apps. `nav-status.js`/`.css` binden den
  Live-Status auf der Website ein.

## Konventionen für dieses Repo

- **Keine Gedankenstriche** (–/—) in nutzersichtbarem Text und Website-Copy; das war in
  mehreren Commits explizit Thema (z.B. `7d14a61 "Copy pass: no em dashes"`). Komma/Doppelpunkt/
  Umformulierung nutzen, Datumsspannen als „bis".
- **Zweisprachig**: jeder UI-String über `Loc.s(en, de)`.
- **Commit-Sprache**: gemischt Englisch/Deutsch im bestehenden Verlauf; neue Commits auf Deutsch
  sind okay, Code-Identifier bleiben Englisch.
- `app/build/`, `*.dmg`, `*.zip` sind gitignored (Root-`.gitignore`). Ebenso lokal gehalten:
  `NOTIFICATIONS.md` und `internal-docs/` — diese gehören nicht ins öffentliche GitHub-Repo.
