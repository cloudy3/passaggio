import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Passaggio
@testable import PassaggioCore

/// App-level tests that need Apple frameworks (SwiftData, AVFoundation, Keychain).
/// Pure logic is tested in PassaggioCore.
@MainActor
@Suite("App integration", .serialized)
struct PassaggioAppTests {
    func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(PassaggioSchema.models), configurations: configuration)
        return ModelContext(container)
    }

    @Test func builtInPresetsSeedOnce() throws {
        let context = try makeContext()
        try BuiltInPresets.seedIfNeeded(context: context)
        try BuiltInPresets.seedIfNeeded(context: context)
        let presets = try context.fetch(FetchDescriptor<GeneratorPreset>())
        #expect(presets.count == ExercisePattern.builtIn.count * 2)
        let passaggio = try #require(presets.first { $0.name.hasPrefix("Passaggio · 5-note") })
        #expect(passaggio.spec.ceiling == .passaggioHigh)
    }

    @Test func backupPayloadRoundTripsEveryRelationship() throws {
        let source = try makeContext()
        let lesson = Lesson(title: "Lesson 1", date: .now, duration: 120, fileName: "a.m4a", waveform: [0, 0.5, 1])
        source.insert(lesson)
        let segment = TranscriptSegment(start: 1, end: 2, speaker: "teacher", role: .teacher, text: "Lift the palate.")
        source.insert(segment)
        segment.lesson = lesson
        let topic = FeedbackTopic(theme: .placementResonance, title: "Lift the soft palate")
        source.insert(topic)
        let point = KeyPoint(theme: .placementResonance, summary: "Lift the palate", quote: "Lift the palate.", timestamp: 1)
        source.insert(point)
        point.lesson = lesson
        point.topic = topic
        let clip = PracticeClip(name: "Lip trill", start: 10, end: 20)
        source.insert(clip)
        clip.lesson = lesson
        let routine = Routine(lengthMinutes: 15)
        source.insert(routine)
        let exercise = RoutineExercise(order: 0, title: "Palate", instructions: "…", goal: "…", minutes: 15,
                                       theme: .placementResonance, trackReference: clip.trackReference)
        source.insert(exercise)
        exercise.routine = routine
        exercise.topic = topic
        exercise.sourceKeyPoints = [point]
        let session = PracticeSession()
        source.insert(session)
        session.routine = routine
        try source.save()

        let payload = try BackupPayload(context: source)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: encoder.encode(payload))

        let target = try makeContext()
        decoded.insert(into: target)
        try target.save()

        let restoredLesson = try #require(try target.fetch(FetchDescriptor<Lesson>()).first)
        #expect(restoredLesson.id == lesson.id)
        #expect(restoredLesson.waveform == [0, 0.5, 1])
        #expect(restoredLesson.segments.count == 1)
        #expect(restoredLesson.keyPoints.first?.topic?.title == "Lift the soft palate")
        #expect(restoredLesson.clips.first?.name == "Lip trill")

        let restoredRoutine = try #require(try target.fetch(FetchDescriptor<Routine>()).first)
        #expect(restoredRoutine.sessions.count == 1)
        let restoredExercise = try #require(restoredRoutine.exercises.first)
        #expect(restoredExercise.sourceKeyPoints.first?.id == point.id)
        #expect(restoredExercise.topic?.id == topic.id)
        #expect(restoredExercise.trackReference == clip.trackReference)
    }

    @Test func rendersAnAudibleExerciseOfTheExpectedLength() async throws {
        var spec = ExerciseSpec.passaggioFocus(.fiveNoteScale)
        spec.tempo = 160 // keep the test quick
        FileStore.removeIfPresent(FileStore.renders)
        let url = try await ExerciseRenderer.renderedFile(for: spec)
        let sequence = try ExerciseSequencer.sequence(for: spec)

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(abs(seconds - (sequence.duration + ExerciseRenderer.tail)) < 0.05)

        let analysis = try await AudioAnalysis.analyze(url: url)
        #expect((analysis.envelope.max() ?? 0) > 0.01, "render is silent — SoundFont not loaded?")

        // Cached: a second call returns the same file without re-rendering.
        let again = try await ExerciseRenderer.renderedFile(for: spec)
        #expect(again == url)
    }

    @Test func exportsReferenceClipAsWAV() async throws {
        let spec = ExerciseSpec.passaggioFocus(.arpeggio)
        let source = try await ExerciseRenderer.renderedFile(for: spec)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ref-\(UUID()).wav")
        defer { FileStore.removeIfPresent(destination) }
        try await AudioExport.exportWAV(from: source, range: 1...5, to: destination)
        let file = try AVAudioFile(forReading: destination)
        #expect(abs(Double(file.length) / file.fileFormat.sampleRate - 4) < 0.01)
        #expect(file.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatLinearPCM)
    }

    @Test func referenceClipIsDownmixedToFitTheFormFieldLimit() async throws {
        let spec = ExerciseSpec.passaggioFocus(.arpeggio)
        let source = try await ExerciseRenderer.renderedFile(for: spec)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ref-\(UUID()).wav")
        defer { FileStore.removeIfPresent(destination) }
        try await AudioExport.exportWAV(from: source, range: 1...11, to: destination)
        let file = try AVAudioFile(forReading: destination)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        let clip = SpeakerReferenceClip(name: "teacher", audio: try Data(contentsOf: destination))
        #expect(!clip.exceedsFormFieldLimit)
    }

    @Test func keychainRoundTrip() throws {
        let keychain = KeychainStore(service: "sg.cloudy3.passaggio.tests")
        try keychain.save("  sk-test-123 \n", for: .openAI)
        #expect(keychain.read(.openAI) == "sk-test-123")
        try keychain.save("sk-new", for: .openAI)
        #expect(keychain.read(.openAI) == "sk-new")
        try keychain.delete(.openAI)
        #expect(keychain.read(.openAI) == nil)
    }
}
