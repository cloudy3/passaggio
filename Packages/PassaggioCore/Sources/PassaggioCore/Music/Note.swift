import Foundation

/// A pitch identified by its MIDI note number (middle C, C4, is 60).
public struct Note: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var midi: Int

    public init(midi: Int) {
        self.midi = midi
    }

    /// Parses scientific pitch notation such as `C4`, `D#2`, `Eb3` or `G♯4`.
    public init?(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let letter = trimmed.first?.uppercased(),
              let base = Note.letterSemitones[letter] else { return nil }

        var rest = trimmed.dropFirst()
        var accidental = 0
        while let c = rest.first, let delta = Note.accidentals[c] {
            accidental += delta
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty, let octave = Int(rest) else { return nil }
        self.midi = (octave + 1) * 12 + base + accidental
    }

    public static let lowestPiano = Note(midi: 21)   // A0
    public static let highestPiano = Note(midi: 108) // C8

    public var pitchClass: Int { ((midi % 12) + 12) % 12 }
    public var octave: Int { Int((Double(midi) / 12).rounded(.down)) - 1 }

    /// Name using sharps, which is how the user's range (D#2–G#4) is written.
    public var name: String { Note.sharpNames[pitchClass] + String(octave) }

    /// Spoken form for VoiceOver ("D sharp 2").
    public var accessibilityName: String {
        let spoken = Note.sharpNames[pitchClass].replacingOccurrences(of: "#", with: " sharp")
        return "\(spoken) \(octave)"
    }

    public var description: String { name }

    /// Equal-tempered frequency with A4 = 440 Hz.
    public var frequency: Double { 440 * pow(2, Double(midi - 69) / 12) }

    public func transposed(by semitones: Int) -> Note { Note(midi: midi + semitones) }

    public static func < (lhs: Note, rhs: Note) -> Bool { lhs.midi < rhs.midi }

    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let letterSemitones: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    private static let accidentals: [Character: Int] = ["#": 1, "♯": 1, "b": -1, "♭": -1]
}

public extension Note {
    // The singer's range and the lower passaggio, used for defaults and presets.
    static let singerFloor = Note(midi: 39)      // D#2
    static let singerCeiling = Note(midi: 68)    // G#4
    static let passaggioLow = Note(midi: 60)     // C4
    static let passaggioHigh = Note(midi: 66)    // F#4
}
