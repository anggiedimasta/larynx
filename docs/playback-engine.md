# PlaybackEngine: Media Detection, Sources, and Root-Cause Bug Analyses

## 1. Subsystem Architecture

`VerseBar.PlaybackEngine` is the media monitoring center of Verse Bar. It polls, aggregates, and unifies media playback state across diverse desktop sources into a single reactive model:

```swift
struct Track: Equatable {
    let title: String
    let artist: String
    let duration: Double
    let elapsedTime: Double
    let isPaused: Bool
    let lastUpdated: Date
    let isEstimatedProgress: Bool
    let artworkData: Data?
    let artworkId: String?
}
```

The engine runs a repeating `NSTimer` configured at **`1.5 seconds`** (`100011d20: fmov d0, #1.5`). In every tick, `PlaybackEngine.poll()` queries five candidate playback sources in priority order:

1. **`pollNowPlaying`**: Queries `NowPlayingService.shared` (macOS system media session).
2. **`pollYTMDesktop`**: Queries local HTTP port `9863` (YouTube Music Desktop App companion API).
3. **`pollArc`**: AppleScript inspection of Arc browser tabs.
4. **`pollChrome`**: AppleScript inspection of Google Chrome tabs.
5. **`pollSafari`**: AppleScript inspection of Safari tabs.

---

## 2. In-Depth Source Analysis

### A. System Media Session: `NowPlayingService`
* **Architecture**: macOS 15.4+ restricts ad-hoc or unsigned binaries from reading `MediaRemote.framework`. To circumvent this, Verse Bar bundles an external script at `/Applications/Verse Bar.app/Contents/Resources/now_playing_helper.swift` and spawns it using the Apple-signed system interpreter:
  ```bash
  /usr/bin/swift /Applications/Verse Bar.app/Contents/Resources/now_playing_helper.swift
  ```
* **IPC**: The helper runs a `1.0s` repeating timer:
  * Dynamically loads `MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteGetNowPlayingApplicationIsPlaying`, and `MRMediaRemoteGetNowPlayingApplicationPID`.
  * Serializes track title, artist, album, duration, elapsed time, bundle ID, and **base64-encoded artwork data** into JSON.
  * Writes newline-delimited JSON strings to `stdout`.
  * `VerseBar.NowPlayingService.readLines` reads `stdout` asynchronously via `NSFileHandle`, deserializes the JSON via `JSONSerialization`, and caches the dictionary under `NSLock`.

---

