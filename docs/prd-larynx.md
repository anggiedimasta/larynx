# Product Requirements Document (PRD): Larynx

**Project Name**: Larynx  
**Target Platform**: macOS 13.0+ (Ventura, Sonoma, Sequoia, Apple Silicon & Intel)  
**Architecture**: Pure Native macOS (Swift 6, SwiftUI, AppKit Bridge, `@Observable` macro)  
**Status**: Approved Specification  

---

## 1. Executive Summary & Vision

**Larynx** is a next-generation, ultra-lightweight macOS media companion designed to display synchronized lyrics and **real-time running musical chords** across customizable presentation surfaces.

Born from a rigorous reverse-engineering audit of Verse Bar, Larynx solves the critical architectural flaws of predecessor apps—eliminating memory heap accumulation, subprocess churn, unconstrained disk logging, and accidental browser launches—while introducing a standout feature for musicians and music enthusiasts: **synchronized running chords with real-time key transposition and capo adjustment**.

---

## 2. Core Pillars & Architecture

```
                                      ┌────────────────────────┐
                                      │      LarynxApp         │
                                      └───────────┬────────────┘
                                                  │
          ┌───────────────────────────────────────┼───────────────────────────────────────┐
          ▼                                       ▼                                       ▼
┌───────────────────────────┐           ┌───────────────────────────┐           ┌───────────────────────────┐
│     PlaybackEngine        │           │   Lyrics & Chords Engine  │           │    Presentation Engine    │
├───────────────────────────┤           ├───────────────────────────┤           ├───────────────────────────┤
│ • Native System Media     │           │ • LRCLIB API Client       │           │ • Menu Bar Ticker         │
│   (MediaRemote / MR)      │           │ • Online Chords Provider  │           │   (Dual-line Lyric+Chord) │
│ • Hybrid Browser Manager  │──────────►│   (Auto-Fetch & Transpose)│──────────►│ • MacBook Notch Island    │
│   - Smart AppleScript     │ TrackState│ • High-Precision LRC      │ Active    │   (NSPanel Level 25)      │
│   - Running-Process Guard │           │ • CJK Romanization        │ Line/Chord│ • Floating Desktop HUD    │
│   - Dia / Arc / Chrome    │           │ • Smart 10Hz Timer        │           │   (Draggable, Glass Pip)  │
│ • Local WebSocket Server  │           │   (Paused on Idle/Sleep)  │           │                           │
└───────────────────────────┘           └───────────────────────────┘           └───────────────────────────┘
```

---

## 3. Detailed Functional Specifications

### A. Presentation Surfaces (Three Active Modes)

#### 1. Menu Bar Ticker
* Resides in the macOS system status bar (`NSStatusItem`).
* **Dual-Line / Compact Marquee**:
  * Line 1: Currently active synchronized lyric line with smooth horizontal marquee scrolling.
  * Line 2 (Optional / Toggleable): **Running Chord Progression** aligned with playback time.
* **Streamlined Interaction (No Heavy Dropdown Popover)**:
  * Left-click: Toggles the Floating Desktop HUD on/off.
  * Right-click / Context Menu: Minimal native menu (`Toggle Desktop HUD`, `Toggle Chords`, `Key Transpose...`, `Preferences...`, `Quit`).

#### 2. MacBook Notch Island Overlay
* Floating borderless `NSPanel` pinned at window level 25 (`NSWindow.Level.statusBar`).
* Dynamically detects MacBook camera notch geometry using `NSScreen.safeAreaInsets` and auxiliary rects.
* **Artwork-Free & Ultra-Fast**: Completely omits album artwork decoding/rendering to maximize responsiveness and achieve a negligible memory footprint (<20MB).
* **Compact State** ($30\text{ pt}$ body height): Ticker hugging the physical notch.
* **Expanded State** ($96\text{ pt}$ body height): Revealed on hover ($0.18\text{s}$ debounce) featuring track title, artist, transport controls (Prev, Play/Pause, Next), active lyric verse, and chord badges.

#### 3. Floating Desktop HUD (Picture-in-Picture Mode)
* **Window Level**: `NSWindow.Level.floating` (floats persistently above active windows, code editors, and browsers).
* **Draggable & Snappable**: Snaps cleanly to display edges and corners.
* **Resizable & Customizable**: Adjustable font size, background glassmorphic blur, and opacity slider ($20\% - 100\%$).
* **Dual-Line Layout**: Prominently displays the current lyric line on top and the current running chord underneath.
---

### B. Killer Feature: Running Chords Engine

Larynx introduces real-time musical chord progression display synchronized with song playback.

1. **Online Chords Provider (Auto-Fetch)**:
   * Queries online chord repositories (Ultimate Guitar / Songsterr / Cifra abstractions) by track artist and title.
2. **Fuzzy Lyric-to-Chord Alignment Engine (Similarity Index)**:
   * **Challenge**: LRCLIB lyrics have millisecond timestamps, while online chord sheets only provide chords placed above plain text lines.
   * **Algorithm**:
     1. **Line Matching via Similarity Index**: Computes normalized Token/Levenshtein similarity between chord-sheet lyric lines and LRCLIB timestamped lines to map chords to their corresponding timecodes.
     2. **Word/Character Offset Interpolation**: Chords positioned over specific words within a line are assigned an interpolated timestamp proportional to the word's position in that lyric line.
     3. **Instrumental Sections**: Sections without lyrics (e.g. `[Intro]`, `[Solo]`, `[Outro]`) are displayed as progression badges (`[Solo: Am - F - C - G]`).
3. **Dedicated Sub-Line Rendering**:
   * Rendered directly below the lyric text across all supported surfaces:
     ```
     Lyric:  "No, I don't want no scrub, a scrub is a guy that can't get no love from me"
     Chord:  [ Am7 ]                     [ Dm7 ]                 [ Em7 ]
     ```
   * Can be independently toggled on or off via hotkey or preferences.
