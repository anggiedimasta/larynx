# LyricsService: Ingestion, LRC Parsing, Transliteration, and Synchronization

## 1. Subsystem Overview

`VerseBar.LyricsService` is responsible for acquiring, parsing, caching, and synchronizing time-coded song lyrics.

It coordinates two core lifecycle paths:
1. **Acquisition Pipeline**: Cache-first resolver backed by the remote [LRCLIB](https://lrclib.net) API.
2. **Real-time Synchronization Loop**: 10Hz timer matching playback position to lyric timestamps.

---

## 2. Ingestion Pipeline & Endpoints

### A. Lifecycle State Flow (`LyricsStatus`)

```
          [Track Changed]
                 │
                 ▼
          ┌─────────────┐
          │  .searching │
          └──────┬──────┘
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
[Disk Cache Hit]      [Disk Cache Miss]
      │                     │
      │                     ├─► [offlineMode == true] ──► .unavailableOffline
      │                     │
      │                     ▼
      │               [LRCLIB Query]
      │               GET /api/get (Exact)
      │                     │
      │              ┌──────┴──────┐
      │              ▼ 200 OK      ▼ 404 / Non-200
      │       [Parse & Cache]  [Search Fallback]
      │              │         GET /api/search?q=...
      │              │             │
      │              │      ┌──────┴──────┐
      │              │      ▼ Match       ▼ No Match
      │              │ [Parse & Cache] ┌──────────┐
      │              │      │          │.notFound │
      │              ▼      ▼          └──────────┘
      └───────────►┌────────┐
                   │ .found │
                   └────────┘
```

---

### B. Disk Caching (`LyricsCache`)
* **Location**: `~/Library/Caches/com.versebar.VerseBar/LyricsCache/`
* **Filename Slug (`getCacheSlug`)**:
  * Formatted as `"${sanitized_artist}_${sanitized_title}.json"`.
  * Non-alphanumeric characters are stripped or converted to underscores; lowercase normalized.
* **Payload Structure (`[VerseBar.CachedLyricLine]`)**:
  ```json
  [
    {
      "timestamp": 12.34,
      "text": "First lyric line",
      "romanized": "Romanized text if non-Latin"
    }
  ]
  ```
* **Performance Impact**: Cache hits load synchronously or near-instantaneously without invoking HTTP tasks, enabling offline and instant lyric playback on repeated song plays.

---

### C. LRCLIB REST Integration

#### 1. Exact Match (`GET /api/get`)
* **Endpoint**: `https://lrclib.net/api/get`
* **Query Parameters**:
  * `artist_name`: `track.artist`
  * `track_name`: `track.title`
  * `duration`: `Int(round(track.duration))`
* **Headers**: `User-Agent: VerseBar/1.0 (https://github.com/antikode/verse-bar)`
* **Response**: Deserialized into `VerseBar.LRCLIBResponse`:
  * `syncedLyrics`: Raw string in standard LRC file format (`[mm:ss.xx] Line text`).
  * `plainLyrics`: Unsynchronized text fallback if timestamps are unavailable.

#### 2. Search Fallback (`GET /api/search`)
* Invoked when exact match returns HTTP 404 or fails.
* **Endpoint**: `https://lrclib.net/api/search?q=${artist} ${title}`
* **Selection Filter**:
  * Filters results for candidates where `syncedLyrics != nil`.
  * Computes duration delta against `track.duration`.
  * Selects the closest candidate within tolerance.

---

## 3. LRC Parsing & Transliteration

### A. LRC Parser (`parseLRC`)
* **Regex**:
  ```regex
  ^\[(\d+):(\d+)(?:\.(\d+))?\](.*)$
  ```
* **Capture Groups**:
  * `Group 1`: Minutes ($M$)
  * `Group 2`: Seconds ($S$)
  * `Group 3`: Sub-seconds / Hundredths ($F$)
  * `Group 4`: Lyric text
* **Formula**:
  $$\text{Timestamp} = (M \times 60) + S + \frac{F}{10^{\text{digits}}}$$
* **Sorting**: Parsed lines are sorted ascending by timestamp.

---

### B. Transliteration Engine (`LyricsService.romanize`)
* **Target Scripts**: Non-Latin CJK scripts (Japanese Kanji/Kana, Korean Hangul, Chinese Hanzi).
* **Implementation Details**:
  1. Inspects unicode scalars of each lyric line to check for non-Latin character sets.
  2. If detected, initializes an `NSMutableString` with the text.
  3. Executes CoreFoundation ICU string transformation:
     ```swift
     CFStringTransform(mutableString, nil, "Any-Latin" as CFString, false)
     ```
  4. Executes secondary transformation:
     ```swift
     CFStringTransform(mutableString, nil, kCFStringTransformStripCombiningMarks, false)
     ```
  5. Stores the result in `LyricLine.romanized`. If no non-Latin characters are detected, `romanized` is set to `nil`.

---

## 4. Synchronization Engine

### A. High-Frequency Timer
* `startSyncTimer()` initializes an `NSTimer`:
  ```swift
  NSTimer.scheduledTimer(withTimeInterval: 0.1, repeats: true)
  ```
* Runs on `RunLoop.main` at **10 Hz** (`100ms` intervals).

---

### B. Active Line Resolution (`updateActiveLyricIndex`)
1. Reads current playback position from `playbackEngine.currentTrack?.elapsedTime`.
2. Adds user-configurable manual sync offset from `AppSettings.manualSyncOffset`:
   $$\text{EffectiveTime} = \text{elapsedTime} + \text{manualSyncOffset}$$
3. Iterates over `lyricLines` to locate the active index:
   $$\text{activeIdx} = \max \{ i \mid \text{lyricLines}[i].\text{timestamp} \le \text{EffectiveTime} \}$$
4. Updates `@Published var currentLineIndex: Int?`.
5. SwiftUI components subscribed to `currentLineIndex` update their rendering:
   * **`PopoverView`**: Calls `scrollViewProxy.scrollTo(activeIdx, anchor: .center)` with smooth animation.
   * **`NotchIslandView`**: Transitions to the new lyric line string.
   * **`StatusItemManager`**: Refreshes menu bar button title/marquee text.
