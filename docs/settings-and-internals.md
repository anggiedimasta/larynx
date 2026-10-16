# AppSettings & Supporting Internals

This document covers user preferences, system permissions, hardware media key synthesis, software updates, and logging.

---

## 1. User Preferences: `VerseBar.AppSettings`

`VerseBar.AppSettings` is a singleton class conforming to `Combine.ObservableObject`. Every property uses a custom `@Published` property wrapper backed by macOS `UserDefaults.standard`.

### Persisted Settings Schema

| Property Name | UserDefaults Key | Type | Description |
| :--- | :--- | :--- | :--- |
| `showArtist` | `showArtist` | `Bool` | Displays the artist name in the menu bar text item |
| `showTitle` | `showTitle` | `Bool` | Displays the track title in the menu bar text item |
| `showLyrics` | `showLyrics` | `Bool` | Displays the current active lyric line in the menu bar |
| `launchAtLogin` | `launchAtLogin` | `Bool` | Registers app as a Login Item via `SMAppService` / ServiceManagement |
| `trackingSafari` | `trackingSafari` | `Bool` | Enables polling and AppleScript query for Safari tabs |
| `trackingChrome` | `trackingChrome` | `Bool` | Enables polling and AppleScript query for Google Chrome tabs |
| `trackingArc` | `trackingArc` | `Bool` | Enables polling and AppleScript query for Arc browser tabs |
| `trackingYTMDesktop` | `trackingYTMDesktop` | `Bool` | Enables polling local port 9863 for YouTube Music Desktop App |
| `manualSyncOffset` | `manualSyncOffset` | `Double` | Time offset (in seconds) added to lyrics sync math (e.g. `+0.5s`, `-0.2s`) |
| `pinPopover` | `pinPopover` | `Bool` | When true, popover remains open even when clicking outside |
| `showNotchIsland` | `showNotchIsland` | `Bool` | Enables the Dynamic Island overlay under the MacBook camera notch |
| `hasCompletedOnboarding` | `hasCompletedOnboarding` | `Bool` | Tracks whether initial setup wizard has been viewed |
| `showRomanization` | `showRomanization` | `Bool` | Displays romanized transliteration beneath Japanese/Korean/Chinese lyrics |

---

## 2. Permissions Engine: `VerseBar.PermissionHelper`

Verse Bar requires two primary macOS system permissions:

### A. Automation Permissions (`Privacy_Automation`)
* **Purpose**: Allows Verse Bar to send Apple Events to Google Chrome, Safari, and Arc to inspect web tabs.
* **Probing**: Tests an Apple Event probe against the target bundle ID:
  ```swift
  PermissionHelper.probeAutomation(for: bundleId) { status in ... }
  ```
* **Status Enum (`VerseBar.PermissionStatus`)**:
  * `.granted`
  * `.denied`
  * `.notDetermined`
  * `.unknown`
* **Deep Links**: When denied, prompts the user and opens System Settings:
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`

---

### B. Notification Permissions (`UserNotifications`)
* **Purpose**: Displays system alerts when updates are available or playback changes.
* **Probing**: Calls `UNUserNotificationCenter.current().getNotificationSettings`.
* **Deep Links**: Opens System Settings notification pane:
  `x-apple.systempreferences:com.apple.preference.notifications`

---

### C. Installation Path Validation (`isInApplicationsFolder`)
* Checks if `Bundle.main.bundleURL` resides within `/Applications` or `~/Applications`.
* If not, the onboarding flow urges the user to move the app bundle to prevent macOS App Translocation (quarantine translocation breaks helper subprocess path resolution).

---

## 3. Hardware Media Keys: `VerseBar.MediaKeys`

Instead of relying solely on browser extensions or standard shortcuts, `VerseBar.MediaKeys` posts synthetic hardware media events directly into the macOS window server.

* **Mechanism**: Invokes IOKit / AppKit system-defined events:
  ```swift
  MediaKeys.send(key: Int32) // Keydown (0xa00) immediately followed by Keyup (0xb00)
  ```
* **Hardware Key Identifiers**:
  * `play`: Key code for Play/Pause (`NX_KEYTYPE_PLAY = 16`)
  * `next`: Key code for Next Track (`NX_KEYTYPE_NEXT = 17`)
  * `previous`: Key code for Previous Track (`NX_KEYTYPE_PREVIOUS = 18`)
* **Benefit**: Allows Verse Bar to toggle playback in native desktop apps (Spotify, Apple Music, Swinsian) without AppleScript or direct API integration.

---

## 4. Software Updates: `VerseBar.UpdateChecker`

* **Singleton**: `UpdateChecker.shared`.
* **API Endpoint**:
  `https://api.github.com/repos/alvinindra/verse-bar/releases/latest`
* **Web Release Page**:
  `https://github.com/alvinindra/verse-bar/releases/latest`
* **State Machine (`UpdateChecker.State`)**:
  * `.idle`: No check in progress.
  * `.checking`: Network request in flight.
  * `.upToDate`: Current version matches or exceeds latest release tag.
  * `.updateAvailable`: Newer release tag discovered on GitHub.
  * `.failed`: Network error or rate-limiting.
* **Execution**: Automatically checks once upon launch (`applicationDidFinishLaunching`), and can be manually re-triggered from the Menu Bar dropdown context menu.

---

## 5. Logging Subsystem: `VerseBar.Logger`

* **Unified Log Subsystems (`OSLog`)**:
  * `generalLog`: General app lifecycle events.
  * `playbackLog`: Source polling and track identification.
  * `lyricsLog`: LRCLIB network fetches and sync timing.
* **File Logging (`debug.log`)**:
  * Written to: `~/Library/Application Support/com.versebar.VerseBar/debug.log`
  * Every log line triggers `FileHandle(forWritingTo:)`, writes timestamped formatted strings, and closes the handle.
  * **Critical Note**: There is no automatic file size cap or log rotation. In active long-term use, this file grows to several hundred megabytes.
