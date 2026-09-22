import Foundation
import Testing
@testable import PassaggioCore

@Suite("Notes")
struct NoteTests {
    @Test func singerRangeMIDINumbers() {
        #expect(Note("D#2")?.midi == 39)
        #expect(Note("G#4")?.midi == 68)
        #expect(Note("C4")?.midi == 60)
        #expect(Note("F#4")?.midi == 66)
        #expect(Note.singerFloor.name == "D#2")
        #expect(Note.singerCeiling.name == "G#4")
    }

    @Test func parsesFlatsAndUnicodeAccidentals() {
        #expect(Note("Eb3") == Note("D#3"))
        #expect(Note("G♯4")?.midi == 68)
        #expect(Note("B♭2")?.midi == 46)
        #expect(Note("Cb4")?.midi == 59)
    }

    @Test(arguments: ["", "H4", "C", "C#", "4C", "C#x"])
    func rejectsMalformedNames(_ text: String) {
        #expect(Note(text) == nil)
    }

    @Test func nameRoundTripsAcrossPianoRange() {
        for midi in Note.lowestPiano.midi...Note.highestPiano.midi {
            let note = Note(midi: midi)
            #expect(Note(note.name) == note, "round trip failed for \(midi)")
        }
    }

    @Test func frequenciesAreEqualTempered() {
        #expect(abs(Note(midi: 69).frequency - 440) < 1e-9)
        #expect(abs(Note("C4")!.frequency - 261.6256) < 1e-3)
        // An octave doubles the frequency.
        #expect(abs(Note("A3")!.frequency * 2 - Note("A4")!.frequency) < 1e-9)
    }

    @Test func accessibilityNameIsSpoken() {
        #expect(Note.singerFloor.accessibilityName == "D sharp 2")
    }
}

@Suite("Patterns")
struct PatternTests {
    @Test func builtInIntervals() {
        #expect(ExercisePattern.fiveNoteScale.offsets == [0, 2, 4, 5, 7, 5, 4, 2, 0])
        #expect(ExercisePattern.arpeggio.offsets == [0, 4, 7, 12, 7, 4, 0])
        #expect(ExercisePattern.octaveSlide.offsets == [0, 12, 0])
        let major = ExercisePattern.majorScale.offsets
        #expect(major.first == 0 && major.max() == 12 && major.count == 15)
        // Whole-whole-half-whole-whole-whole-half on the way up.
        let ascending = Array(major.prefix(8))
        #expect(zip(ascending.dropFirst(), ascending).map { $0 - $1 } == [2, 2, 1, 2, 2, 2, 1])
    }

    @Test func beatsMatchNoteCountAndHoldTheLastNote() {
        for pattern in ExercisePattern.builtIn {
            #expect(pattern.beats.count == pattern.offsets.count)
        }
        #expect(ExercisePattern.fiveNoteScale.beats.last == 2)
    }

    @Test func customDegreesMatchBuiltIns() throws {
        #expect(try ExercisePattern.parseDegrees("1 3 5 8 5 3 1") == ExercisePattern.arpeggio.offsets)
        #expect(try ExercisePattern.parseDegrees("1-2-3-4-5-4-3-2-1") == ExercisePattern.fiveNoteScale.offsets)
        #expect(ExercisePattern.custom("1, 5, 1").offsets == [0, 7, 0])
    }

    @Test func customDegreesSupportAccidentalsAndCompoundIntervals() throws {
        #expect(try ExercisePattern.parseDegrees("1 b3 #4 9 15") == [0, 3, 6, 14, 24])
    }

    @Test func customDegreesRejectGarbage() {
        #expect(throws: ExercisePattern.ParseError.empty) { try ExercisePattern.parseDegrees("  ") }
        #expect(throws: ExercisePattern.ParseError.invalidToken("x")) { try ExercisePattern.parseDegrees("1 x 3") }
        #expect(throws: ExercisePattern.ParseError.invalidToken("0")) { try ExercisePattern.parseDegrees("0") }
        #expect(ExercisePattern.custom("nope").offsets.isEmpty)
    }
}

@Suite("Exercise roots")
struct ExerciseRootTests {
    @Test func fullRangeWalksUpAndBack() throws {
        let spec = ExerciseSpec.fullRange(.fiveNoteScale)
        let roots = try spec.roots().map(\.midi)
        // Root 39 (D#2) to 61 (C#4): C#4 + a fifth = G#4, the ceiling.
        #expect(roots.first == 39)
        #expect(roots.max() == 61)
        #expect(roots.last == 39)
        #expect(roots.count == 23 + 22)
        // Every sung note stays inside the range.
        for root in roots {
            for offset in spec.pattern.offsets {
                #expect((39...68).contains(root + offset))
            }
        }
    }

    @Test func stepControlsSpacing() throws {
        var spec = ExerciseSpec.fullRange(.arpeggio)
        spec.direction = .ascending
        spec.step = 2
        let roots = try spec.roots().map(\.midi)
        #expect(zip(roots.dropFirst(), roots).allSatisfy { $0 - $1 == 2 })
        #expect(roots.first == 39)
        #expect(roots.last! + 12 <= 68)
    }