4. **Key Transpose & Capo Helper**:
   * Musician-friendly pitch shifting: Semitone adjustment controls ($+1, -1, \dots, +12, -12$).
   * Capo position selector ($1 - 7$) that automatically calculates transposed chord fingerings.
---

### C. Media Source Detection & Playback Engine

#### 1. Native macOS System NowPlaying (Optimized Helper)
* Universal tracking for native music applications (Spotify, Apple Music, Swinsian, Cog, Doppler) via `MediaRemote` integration.
* **Artwork Stripped Out**: The helper subprocess emits only text metadata (`title`, `artist`, `duration`, `elapsed`, `isPlaying`). Raw image serialization/base64 streaming is completely removed, eliminating the single largest memory leak vector from Verse Bar.

#### 2. Generic Chromium Browser Engine (Dia, Arc, Chrome, Brave, etc.)
* **Dynamic Process Discovery**: Rather than hardcoding browser scripts, Larynx inspects `NSWorkspace.shared.runningApplications` for all known Chromium and WebKit bundle identifiers:
  * **Dia Browser**: `company.thebrowser.dia`
  * **Arc Browser**: `company.thebrowser.Arc`
  * **Google Chrome**: `com.google.Chrome`
  * **Brave Browser**: `com.brave.Browser`
  * **Safari**: `com.apple.Safari`
  * **Microsoft Edge**: `com.microsoft.edgemac`
* **Strict Running-Process Guard**: Only actively running browsers with matching tabs are scripted. **Never executes AppleScript targeting a closed browser, completely eliminating unwanted browser launches**.
* **Optional Local Companion WebSocket**:
  * Lightweight loopback WebSocket listener (`127.0.0.1:port`) for browser extensions, enabling zero-latency syncing with zero Apple Event permission dialogs.

### D. Lyrics & Synchronization Engine

1. **Remote Provider & Local Cache**:
   * Primary resolver: LRCLIB API (`GET /api/get` exact query, `GET /api/search` fallback).
   * Local LRU cache on disk (`~/Library/Caches/com.larynx.Larynx/LyricsCache/`).
2. **Accurate CJK Romanization**:
   * Detects Japanese, Korean, and Chinese scripts.
   * Employs CoreFoundation ICU transform (`Any-Latin` + diacritic stripping) with enhanced script-specific phonetic mapping (Hepburn Romaji, Pinyin, Revised Romanization).
3. **Smart Power-Saving Sync Timer**:
   * Runs at $10\text{ Hz}$ ($100\text{ ms}$) precision **only while media is playing**.
   * Automatically suspended when playback is paused, screen is locked, or system goes to sleep.

---

## 4. Performance, Memory & Resource Budgets

Larynx strictly enforces four data governance rules to prevent memory bloat and disk leaks:

| Parameter | Budget / Constraint | Enforcement Mechanism |
| :--- | :--- | :--- |
| **Resident Memory (RAM)** | $\le 35\text{ MB}$ typical ($\le 60\text{ MB}$ peak) | Swift 6 `@Observable` actors, no memory-leaking Combine pipelines |
| **Binary Footprint** | $\le 10\text{ MB}$ | Zero Electron/Node runtime; 100% native compiled Swift Mach-O |
| **Disk Logging Limit** | Max $5\text{ MB}$ total | Single rolling backup (`larynx.log` + `larynx.log.1`), rotation on overflow |
| **Disk Cache Quota** | Max $100\text{ MB}$ LRU | Automatic pruning of oldest cache files when quota is exceeded |
| **CPU Usage (Active)** | $< 1.5\%$ on Apple Silicon | Throttled timer ticks, hardware ProMotion Pro frame synchronization |
| **CPU Usage (Idle)** | $0.0\%$ | Timers invalidated immediately upon pause or lock screen |
| **Subprocess Spawning** | $0$ spawned per minute | In-process Apple Events / WebSockets; zero `NSTask("/bin/osascript")` |
| **Artwork Serialization** | On-change only | Artwork cached by unique hash; no 1.0s base64 streaming |

---

## 5. Technical Implementation Roadmap

### Phase 1: Core Engine & Data Governance
* [ ] Initialize Swift 6 package with macOS 13+ deployment target.
* [ ] Implement `PlaybackEngine` with `NSRunningApplication` guards and Dia/Arc/Chrome bundle detection.
* [ ] Implement `NowPlayingService` with on-change artwork hashing and `@autoreleasepool` protection.
* [ ] Implement `Logger` with strict 5MB rolling file rotation.

### Phase 2: Lyrics & Running Chords Engine
* [ ] Implement LRCLIB client and LRC timestamp parser.
* [ ] Implement `ChordsService` with online chord fetching and time-aligned parsing.
* [ ] Implement Transpose & Capo math engine.
* [ ] Implement CJK Romanization transform.
* [ ] Implement 100MB capped disk LRU cache.

### Phase 3: Presentation Layer (SwiftUI + AppKit)
* [ ] Implement `MenuBarController` (`NSStatusItem` dual-line marquee for lyric + chord).
* [ ] Implement `NotchIslandController` (`NSPanel` level 25 with screen safe area calculation).
* [ ] Implement `DesktopHUDController` (draggable, resizable, glassmorphic floating PiP window).
* [ ] Implement quick popover with transport buttons and tap-to-seek.

### Phase 4: Verification & Polish
* [ ] Long-running stress test (72-hour benchmark verifying flat memory profile <40MB).
* [ ] Verify Dia browser playback and play/pause controls without waking Google Chrome.
* [ ] Verify chord transpose accuracy across standard musical keys.
