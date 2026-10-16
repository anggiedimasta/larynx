import Foundation
import AppKit

public struct Track: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let duration: Double
    public let elapsedTime: Double
    public let isPaused: Bool
    public let lastUpdated: Date
    public let source: String

    public init(
        title: String,
        artist: String,
        duration: Double,
        elapsedTime: Double,
        isPaused: Bool,
        lastUpdated: Date = Date(),
        source: String
    ) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.isPaused = isPaused
        self.lastUpdated = lastUpdated
        self.source = source
    }
}

public final class PlaybackEngine: @unchecked Sendable {
    public static let shared = PlaybackEngine()

    public var onTrackChanged: (@Sendable (Track?) -> Void)?
    public private(set) var currentTrack: Track?

    private var pollTimer: Timer?
    private let queue = DispatchQueue(label: "com.larynx.playback", qos: .userInitiated)
    private var lastPolledSource: String?

    // Supported Chromium & WebKit bundle identifiers
    private let targetBrowsers: [(bundleId: String, appName: String, isSafari: Bool)] = [
        ("company.thebrowser.dia", "Dia", false),
        ("company.thebrowser.Arc", "Arc", false),
        ("com.google.Chrome", "Google Chrome", false),
        ("com.brave.Browser", "Brave Browser", false),
        ("com.microsoft.edgemac", "Microsoft Edge", false),
        ("com.apple.Safari", "Safari", true)
    ]

    private init() {}

    public func start() {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.poll()
            }
            self.poll()
        }
    }

    public func stop() {
        DispatchQueue.main.async {
            self.pollTimer?.invalidate()
            self.pollTimer = nil
        }
    }

    public func poll() {
        queue.async {
            autoreleasepool {
                if let track = self.pollActiveBrowsers() {
                    self.updateTrack(track)
                }
            }
        }
    }

    private func updateTrack(_ track: Track?) {
        if self.currentTrack != track {
            self.currentTrack = track
            self.onTrackChanged?(track)
        }
    }

    private func pollActiveBrowsers() -> Track? {
        // Find which browsers are actively running right now
        for browser in targetBrowsers {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleId)
            guard !running.isEmpty else { continue } // ponytail: strict running guard avoids launching closed browsers

            if let track = queryBrowser(browser) {
                lastPolledSource = browser.appName
                return track
            }
        }
        return nil
    }

    private func queryBrowser(_ browser: (bundleId: String, appName: String, isSafari: Bool)) -> Track? {
        let scriptText: String
        let js = #"""
        (function(){
            var v = document.querySelector('video');
            if (!v) return '';
            var titleEl = document.querySelector('yt-formatted-string.title.style-scope.ytmusic-player-bar')
                       || document.querySelector('.title.style-scope.ytmusic-player-bar')
                       || document.querySelector('ytmusic-player-bar .title')
                       || document.querySelector('h1.ytd-watch-metadata yt-formatted-string')
                       || document.querySelector('#info-contents h1 yt-formatted-string');
            var artistEl = document.querySelector('yt-formatted-string.byline.style-scope.ytmusic-player-bar a')
                        || document.querySelector('.byline.style-scope.ytmusic-player-bar a')
                        || document.querySelector('ytmusic-player-bar .byline a')
                        || document.querySelector('#owner #channel-name a')
                        || document.querySelector('ytd-channel-name a');
            var title = titleEl ? titleEl.textContent.trim() : '';
            var artist = artistEl ? artistEl.textContent.trim() : '';
            if (!title && document.title) {
                var dt = document.title.replace(/ - YouTube Music$/, '').replace(/ - YouTube$/, '');
                var parts = dt.split(' - ');
                if (parts.length >= 2) { title = parts[0].trim(); artist = parts.slice(1).join(' - ').trim(); }
                else { title = dt.trim(); }
            }
            if (!title) return '';
            return title + '|||' + artist + '|||' + (v.currentTime || 0) + '|||' + (v.duration || 0) + '|||' + v.paused;
        })()
        """#

        if browser.isSafari {
            scriptText = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" or URL of t contains "youtube.com" then
                            return (do JavaScript "\(js)" in t)
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        } else {
            // Chromium (Dia, Arc, Chrome, Brave, Edge)
            scriptText = """
            tell application id "\(browser.bundleId)"
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            if URL of t contains "music.youtube.com" or URL of t contains "youtube.com" then
                                return (execute t javascript "\(js)")
                            end if
                        end repeat
                    end try
                end repeat
            end tell
            return ""
            """
        }

        guard let script = NSAppleScript(source: scriptText) else { return nil }
        var errorDict: NSDictionary?
        let resultDesc = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let stringValue = resultDesc.stringValue, !stringValue.isEmpty else {
            return nil
        }

        let parts = stringValue.components(separatedBy: "|||")
        guard parts.count >= 5 else { return nil }

        let title = parts[0]
        let artist = parts[1].isEmpty ? "Unknown Artist" : parts[1]
        let current = Double(parts[2]) ?? 0
        let duration = Double(parts[3]) ?? 0
        let isPaused = (parts[4] == "true")

        return Track(
            title: title,
            artist: artist,
            duration: duration,
            elapsedTime: current,
            isPaused: isPaused,
            source: browser.appName
        )
    }

    public func togglePlayPause() {
        queue.async {
            autoreleasepool {
                // If a browser is running media, toggle video inside THAT running browser
                for browser in self.targetBrowsers {
                    let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleId)
                    guard !running.isEmpty else { continue }

                    let toggleJS = "(function(){var v=document.querySelector('video');if(v){v.paused?v.play().catch(function(){}):v.pause();}})()"
                    let scriptText = browser.isSafari ? """
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "music.youtube.com" or URL of t contains "youtube.com" then
                                    do JavaScript "\(toggleJS)" in t
                                    return
                                end if
                            end repeat
                        end repeat
                    end tell
                    """ : """
                    tell application id "\(browser.bundleId)"
                        repeat with w in windows
                            try
                                repeat with t in tabs of w
                                    if URL of t contains "music.youtube.com" or URL of t contains "youtube.com" then
                                        execute t javascript "\(toggleJS)"
                                        return
                                    end if
                                end repeat
                            end try
                        end repeat
                    end tell
                    """

                    if let script = NSAppleScript(source: scriptText) {
                        var err: NSDictionary?
                        script.executeAndReturnError(&err)
                    }
                }

                // Also send hardware media key
                self.postMediaKey(16) // NX_KEYTYPE_PLAY
            }
        }
    }

    private func postMediaKey(_ keyCode: Int32) {
        func post(down: Bool) {
            let flags: NSEvent.ModifierFlags = down ? NSEvent.ModifierFlags(rawValue: 0xa00) : NSEvent.ModifierFlags(rawValue: 0xb00)
            let data1 = (Int(keyCode) << 16) | (down ? 0xa00 : 0xb00)
            if let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) {
                event.cgEvent?.post(tap: .cghidEventTap)
            }
        }
        post(down: true)
        post(down: false)
    }
}