    @Test func descendingStartsAtStartNote() throws {
        var spec = ExerciseSpec.fullRange(.fiveNoteScale)
        spec.direction = .descending
        spec.startNote = Note("A3")!
        let roots = try spec.roots().map(\.midi)
        #expect(roots.first == 57)
        #expect(roots.last == 39)
    }

    @Test func startNoteIsClampedIntoTheValidRange() throws {
        var spec = ExerciseSpec.fullRange(.fiveNoteScale)
        spec.direction = .ascending
        spec.startNote = Note("C6")!
        #expect(try spec.roots().map(\.midi) == [61])
        spec.startNote = Note("C1")!
        #expect(try spec.roots().first?.midi == 39)
    }

    @Test(arguments: ExercisePattern.builtIn)
    func passaggioPresetPeaksInsideC4ToFSharp4(_ pattern: ExercisePattern) throws {
        let spec = ExerciseSpec.passaggioFocus(pattern)
        let roots = try spec.roots()
        let span = pattern.offsets.max()!
        let peaks = roots.map { $0.midi + span }
        #expect(peaks.first == 60)
        #expect(peaks.max() == 66)
        #expect(peaks.allSatisfy { (60...66).contains($0) })
        #expect(peaks.count == 7 + 6)
    }

    @Test func validationErrors() {
        var spec = ExerciseSpec()
        spec.floor = Note("C4")!
        spec.ceiling = Note("E4")!
        #expect(throws: ExerciseSpec.ValidationError.patternDoesNotFit(span: 7, available: 4)) { try spec.roots() }

        spec = ExerciseSpec()
        spec.floor = Note("C4")!
        spec.ceiling = Note("C3")!
        #expect(throws: ExerciseSpec.ValidationError.invalidRange) { try spec.validate() }

        spec = ExerciseSpec()
        spec.step = 0
        #expect(throws: ExerciseSpec.ValidationError.invalidStep) { try spec.validate() }

        spec = ExerciseSpec()
        spec.tempo = 10
        #expect(throws: ExerciseSpec.ValidationError.invalidTempo) { try spec.validate() }

        spec = ExerciseSpec(pattern: .custom(""))
        #expect(throws: ExerciseSpec.ValidationError.emptyPattern) { try spec.validate() }
    }

    @Test func specRoundTripsThroughJSON() throws {
        let spec = ExerciseSpec(pattern: .custom("1 3 5"), startNote: Note("E3")!, tempo: 72, step: 2, direction: .descending)
        let decoded = try JSONDecoder().decode(ExerciseSpec.self, from: JSONEncoder().encode(spec))
        #expect(decoded == spec)
    }
}

@Suite("Sequencer")
struct SequencerTests {
    @Test func timingAtSixtyBPM() throws {
        var spec = ExerciseSpec.fullRange(.fiveNoteScale)
        spec.tempo = 60 // one beat per second
        spec.direction = .ascending
        spec.ceiling = Note(midi: 39 + 7 + 1) // exactly two repetitions
        let sequence = try ExerciseSequencer.sequence(for: spec)

        // Per repetition: 2-beat cue + 8 one-beat notes + a 2-beat final note + 1 beat rest.
        #expect(sequence.repetitions.count == 2)
        #expect(sequence.duration == 26)
        #expect(sequence.repetitions.map(\.start) == [0, 13])
        #expect(sequence.repetitions.map(\.melodyStart) == [2, 15])

        let first = sequence.events.filter { $0.start < 13 }
        #expect(first.count == 1 + 9)
        #expect(first[0].role == .cue)
        #expect(first[0].notes == [39, 43, 46]) // D#, G, A# — D# major triad
        #expect(first.dropFirst().map { $0.notes[0] } == [39, 41, 43, 44, 46, 44, 43, 41, 39])
        #expect(first.dropFirst().map(\.start) == [2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(abs(first.last!.duration - 2 * ExerciseSequencer.articulation) < 1e-9)
    }

    @Test func withoutCueTheMelodyStartsImmediately() throws {
        var spec = ExerciseSpec.passaggioFocus(.arpeggio)
        spec.playsCueChord = false
        let sequence = try ExerciseSequencer.sequence(for: spec)
        #expect(sequence.events.allSatisfy { $0.role == .melody })
        #expect(sequence.repetitions.first?.melodyStart == 0)
    }

    @Test func pianoOctaveShiftMovesEveryNote() throws {
        var spec = ExerciseSpec.passaggioFocus(.octaveSlide)
        let base = try ExerciseSequencer.sequence(for: spec)
        spec.pianoOctaveShift = 1
        let shifted = try ExerciseSequencer.sequence(for: spec)
        #expect(zip(base.events, shifted.events).allSatisfy { a, b in zip(a.notes, b.notes).allSatisfy { $1 - $0 == 12 } })
        // Repetition roots report the sung pitch, not the piano's.
        #expect(base.repetitions.map(\.root) == shifted.repetitions.map(\.root))
    }

    @Test func eventsDoNotOverlapWithinTheMelody() throws {
        let sequence = try ExerciseSequencer.sequence(for: .fullRange(.majorScale))
        let melody = sequence.events.filter { $0.role == .melody }
        for (a, b) in zip(melody, melody.dropFirst()) {
            #expect(a.end <= b.start + 1e-9)
        }
        #expect(sequence.repetition(at: sequence.duration - 0.1)?.root == Note.singerFloor)
    }
}
