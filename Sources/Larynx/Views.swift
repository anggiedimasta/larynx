import SwiftUI
import AppKit

// MARK: - MacBook Notch Island View
public struct NotchIslandView: View {
    let track: Track?
    let activeLine: LyricLine?
    let isExpanded: Bool
    let onTogglePlayPause: () -> Void

    public init(track: Track?, activeLine: LyricLine?, isExpanded: Bool, onTogglePlayPause: @escaping () -> Void) {
        self.track = track
        self.activeLine = activeLine
        self.isExpanded = isExpanded
        self.onTogglePlayPause = onTogglePlayPause
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isExpanded ? 18 : 12)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

            if isExpanded {
                VStack(spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track?.title ?? "No Media Playing")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(track?.artist ?? "Larynx")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(action: onTogglePlayPause) {
                            Image(systemName: (track?.isPaused ?? true) ? "play.fill" : "pause.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    if let line = activeLine {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.yellow)
                                .lineLimit(1)
                            if let chord = line.chord {
                                Text(chord)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: (track?.isPaused ?? true) ? "music.note" : "waveform")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    if let line = activeLine {
                        Text(line.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let chord = line.chord {
                            Text(chord)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                    } else {
                        Text(track?.title ?? "Larynx Idle")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(minWidth: isExpanded ? 320 : 180, maxWidth: isExpanded ? 460 : 260)
        .frame(height: isExpanded ? 80 : 32)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - Floating Desktop HUD (PiP Card)
public struct DesktopHUDView: View {
    let track: Track?
    let activeLine: LyricLine?
    let transposeSemiTones: Int
    let onTransposeChanged: (Int) -> Void
    let onTogglePlayPause: () -> Void

    @State private var showChords: Bool = true
    @State private var opacity: Double = 0.85

    public init(
        track: Track?,
        activeLine: LyricLine?,
        transposeSemiTones: Int,
        onTransposeChanged: @escaping (Int) -> Void,
        onTogglePlayPause: @escaping () -> Void
    ) {
        self.track = track
        self.activeLine = activeLine
        self.transposeSemiTones = transposeSemiTones
        self.onTransposeChanged = onTransposeChanged
        self.onTogglePlayPause = onTogglePlayPause
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header bar
            HStack {
                Circle()
                    .fill((track?.isPaused ?? true) ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(track?.title ?? "Larynx Ready")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer()

                // Transpose controls
                HStack(spacing: 4) {
                    Button(action: { onTransposeChanged(transposeSemiTones - 1) }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)

                    Text(transposeText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)

                    Button(action: { onTransposeChanged(transposeSemiTones + 1) }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onTogglePlayPause) {
                    Image(systemName: (track?.isPaused ?? true) ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }

            // Lyric line display
            if let line = activeLine {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let romanized = line.romanized {
                        Text(romanized)
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    if showChords, let chord = line.chord {
                        Text(chord)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
            } else {
                let placeholder = (track != nil) ? "🎵 \(track?.artist ?? "") - \(track?.title ?? "") (Intro)" : "Listening for media..."
                Text(placeholder)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .frame(minWidth: 280, maxWidth: 440)
    }

    private var transposeText: String {
        if transposeSemiTones == 0 { return "KEY" }
        return transposeSemiTones > 0 ? "+\(transposeSemiTones)" : "\(transposeSemiTones)"
    }
}
