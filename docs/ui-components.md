# UI Components: StatusItemManager, PopoverView, and NotchIsland

Verse Bar provides three presentation surfaces to render lyrics and playback controls on macOS:
1. **StatusItemManager** (Menu Bar status item)
2. **PopoverView** (Interactive dropdown card)
3. **NotchIsland** (Physical MacBook camera notch overlay)

---

## 1. Menu Bar Controller: `VerseBar.StatusItemManager`

### A. Lifecycle & Architecture
* **Type**: Singleton class (`StatusItemManager.shared`).
* **Underlying Component**: AppKit `NSStatusItem` managed via `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
* **Refresh Timer**: Runs `menuBarUpdateTimer` every **`0.5 seconds`** (`100081ff0: fmov d0, #0.5`).

---

### B. Display Formatting (`updateMenuBarText`)
The text rendered in the menu bar button is conditionally assembled based on `AppSettings`:
* `showArtist == true`: Appends artist name.
* `showTitle == true`: Appends track title.
* `showLyrics == true`: Appends current active lyric line from `LyricsService.currentLineIndex`.
* If playing: Prepends music note indicator (`"🎵 "`).
* If paused: Updates play/pause state indicator.

---

### C. Marquee Text Scrolling: `VerseBar.MarqueeText`
* When the combined title/lyric string exceeds the available status bar item boundary, `MarqueeText` handles continuous horizontal scrolling using a SwiftUI offset animation:
  * Measures text width against container width.
  * Animates `offset(x:)` with linear repeat to cycle long lyric lines smoothly.

---

### D. User Interaction & Context Menu
* **Left Click (`statusItemClicked`)**: Toggles the interactive dropdown popover (`togglePopover`).
* **Right Click / Control Click (`showContextMenu`)**: Displays native context menu with:
  * Song information header.
  * Preferences (`openSettings`).
  * Check for Updates (`checkForUpdates`).
  * Quit Verse Bar (`quitApp`).

---

## 2. Interactive Dropdown: `VerseBar.PopoverView`

### A. Popover Container: `VerseBar.PopoverHostingController`
* **Underlying Component**: AppKit `NSPopover` containing an `NSHostingController` wrapped around SwiftUI `PopoverView`.
* **Pin Behavior (`applyPopoverBehavior`)**:
  * Bound to `AppSettings.pinPopover`:
    * When `pinPopover == true`: Configured with `.applicationDefined` behavior so the popover remains open when clicking other apps.
    * When `pinPopover == false`: Configured with `.transient` behavior (auto-closes on outside click).

---

### B. SwiftUI View Hierarchy
* **Frosted Glass Styling (`VerseBar.GlassmorphicView`)**: Uses `NSVisualEffectView` background with `.behindWindow` blending and `.hudWindow` material.
* **Header**: Displays album artwork, track title, artist name, and transport buttons.
* **Transport Controls**:
  * Action dispatcher based on `PopoverView.PlayerAction`:
    ```swift
    enum PlayerAction {
        case togglePlayPause
        case next
        case previous
    }
    ```
* **Lyrics List (`ScrollViewReader`)**:
  * Iterates `LyricsService.lyricLines` inside a `ScrollView`.
  * Active line is highlighted with distinct opacity/font weight.
  * Automatic scrolling: Subscribes to `LyricsService.$currentLineIndex` and invokes:
    ```swift
    scrollViewProxy.scrollTo(currentIndex, anchor: .center)
    ```
  * **Tap-to-Seek**: Clicking any lyric line executes `onTapGesture`, triggering playback seek to that line's timestamp.

---

## 3. Dynamic Notch Island: `VerseBar.NotchIsland`

### A. Window Hierarchy (`NotchIslandController`)
* **Window Class**: Native borderless AppKit `NSPanel` initialized via `ensurePanel()`.
* **Window Properties**:
  * `level = 25` (`NSWindow.Level.statusBar`): Floats above normal windows, menus, and fullscreen spaces.
  * `backgroundColor = .clear` & `isOpaque = false`: Transparent canvas.
  * `hasShadow = false`: Custom shadow rendered by SwiftUI.
  * `hidesOnDeactivate = false`: Stays visible across workspace switches.
  * `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.

---

### B. Screen Geometry Math (`resolveNotchMetrics`)
1. Reads `NSScreen.mainScreen` safe area and auxiliary area rects.
2. Dynamically measures physical notch width:
   $$\text{NotchWidth} = \text{auxiliaryTopRightArea.minX} - \text{auxiliaryTopLeftArea.maxX}$$
3. Dimensions:
   * **`compactBodyHeight`**: `30.0 pt`
   * **`expandedBodyHeight`**: `96.0 pt`
   * **`minCompactWidth`**: `260.0 pt`
   * **`minExpandedWidth`**: `520.0 pt`
   * **`notchOverhang`**: `44.0 pt`
   * **`collapseDelay`**: `0.18 s`
   * **Default Fallback Width**: `200.0 pt`
4. Observes `NSApplication.didChangeScreenParametersNotification` to re-calculate geometry when display arrangements change.

---

### C. State Machine & Hover Interaction
* Managed by `NotchIslandController.ViewModel` (`ObservableObject` with `@Published var isExpanded: Bool`).
* **Hover In**:
  * Cancels any pending collapse work item.
  * Sets `isExpanded = true`.
  * Calls `repositionPanel(expanded: true)` with smooth animation.
* **Hover Out**:
  * Schedules a `DispatchWorkItem` on `DispatchQueue.main` with delay `0.18s`.
  * When fired, sets `isExpanded = false` and animates collapse.
* **Compact Mode Content**: Compact pill hugging the notch showing the current synchronized lyric.
* **Expanded Mode Content (`expandedContent`)**: Full card showing album artwork, track title, artist, playback controls (Prev, Play/Pause, Next), and active verse.
