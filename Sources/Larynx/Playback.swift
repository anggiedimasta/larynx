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
        let scriptText = browser.isSafari ? """
        tell application "Safari"
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t)
                        if u contains "music.youtube.com" or u contains "youtube.com" then
                            return (title of t) & "|||" & u
                        end if
                    end repeat
                end repeat
            end try
        end tell
        return ""
        """ : """
        tell application id "\(browser.bundleId)"
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t)
                        if u contains "music.youtube.com" or u contains "youtube.com" then
                            return (title of t) & "|||" & u
                        end if
                    end repeat
                end repeat
            end try
        end tell
        return ""
        """

        guard let script = NSAppleScript(source: scriptText) else { return nil }
        var errorDict: NSDictionary?
        let resultDesc = script.executeAndReturnError(&errorDict)
        guard errorDict == nil, let stringValue = resultDesc.stringValue, !stringValue.isEmpty else {
            return nil
        }

        let parts = stringValue.components(separatedBy: "|||")
        guard let rawTitle = parts.first, !rawTitle.isEmpty else { return nil }

        let cleaned = rawTitle
            .replacingOccurrences(of: " - YouTube Music", with: "")
            .replacingOccurrences(of: " - YouTube", with: "")
        let subParts = cleaned.components(separatedBy: " - ")

        let title = subParts[0].trimmingCharacters(in: .whitespaces)
        let artist = subParts.count > 1 ? subParts[1].trimmingCharacters(in: .whitespaces) : "YouTube Music"
        guard !title.isEmpty else { return nil }

        return Track(
            title: title,
            artist: artist,
            duration: 0,
            elapsedTime: 0,
            isPaused: false,
            source: browser.appName
        )
    }

    public func togglePlayPause() {
        // Global hardware media key - works across all browsers & native players without scripting errors
        postMediaKey(16) // NX_KEYTYPE_PLAY
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
