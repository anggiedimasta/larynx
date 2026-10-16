# Verse Bar: Complete Reverse Engineering Documentation Suite

This directory contains the exhaustive reverse engineering and architectural analysis of **Verse Bar** (`/Applications/Verse Bar.app`), generated using native binary disassembly, dynamic inspection, Mach-O symbol extraction, and runtime profiling.

---

## 📚 Documentation Index

| Document | Key Topics Covered |
| :--- | :--- |
| **[`prd-larynx.md`](./prd-larynx.md)** | **Product Requirements Document (PRD)** for the new native macOS app **Larynx** (Running Chords, Desktop PiP HUD, Dia Browser support, Anti-Leak resource budgets). |
| **[`architecture.md`](./architecture.md)** | Binary metadata, Mach-O load commands, dynamic frameworks, process lifecycle, and topology. |
| **[`playback-engine.md`](./playback-engine.md)** | Media player sources, NowPlaying helper subprocess, browser AppleScript injection, YTMDesktop API, and **in-depth root cause analyses of both user bugs**. |
| **[`lyrics-service.md`](./lyrics-service.md)** | LRCLIB REST client, LRC timestamp regex parser, CoreFoundation ICU transliteration (`Any-Latin`), disk cache, and 10Hz sync timer. |
| **[`ui-components.md`](./ui-components.md)** | `StatusItemManager` (menu bar ticker), `PopoverView` (SwiftUI dropdown with tap-to-seek), and `NotchIslandController` (MacBook notch overlay). |
| **[`settings-and-internals.md`](./settings-and-internals.md)** | `AppSettings` schema (13 persisted keys), `PermissionHelper` (Apple Events & Notifications), `MediaKeys` (IOKit hardware keys), `UpdateChecker`, and `Logger`. |

---

## ⚡ Quick Reference: Root Causes for User-Reported Bugs

### 1. Why Play/Pause Launches Google Chrome while Using Dia Browser
* **Root Cause**: In `VerseBar.PlaybackEngine.togglePlayPause()`, the application unconditionally executes three AppleScript blocks against `"Arc"`, `"Google Chrome"`, and `"Safari"` to toggle video playback on `music.youtube.com`.
* **The AppleScript Trap**: In macOS, calling `tell application "Google Chrome"` when Google Chrome is installed but not open **causes macOS to automatically launch Google Chrome**.
* **Browser Omission**: Verse Bar only recognizes Arc, Google Chrome, and Safari. **Dia browser is completely unhandled**. When playing in Dia, the system MediaRemote detects the track, but pressing Play/Pause fires the hardcoded browser AppleScripts, waking up Chrome.
* **Full Details & Fix**: See [**`playback-engine.md` §3**](./playback-engine.md#3-bug-analysis-1-playpause-button-launches-google-chrome).

---

### 2. Why Memory Heap Grows Continuously over 2+ Days
* **Root Cause A (Massive Disk & File Handle Churn)**: `Logger.writeToFile` appends every log line directly to disk without size limits or log rotation. On this system, `~/Library/Application Support/com.versebar.VerseBar/debug.log` had swollen to **`514 Megabytes`** from 230,000+ entries written every 1.5 seconds.
* **Root Cause B (High-Frequency Subprocess Churn)**: `AppleScriptRunner.run` spawns `/usr/bin/osascript` via `NSTask` (`Process`) every 1.5 seconds across three browsers (~120 child processes per minute, 172,800 over 2 days). This creates heavy Mach task port, file descriptor, and autorelease pool fragmentation.
* **Root Cause C (1.0s Base64 Artwork Serialization)**: `now_playing_helper.swift` serializes full raw uncompressed album artwork into base64 strings (2MB–5MB) and dumps it to stdout every single second, allocating large heap buffers continuously.
* **Root Cause D (Missing Autorelease Pools)**: The `0.1s` lyrics sync timer, `0.5s` menu bar timer, and `1.5s` polling timer lack `@autoreleasepool { ... }` wrappers, preventing thread-local Objective-C ARC objects from draining.
* **Full Details & Fixes**: See [**`playback-engine.md` §4**](./playback-engine.md#4-bug-analysis-2-unbounded-memory-heap-growth-2-days-runtime).