### B. Web Browsers: `AppleScriptRunner` & Injected JavaScript DOM Scrapers
* **Target Browsers**: Google Chrome, Safari, Arc.
* **Mechanism**: Verse Bar executes `/usr/bin/osascript` via `NSTask` (`Process`) with script templates targeting each browser.
* **Verbatim Injected JavaScript Payloads**:
  1. **YouTube Music Web Scraper** (Evaluated in `music.youtube.com` tabs):
     ```javascript
     (function(){
         var v = document.querySelector('video');
         if (!v) return '';
         var titleEl = document.querySelector('yt-formatted-string.title.style-scope.ytmusic-player-bar')
                    || document.querySelector('.title.style-scope.ytmusic-player-bar')
                    || document.querySelector('ytmusic-player-bar .title');
         var artistEl = document.querySelector('yt-formatted-string.byline.style-scope.ytmusic-player-bar a')
                     || document.querySelector('.byline.style-scope.ytmusic-player-bar a')
                     || document.querySelector('ytmusic-player-bar .byline a')
                     || document.querySelector('yt-formatted-string.byline.style-scope.ytmusic-player-bar')
                     || document.querySelector('.byline.style-scope.ytmusic-player-bar');
         var title = titleEl ? titleEl.textContent.trim() : '';
         var artist = artistEl ? artistEl.textContent.trim() : '';
         if (!title && document.title) {
             var dt = document.title.replace(/ - YouTube Music$/, '').replace(/ [|] YouTube Music$/, '');
             if (dt !== 'YouTube Music' && dt !== 'YouTube') {
                 var parts = dt.split(' - ');
                 if (parts.length >= 2) { title = parts[0].trim(); artist = parts.slice(1).join(' - ').trim(); }
                 else { title = dt.trim(); }
             }
         }
         var ct = v.currentTime || 0;
         var dur = v.duration || 0;
         var paused = v.paused;
         return title + '|||' + artist + '|||' + ct + '|||' + dur + '|||' + paused;
     })()
     ```
  2. **Standard YouTube Video Scraper** (Fallback evaluated on general `youtube.com` tabs):
     ```javascript
     (function(){
         var v = document.querySelector('video');
         if (!v) return '';
         var titleEl = document.querySelector('h1.ytd-watch-metadata yt-formatted-string')
                    || document.querySelector('#info-contents h1 yt-formatted-string')
                    || document.querySelector('h1.title');
         var channelEl = document.querySelector('#owner #channel-name a')
                      || document.querySelector('ytd-channel-name a')
                      || document.querySelector('#upload-info a');
         var title = titleEl ? titleEl.textContent.trim() : '';
         var artist = channelEl ? channelEl.textContent.trim() : '';
         if (!title) {
             var dt = document.title.replace(/ - YouTube$/, '').replace(/ [|] YouTube$/, '');
             if (dt !== 'YouTube') title = dt.trim();
         }
         var ct = v.currentTime || 0;
         var dur = v.duration || 0;
         var paused = v.paused;
         return title + '|||' + artist + '|||' + ct + '|||' + dur + '|||' + paused;
     })()
     ```
  3. **Play/Pause Toggle Script**:
     ```javascript
     (function(){var v=document.querySelector('video');if(!v)return;if(v.paused){v.play().catch(function(){});}else{v.pause();}})()
     ```
  4. **Next Track Button Script**:
     ```javascript
     (function(){var b=document.querySelector('.next-button')||document.querySelector('[aria-label="Next"]');if(b)b.click();})()
     ```
  5. **Previous Track Button Script**:
     ```javascript
     (function(){var b=document.querySelector('.previous-button')||document.querySelector('[aria-label="Previous"]');if(b)b.click();})()
     ```
  6. **Direct Timestamp Seek Script**:
     ```javascript
     (function(){var v=document.querySelector('video');if(v){try{v.currentTime=%f;}catch(e){}}})()
     ```

### C. Browser Tab Verification: `YouTubeTabVerdict`
When `NowPlayingService` reports a browser as the active media application, `PlaybackEngine` verifies whether the browser tab actually contains YouTube content before accepting the session:
```swift
enum YouTubeTabVerdict {
    case youtube        // Confirmed music.youtube.com or youtube.com tab
    case notYouTube     // Browser is playing non-YouTube media (e.g. Netflix, podcast)
    case cannotVerify   // Automation permission denied or script timed out
}
```

---

### D. Desktop Player: YTMDesktop Companion API
* **Endpoint**: `http://localhost:9863/query`
* **Protocol**: HTTP GET via `URLSession.shared.dataTask`.
* **Parsed JSON Schema**:
  * `player.hasSong` (`Bool`): Whether a track is currently loaded.
  * `player.isPaused` (`Bool`): Current playback state.
  * `player.seekbarCurrentPosition` (`Double`): Real-time playback timestamp in seconds.
  * `track.title` (`String`): Song name.
  * `track.author` (`String`): Artist name.
  * `track.duration` (`Double`): Total track length in seconds.

## 3. Bug Analysis #1: Play/Pause Button Launches Google Chrome

### Symptom
When listening to YouTube Music in **Dia browser** (or any unsupported browser), clicking the Play/Pause button in the Verse Bar menu bar dropdown unexpectedly launches Google Chrome.

### Root-Cause Disassembly Walkthrough
1. When the user clicks the Play/Pause button, `PopoverHostingController.handlePlayPause()` invokes:
   ```swift
   VerseBar.PlaybackEngine.togglePlayPause() // 0x10001c41c
   ```
2. In `PlaybackEngine.togglePlayPause()`, two actions occur:
   * **Action 1**: Posts hardware media keys (`MediaKeys.send(MediaKeys.play)`).
   * **Action 2**: Calls `runJSInBrowsers` (`0x10001c900`) with video toggle script:
     ```javascript
     (function(){var v=document.querySelector('video');if(!v)return;if(v.paused){v.play().catch(function(){});}else{v.pause();}})()
     ```
3. In `runJSInBrowsers`, the application constructs AppleScript strings and unconditionally calls:
   ```swift
   AppleScriptRunner.run(arcScript)    // 0x10001cc40
   AppleScriptRunner.run(chromeScript) // 0x10001cc60
   AppleScriptRunner.run(safariScript) // 0x10001cc80
   ```
