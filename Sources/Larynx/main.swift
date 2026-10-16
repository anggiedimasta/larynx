import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var notchPanel: NSPanel?
    private var hudPanel: NSPanel?

    private var notchHostingView: NSHostingView<NotchIslandView>?
    private var hudHostingView: NSHostingView<DesktopHUDView>?

    private var currentTrack: Track?
    private var activeLine: LyricLine?
    private var isNotchExpanded = false
    private var showChordsInMenuBar = true
    private var showNotchIsland = true
    private var showHUD = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background accessory application (LSUIElement behavior)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupNotchIsland()
        setupDesktopHUD()
        setupEngines()
    }

    // MARK: - Menu Bar Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.title = "🎵 Larynx"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let title = currentTrack != nil ? "\(currentTrack!.title) - \(currentTrack!.artist)" : "Larynx Ready"
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())

            let hudItem = NSMenuItem(title: showHUD ? "Hide Desktop HUD" : "Show Desktop HUD", action: #selector(toggleHUD), keyEquivalent: "h")
            hudItem.target = self
            menu.addItem(hudItem)

            let notchItem = NSMenuItem(title: showNotchIsland ? "Hide Notch Island" : "Show Notch Island", action: #selector(toggleNotch), keyEquivalent: "n")
            notchItem.target = self
            menu.addItem(notchItem)

            let chordItem = NSMenuItem(title: showChordsInMenuBar ? "Hide Chords in Menu Bar" : "Show Chords in Menu Bar", action: #selector(toggleChords), keyEquivalent: "c")
            chordItem.target = self
            menu.addItem(chordItem)

            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit Larynx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(quitItem)

            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil // restore action-based left clicks
        } else {
            toggleHUD()
        }
    }

    @objc private func toggleHUD() {
        showHUD.toggle()
        if showHUD {
            hudPanel?.orderFrontRegardless()
        } else {
            hudPanel?.orderOut(nil)
        }
    }

    @objc private func toggleNotch() {
        showNotchIsland.toggle()
        if showNotchIsland {
            notchPanel?.orderFrontRegardless()
        } else {
            notchPanel?.orderOut(nil)
        }
    }

    @objc private func toggleChords() {
        showChordsInMenuBar.toggle()
        updateMenuBarText()
    }

    // MARK: - Notch Island Panel
    private func setupNotchIsland() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: 25) // NSWindow.Level.statusBar / above notch
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: makeNotchView())
        panel.contentView = host
        self.notchHostingView = host
        self.notchPanel = panel

        repositionNotchPanel()
        if showNotchIsland { panel.orderFrontRegardless() }
    }

    private func makeNotchView() -> NotchIslandView {
        NotchIslandView(
            track: currentTrack,
            activeLine: activeLine,
            isExpanded: isNotchExpanded,
            onTogglePlayPause: {
                PlaybackEngine.shared.togglePlayPause()
            }
        )
    }

    private func repositionNotchPanel() {
        guard let screen = NSScreen.main, let panel = notchPanel else { return }
        let screenRect = screen.frame
        let notchHeight = screen.safeAreaInsets.top
        let width: CGFloat = isNotchExpanded ? 400 : 240
        let height: CGFloat = isNotchExpanded ? 80 : 32

        // Center on screen width, positioned under the notch
        let x = screenRect.origin.x + (screenRect.width - width) / 2
        let y = screenRect.origin.y + screenRect.height - height - max(0, notchHeight - 12)

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: true)
    }

    // MARK: - Desktop HUD (Floating PiP)
    private func setupDesktopHUD() {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 340, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating // Pinned above regular windows
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true // User can drag anywhere
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: makeHUDView())
        panel.contentView = host
        self.hudHostingView = host
        self.hudPanel = panel

        // Default position: bottom-right
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 360
            let y = screen.visibleFrame.minY + 40
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        if showHUD { panel.orderFrontRegardless() }
    }

    private func makeHUDView() -> DesktopHUDView {
        DesktopHUDView(
            track: currentTrack,
            activeLine: activeLine,
            transposeSemiTones: LyricsAndChordsEngine.shared.transposeSemiTones,
            onTransposeChanged: { newTranspose in
                LyricsAndChordsEngine.shared.transposeSemiTones = newTranspose
            },
            onTogglePlayPause: {
                PlaybackEngine.shared.togglePlayPause()
            }
        )
    }

    // MARK: - Engine Wiring
    private func setupEngines() {
        PlaybackEngine.shared.onTrackChanged = { [weak self] track in
            DispatchQueue.main.async {
                self?.currentTrack = track
                LyricsAndChordsEngine.shared.handleTrack(track)
                self?.refreshViews()
            }
        }

        LyricsAndChordsEngine.shared.onLinesUpdated = { [weak self] lines, status in
            DispatchQueue.main.async {
                self?.refreshViews()
            }
        }

        LyricsAndChordsEngine.shared.onActiveIndexChanged = { [weak self] index in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let idx = index, idx < LyricsAndChordsEngine.shared.lines.count {
                    self.activeLine = LyricsAndChordsEngine.shared.lines[idx]
                } else {
                    self.activeLine = nil
                }
                self.refreshViews()
            }
        }

        PlaybackEngine.shared.start()
    }

    private func refreshViews() {
        updateMenuBarText()
        notchHostingView?.rootView = makeNotchView()
        hudHostingView?.rootView = makeHUDView()
    }

    private func updateMenuBarText() {
        guard let button = statusItem?.button else { return }

        if let line = activeLine {
            var text = line.text
            if showChordsInMenuBar, let chord = line.chord {
                text = "\(text) \(chord)"
            }
            button.title = "🎵 \(text)"
        } else if let track = currentTrack {
            button.title = "🎵 \(track.title) - \(track.artist)"
        } else {
            button.title = "🎵 Larynx"
        }
    }
}

// Entrypoint
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
