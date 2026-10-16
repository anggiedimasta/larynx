# Verse Bar: System Architecture & Binary Overview

## 1. High-Level Summary

**Verse Bar** (`com.versebar.VerseBar`) is an open-source macOS menu bar utility written in Swift that displays real-time synchronized lyrics for songs playing across native media players and web browsers.

The application operates as an un-docked accessory daemon (`LSUIElement: true`) and delivers lyrics through three distinct presentation surfaces:
1. **Menu Bar Status Item**: Live text/marquee ticker directly in the macOS menu bar.
2. **Interactive SwiftUI Popover**: Floating card providing full lyrics, album artwork, playback transport controls, and tap-to-seek functionality.
3. **Notch Island**: Dynamic island overlay window positioned over the MacBook camera notch.

---

## 2. Target Executable Specifications

* **Bundle Path**: `/Applications/Verse Bar.app`
* **Binary Path**: `/Applications/Verse Bar.app/Contents/MacOS/VerseBar`
* **Bundle Identifier**: `com.versebar.VerseBar`
* **Version**: `1.4.0` (Build `10`)
* **Minimum System Version**: macOS 11.0 (Big Sur)
* **Executable Format**: Mach-O 64-bit executable (`arm64`), little-endian
* **Executable SHA-256 Digest**: `4ae69605b4c23e2a6ac466c94234bc005c416760a5876bd73267da6247aaac69`
* **Code Signature**: Ad-hoc signed (`cdhash: 7eca8b61a87ac7f092581d88a58c8f4db85ab314`)
* **Principal Class**: `NSApplication`
* **Total Static Symbols**: 6,616 symbols (Local/internal symbols retained, demangled with Swift ABI)

---

## 3. Dynamic Framework Dependencies

Derived from Mach-O `LC_LOAD_DYLIB` load commands:

| Framework | Linkage | Purpose |
| :--- | :--- | :--- |
| `SwiftUI.framework` | Dynamic | Primary declarative UI engine (`NotchIslandView`, `PopoverView`, `SettingsView`, `OnboardingView`) |
| `AppKit.framework` | Dynamic | Window management (`NSPanel`, `NSStatusItem`, `NSPopover`, `NSHostingView`) |
| `Combine.framework` | Dynamic | Reactive property binding (`@Published`, `ObservableObject`, `AnyCancellable`) |
| `Foundation.framework` | Dynamic | Data modeling, JSON decoding, URLSession, Date/Time, File I/O, IPC |
| `UserNotifications.framework` | Dynamic | Native system notification delivery |
| `libobjc.A.dylib` | Dynamic | Objective-C runtime interoperability |
| `libswiftCore.dylib` | Dynamic | Swift standard runtime |
| `libswiftDispatch.dylib` | Dynamic | Grand Central Dispatch (`DispatchQueue`, `DispatchWorkItem`) |
| `libswiftOSLog.dylib` | Dynamic | Apple Unified Logging (`os_log`) |

---

## 4. Subsystem Topology

```
                                  ┌─────────────────────────────┐
                                  │    VerseBar.AppDelegate    │
                                  └──────────────┬──────────────┘
                                                 │
          ┌──────────────────────────────────────┼──────────────────────────────────────┐
          ▼                                      ▼                                      ▼
┌───────────────────────────┐          ┌───────────────────────────┐          ┌───────────────────────────┐
│       PlaybackEngine      │          │       LyricsService       │          │     Presentation Layer    │
├───────────────────────────┤          ├───────────────────────────┤          ├───────────────────────────┤
│ • NowPlayingService       │◄─────────┤ • Cache-First Resolver    │─────────►│ • StatusItemManager       │
│   (now_playing_helper)    │ Published│ • LRCLIB API Client       │ Published│ • PopoverHostingController│
│ • AppleScriptRunner       │   Track? │ • LRC Parser & Regex      │Lyrics/Idx│ • NotchIslandController   │
│   (Safari / Chrome / Arc) │          │ • ICU Romanization        │          │   (NSPanel Level 25)      │
│ • YTMDesktop API (:9863)  │          │ • 10Hz Sync Timer         │          │ • Settings / Onboarding   │
└───────────────────────────┘          └───────────────────────────┘          └───────────────────────────┘
```

---

## 5. Process Lifecycle

1. **Launch**: `AppDelegate.applicationDidFinishLaunching` runs on the main thread:
   * Initializes `AppSettings.shared` (reading user defaults).
   * Spawns `NowPlayingService.shared.start()`, which launches the subprocess `/usr/bin/swift now_playing_helper.swift`.
   * Starts `PlaybackEngine.shared.startPolling()`, configuring a 1.5s timer.
   * Initializes `StatusItemManager.shared`, configuring the `NSStatusItem` and popover.
   * Initializes `NotchIslandController.shared`, inspecting screen notch metrics.
   * Checks for updates asynchronously via `UpdateChecker.shared.check(manual: false)`.
   * Displays onboarding via `OnboardingController.shared.showIfNeeded()` if first run.
2. **Run Loop**: Runs `NSApplicationMain` with three active high-frequency timers:
   * **`PlaybackEngine` Polling Timer**: Every `1.5s` (detecting media playback).
   * **`LyricsService` Sync Timer**: Every `0.1s` (matching lyrics timestamps to playback).
   * **`StatusItemManager` Refresh Timer**: Every `0.5s` (updating menu bar text / marquee).
