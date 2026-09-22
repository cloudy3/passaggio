import Foundation

/// A timed piano event: one note, or a chord when `notes` has several entries.
public struct NoteEvent: Hashable, Sendable {
    public enum Role: Hashable, Sendable { case cue, melody }

    public var start: TimeInterval
    public var duration: TimeInterval
    public var notes: [Int]
    public var velocity: UInt8
    public var role: Role

    public var end: TimeInterval { start + duration }
}

public struct ExerciseSequence: Sendable {
    public struct Repetition: Hashable, Sendable {
        public var root: Note
        public var start: TimeInterval
        /// When the singer starts (after the cue chord).
        public var melodyStart: TimeInterval
    }

    public var events: [NoteEvent]
    public var repetitions: [Repetition]
    public var duration: TimeInterval

    /// The repetition playing at `time`, for showing "now on: C4" during playback.
    public func repetition(at time: TimeInterval) -> Repetition? {
        repetitions.last { $0.start <= time }
    }
}

/// Turns an `ExerciseSpec` into timed events. Pure, so the audio layer only has to play them.
public enum ExerciseSequencer {
    /// Fraction of each note's slot that sounds; the gap keeps repeated pitches distinct.
    static let articulation = 0.92
    static let cueVelocity: UInt8 = 72
    static let melodyVelocity: UInt8 = 92

    public static func sequence(for spec: ExerciseSpec) throws -> ExerciseSequence {
        let roots = try spec.roots()
        let beat = 60 / spec.tempo
        let offsets = spec.pattern.offsets
        let beats = spec.pattern.beats
        let pianoShift = 12 * spec.pianoOctaveShift

        var events: [NoteEvent] = []
        var repetitions: [ExerciseSequence.Repetition] = []
        var time: TimeInterval = 0

        for root in roots {
            let repStart = time
            if spec.playsCueChord {
                // Root-position major triad, the "here's your key" chord a teacher plays.
                let chord = [0, 4, 7].map { root.midi + $0 + pianoShift }
                events.append(NoteEvent(
                    start: time,
                    duration: spec.cueBeats * beat * articulation,
                    notes: chord,
                    velocity: cueVelocity,
                    role: .cue
                ))
                time += spec.cueBeats * beat
            }
            let melodyStart = time
            for (offset, length) in zip(offsets, beats) {
                events.append(NoteEvent(
                    start: time,
                    duration: length * beat * articulation,
                    notes: [root.midi + offset + pianoShift],
                    velocity: melodyVelocity,
                    role: .melody
                ))
                time += length * beat
            }
            time += spec.restBeats * beat
            repetitions.append(.init(root: root, start: repStart, melodyStart: melodyStart))
        }

        return ExerciseSequence(events: events, repetitions: repetitions, duration: time)
    }
}
