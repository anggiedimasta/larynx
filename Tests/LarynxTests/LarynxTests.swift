import Foundation
import Testing
@testable import Larynx

@Test func testLRCParser() {
    let sampleLRC = """
    [00:12.50] Hello world
    [01:05.200] Second line of lyric
    """
    let engine = LyricsAndChordsEngine.shared
    let lines = engine.parseLRC(sampleLRC)

    #expect(lines.count == 2)
    #expect(lines[0].text == "Hello world")
    #expect(abs(lines[0].timestamp - 12.5) < 0.01)
    #expect(lines[1].text == "Second line of lyric")
    #expect(abs(lines[1].timestamp - 65.2) < 0.01)
}

@Test func testChordTransposition() {
    #expect(LyricsAndChordsEngine.transposeChord("[ C ]", by: 2) == "[ D ]")
    #expect(LyricsAndChordsEngine.transposeChord("[ Am7 ]", by: 1) == "[ A#m7 ]")
    #expect(LyricsAndChordsEngine.transposeChord("[ G ]", by: -2) == "[ F ]")
}

@Test func testChordToLyricAlignment() {
    let lyrics = [
        LyricLine(timestamp: 10.0, text: "I want it that way"),
        LyricLine(timestamp: 15.0, text: "Tell me why")
    ]
    let chords = [
        (chord: "[ F#m ]", lyric: "I want it that way"),
        (chord: "[ E ]", lyric: "Tell me why")
    ]

    let mapped = LyricsAndChordsEngine.shared.alignChordsToLyrics(chordLines: chords, lyrics: lyrics)
    #expect(mapped[0] == "[ F#m ]")
    #expect(mapped[1] == "[ E ]")
}
