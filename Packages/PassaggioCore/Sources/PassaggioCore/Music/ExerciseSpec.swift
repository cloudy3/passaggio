import Foundation

/// Every parameter of a generated practice track. Stored as JSON on presets and routine exercises.
public struct ExerciseSpec: Hashable, Codable, Sendable {
    public enum Direction: String, Codable, CaseIterable, Sendable {
        case ascending
        case descending
        case ascendingThenDescending

        public var displayName: String {
            switch self {
            case .ascending: "Up"
            case .descending: "Down"
            case .ascendingThenDescending: "Up, then back down"
            }
        }
    }

    public var pattern: ExercisePattern
    /// Root of the first repetition. Clamped into the range the pattern fits in.
    public var startNote: Note
    public var tempo: Double
    /// Semitones the root moves between repetitions.
    public var step: Int
    public var direction: Direction
    /// No sung note goes below `floor` or above `ceiling`.
    public var floor: Note
    public var ceiling: Note
    public var playsCueChord: Bool
    public var cueBeats: Double
    public var restBeats: Double
    /// Plays the piano this many octaves away from the sung pitch. Some teachers play
    /// an octave up for low male voices; the default is the sung pitch.
    public var pianoOctaveShift: Int

    public init(
        pattern: ExercisePattern = .fiveNoteScale,
        startNote: Note = .singerFloor,
        tempo: Double = 96,
        step: Int = 1,
        direction: Direction = .ascendingThenDescending,
        floor: Note = .singerFloor,
        ceiling: Note = .singerCeiling,
        playsCueChord: Bool = true,
        cueBeats: Double = 2,
        restBeats: Double = 1,
        pianoOctaveShift: Int = 0
    ) {
        self.pattern = pattern
        self.startNote = startNote
        self.tempo = tempo
        self.step = step
        self.direction = direction
        self.floor = floor
        self.ceiling = ceiling
        self.playsCueChord = playsCueChord
        self.cueBeats = cueBeats
        self.restBeats = restBeats
        self.pianoOctaveShift = pianoOctaveShift
    }

    public static let tempoRange: ClosedRange<Double> = 40...200
    public static let stepRange: ClosedRange<Int> = 1...12
}

// MARK: - Presets

public extension ExerciseSpec {
    /// Walks the whole range, D#2–G#4 by default, up and back down.
    static func fullRange(_ pattern: ExercisePattern) -> ExerciseSpec {
        ExerciseSpec(pattern: pattern, startNote: .singerFloor, direction: .ascendingThenDescending)
    }

    /// Concentrates repetitions in the lower passaggio (C4–F#4), where mix work happens.
    /// The first repetition peaks at C4; the root climbs until the peak reaches F#4 and
    /// then comes back down, so every repetition's top note sits inside the passaggio.
    static func passaggioFocus(_ pattern: ExercisePattern) -> ExerciseSpec {
        let span = pattern.offsets.max() ?? 0
        let lowest = pattern.offsets.min() ?? 0
        let firstRoot = Note.passaggioLow.transposed(by: -span)
        return ExerciseSpec(
            pattern: pattern,
            startNote: firstRoot,
            tempo: 88,
            direction: .ascendingThenDescending,
            floor: firstRoot.transposed(by: lowest),
            ceiling: .passaggioHigh
        )
    }
}

// MARK: - Validation

public extension ExerciseSpec {
    enum ValidationError: Error, Equatable, LocalizedError {
        case emptyPattern
        case invalidRange
        case invalidStep
        case invalidTempo
        case patternDoesNotFit(span: Int, available: Int)

        public var errorDescription: String? {
            switch self {
            case .emptyPattern: "The pattern has no notes."
            case .invalidRange: "The floor note must be at or below the ceiling note."
            case .invalidStep: "The step must be between 1 and 12 semitones."
            case .invalidTempo: "The tempo must be between 40 and 200 BPM."
            case let .patternDoesNotFit(span, available):
                "The pattern spans \(span) semitones but the floor-to-ceiling range is only \(available)."
            }
        }
    }

    func validate() throws {
        let offsets = pattern.offsets
        guard !offsets.isEmpty else { throw ValidationError.emptyPattern }
        guard floor <= ceiling else { throw ValidationError.invalidRange }
        guard Self.stepRange.contains(step) else { throw ValidationError.invalidStep }
        guard Self.tempoRange.contains(tempo) else { throw ValidationError.invalidTempo }
        let span = offsets.max()! - offsets.min()!
        let available = ceiling.midi - floor.midi
        guard span <= available else { throw ValidationError.patternDoesNotFit(span: span, available: available) }
    }

    /// Roots whose every sung note lies within floor...ceiling.
    var validRootRange: ClosedRange<Int>? {
        let offsets = pattern.offsets
        guard let lo = offsets.min(), let hi = offsets.max() else { return nil }
        let lowestRoot = floor.midi - lo
        let highestRoot = ceiling.midi - hi
        return lowestRoot <= highestRoot ? lowestRoot...highestRoot : nil
    }

    /// The root of every repetition, in order.
    func roots() throws -> [Note] {
        try validate()
        guard let valid = validRootRange else {
            throw ValidationError.patternDoesNotFit(span: 0, available: ceiling.midi - floor.midi)
        }
        let start = min(max(startNote.midi, valid.lowerBound), valid.upperBound)

        func walk(from origin: Int, by delta: Int) -> [Int] {
            Array(sequence(first: origin) { $0 + delta }.prefix { valid.contains($0) })
        }

        let midis: [Int]
        switch direction {
        case .ascending:
            midis = walk(from: start, by: step)
        case .descending:
            midis = walk(from: start, by: -step)
        case .ascendingThenDescending:
            let up = walk(from: start, by: step)
            // Come back down through the same roots, without repeating the peak.
            midis = up + up.dropLast().reversed()
        }
        return midis.map(Note.init(midi:))
    }
}