4. **The macOS AppleScript Quirk**:
   * In macOS AppleScript, targeting an application with `tell application "Google Chrome"` when Google Chrome is installed but closed **causes macOS to automatically launch that application**.
   * Verse Bar fails to check whether Google Chrome is actively running before sending the AppleScript command.
   * Furthermore, **Dia browser is not recognized** by Verse Bar (only Arc, Chrome, and Safari are supported). While Dia's playback might be detected through the system `NowPlayingService`, the play/pause handler does not know how to script Dia, and instead fires scripts at Arc, Chrome, and Safari, waking up Chrome.

### Concrete Fix
1. Guard all AppleScript calls by checking running applications first:
   ```swift
   guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty else { return }
   ```
   Or wrap the AppleScript code with an `is running` guard:
   ```applescript
   if application "Google Chrome" is running then
       tell application "Google Chrome" ...
   end if
   ```
2. Add support for Dia browser bundle identifier (`com.diabrowser.Dia` or equivalent).

---

## 4. Bug Analysis #2: Unbounded Memory Heap Growth (2+ Days Runtime)

### Symptom
When Verse Bar is left open for several days, resident memory and heap usage continuously climb, often leading to performance degradation or termination.

### Observed Causes & Evidence

#### 1. Massive Unbounded File I/O (`debug.log` Reaching 514MB+)
* In `Logger.writeToFile` (`0x1000d190c`):
  * Every single log call creates a `FileHandle(forWritingTo: logFileURL)`, seeks to the end, writes data, and closes the handle.
  * Every 1.5 seconds, `PlaybackEngine.poll()` outputs at least two log messages:
    * `[PLAYBACK] 🎵 Detected (NowPlaying): ...`
    * `[PLAYBACK] ✅ Source NowPlaying: track found`
  * Over 48 hours, this writes over **230,000 log entries** without any log rotation, file size limit, or truncation.
  * Actual verification on disk revealed `/Users/lion/Library/Application Support/com.versebar.VerseBar/debug.log` had swollen to **514 Megabytes**.

#### 2. Process Churn via `NSTask` (`/usr/bin/osascript`)
* In `AppleScriptRunner.run` (`0x1000ceeac`):
  * Every browser poll invokes `/usr/bin/osascript` via `NSTask()` / `Process()`.
  * Across three browsers every 1.5 seconds, the app spawns **~120 child processes per minute** (172,800 child processes over 2 days).
  * Foundation's `Process` and `Pipe` allocate Mach task ports, file descriptors, and dispatch sources. Rapid continuous churn creates memory fragmentation and retains autorelease pools across GCD threads.

#### 3. Base64 Album Artwork Streamed Every 1.0 Second
* In `now_playing_helper.swift`:
  ```swift
  if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
      dict["artwork"] = art.base64EncodedString()
      if let aid = info["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String {
          dict["artworkId"] = aid
      }
  }
  ```
* Every second, the helper serializes full raw uncompressed artwork as a base64 string (often 2MB–5MB) and dumps it to `stdout`.
* `NowPlayingService.readLines` reads this huge string, deserializes it via `JSONSerialization`, and caches it in memory every second—allocating gigabytes of temporary objects over 48 hours without an `@autoreleasepool`.

#### 4. Lack of `@autoreleasepool` in High-Frequency Timers
* The app runs three continuous background timers:
  * `0.1s` (10Hz) sync timer in `LyricsService`
  * `0.5s` (2Hz) menu bar text timer in `StatusItemManager`
  * `1.5s` polling timer in `PlaybackEngine`
* In Swift/Objective-C ARC, objects allocated in GCD blocks and timer handlers land in the thread-local autorelease pool. Without explicit `autoreleasepool { ... }` blocks around timer tick handlers, autoreleased Objective-C objects accumulate indefinitely until the thread terminates.

### Concrete Fixes
1. **Log Rotation**: Add log file capping (e.g. max 5MB with single `.old` rotation) or log level suppression in production.
2. **Reuse AppleScript Execution**: Replace `NSTask("/usr/bin/osascript")` process spawning with persistent in-process `NSAppleScript` or `NSUserAppleScriptTask`.
3. **Artwork Deduplication**: Only emit base64 artwork from `now_playing_helper` when `artworkIdentifier` changes, rather than every 1 second.
4. **Autorelease Enclosure**: Enclose timer callbacks in `@autoreleasepool { ... }`.
