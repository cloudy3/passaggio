import Foundation
import SwiftData
import PassaggioCore

// Enums are stored as raw strings with typed computed accessors. SwiftData can
// persist Codable enums directly, but raw strings keep #Predicate queries simple
// and make the backup JSON self-describing.

nonisolated enum ProcessingStatus: String, Codable, Sendable {
    case imported
    case transcribing
    case needsSpeakers      // transcribed, but no segment is labelled as the teacher yet
    case analyzing
    case analyzed
    case failed
}

@Model
final class Lesson {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var notes: String
    /// File name inside `FileStore.recordings`.
    var fileName: String
    var importedAt: Date
    /// Peak amplitude per bucket, 0...1, as packed Float32.
    @Attribute(.externalStorage) var waveformData: Data
    var statusRaw: String
    var lastError: String?
    /// `LessonStyle`. Declared with a default so lessons saved before it existed migrate as singing.
    var styleRaw: String = LessonStyle.singing.rawValue

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.lesson)
    var segments: [TranscriptSegment] = []
    @Relationship(deleteRule: .cascade, inverse: \KeyPoint.lesson)
    var keyPoints: [KeyPoint] = []
    @Relationship(deleteRule: .cascade, inverse: \PracticeClip.lesson)
    var clips: [PracticeClip] = []

    init(id: UUID = UUID(), title: String, date: Date, duration: TimeInterval, fileName: String, waveform: [Float]) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.notes = ""
        self.fileName = fileName
        self.importedAt = .now
        self.waveformData = Lesson.pack(waveform)
        self.statusRaw = ProcessingStatus.imported.rawValue
    }

    var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .imported }
        set { statusRaw = newValue.rawValue }
    }

    var style: LessonStyle {
        get { LessonStyle(rawValue: styleRaw) ?? .singing }
        set { styleRaw = newValue.rawValue }
    }

    var fileURL: URL { FileStore.recordings.appendingPathComponent(fileName) }

    var waveform: [Float] {
        get { Lesson.unpack(waveformData) }
        set { waveformData = Lesson.pack(newValue) }
    }

    var sortedSegments: [TranscriptSegment] { segments.sorted { $0.start < $1.start } }
    var sortedKeyPoints: [KeyPoint] { keyPoints.sorted { $0.timestamp < $1.timestamp } }

    nonisolated static func pack(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    nonisolated static func unpack(_ data: Data) -> [Float] {
        // Copy rather than bind: Data's storage isn't guaranteed to be Float-aligned.
        var values = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return values
    }
}

@Model
final class TranscriptSegment {
    var start: TimeInterval
    var end: TimeInterval
    var speaker: String
    var roleRaw: String
    var text: String
    var lesson: Lesson?

    init(start: TimeInterval, end: TimeInterval, speaker: String, role: SpeakerRole, text: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.roleRaw = role.rawValue
        self.text = text
    }

    var role: SpeakerRole {
        get { SpeakerRole(rawValue: roleRaw) ?? .unknown }
        set { roleRaw = newValue.rawValue }
    }
}

@Model
final class KeyPoint {
    @Attribute(.unique) var id: UUID
    var themeRaw: String
    var summary: String
    var quote: String
    var timestamp: TimeInterval
    var lesson: Lesson?
    var topic: FeedbackTopic?
    var exercises: [RoutineExercise] = []

    init(id: UUID = UUID(), theme: Theme, summary: String, quote: String, timestamp: TimeInterval) {
        self.id = id
        self.themeRaw = theme.rawValue
        self.summary = summary
        self.quote = quote
        self.timestamp = timestamp
    }

    var theme: Theme {
        get { Theme(rawValue: themeRaw) ?? .tensionHabits }
        set { themeRaw = newValue.rawValue }
    }
}

/// Feedback that recurs across lessons: every key point making the same correction
/// belongs to one topic.
@Model
final class FeedbackTopic {
    @Attribute(.unique) var id: UUID
    var themeRaw: String
    var title: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \KeyPoint.topic)
    var keyPoints: [KeyPoint] = []
    @Relationship(deleteRule: .nullify, inverse: \RoutineExercise.topic)
    var exercises: [RoutineExercise] = []

    init(id: UUID = UUID(), theme: Theme, title: String) {
        self.id = id
        self.themeRaw = theme.rawValue
        self.title = title
        self.createdAt = .now
    }

    var theme: Theme { Theme(rawValue: themeRaw) ?? .tensionHabits }

    /// Distinct lessons the topic came up in, newest first.
    var lessons: [Lesson] {
        var seen = Set<UUID>()
        return keyPoints
            .compactMap(\.lesson)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
    }

    var lastSeen: Date? { lessons.first?.date }

    /// Topics only collect points from lessons of one style (see `LessonProcessor.analyze`).
    var style: LessonStyle { keyPoints.lazy.compactMap(\.lesson).first?.style ?? .singing }

    /// Key points newest lesson first.
    var sortedKeyPoints: [KeyPoint] {
        keyPoints.sorted { ($0.lesson?.date ?? .distantPast) > ($1.lesson?.date ?? .distantPast) }
    }
}

/// A few seconds of a known voice, sent with every transcription request.
@Model
final class SpeakerReference {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    /// WAV file inside `FileStore.references`.
    var fileName: String
    var duration: TimeInterval
    var createdAt: Date

    init(id: UUID = UUID(), role: SpeakerRole, fileName: String, duration: TimeInterval) {
        self.id = id
        self.roleRaw = role.rawValue
        self.fileName = fileName
        self.duration = duration
        self.createdAt = .now
    }

    var role: SpeakerRole { SpeakerRole(rawValue: roleRaw) ?? .unknown }
    var fileURL: URL { FileStore.references.appendingPathComponent(fileName) }
}

/// A named stretch of a lesson recording, played on a loop for practice.
@Model
final class PracticeClip {
    @Attribute(.unique) var id: UUID
    var name: String
    var start: TimeInterval
    var end: TimeInterval
    var createdAt: Date
    var lesson: Lesson?

    init(id: UUID = UUID(), name: String, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.createdAt = .now
    }

    var duration: TimeInterval { end - start }
    var trackReference: String { "clip:\(id.uuidString)" }
}

/// Saved parameters for a generated exercise track.
@Model
final class GeneratorPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var specData: Data
    var isBuiltIn: Bool
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, spec: ExerciseSpec, isBuiltIn: Bool = false, sortOrder: Int = 1_000) {
        self.id = id
        self.name = name
        self.specData = (try? JSONEncoder().encode(spec)) ?? Data()
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    var spec: ExerciseSpec {
        get { (try? JSONDecoder().decode(ExerciseSpec.self, from: specData)) ?? ExerciseSpec() }
        set { specData = (try? JSONEncoder().encode(newValue)) ?? specData }
    }

    var trackReference: String { "preset:\(id.uuidString)" }
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var lengthMinutes: Int
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise] = []
    @Relationship(deleteRule: .cascade, inverse: \PracticeSession.routine)
    var sessions: [PracticeSession] = []

    init(id: UUID = UUID(), lengthMinutes: Int) {
        self.id = id
        self.createdAt = .now
        self.lengthMinutes = lengthMinutes
    }

    var sortedExercises: [RoutineExercise] { exercises.sorted { $0.order < $1.order } }
    var lastPracticed: Date? { sessions.map(\.date).max() }
}

@Model
final class RoutineExercise {
    @Attribute(.unique) var id: UUID
    var order: Int
    var title: String
    var instructions: String
    var goal: String
    var minutes: Int
    var themeRaw: String
    /// "preset:<uuid>" or "clip:<uuid>", or nil when the exercise has no track.
    var trackReference: String?
    var routine: Routine?
    var topic: FeedbackTopic?
    @Relationship(deleteRule: .nullify, inverse: \KeyPoint.exercises)
    var sourceKeyPoints: [KeyPoint] = []

    init(id: UUID = UUID(), order: Int, title: String, instructions: String, goal: String, minutes: Int, theme: Theme, trackReference: String?) {
        self.id = id
        self.order = order
        self.title = title
        self.instructions = instructions
        self.goal = goal
        self.minutes = minutes
        self.themeRaw = theme.rawValue
        self.trackReference = trackReference
    }

    var theme: Theme { Theme(rawValue: themeRaw) ?? .tensionHabits }

    /// Source feedback, newest lesson first.
    var sortedSources: [KeyPoint] {
        sourceKeyPoints.sorted { ($0.lesson?.date ?? .distantPast) > ($1.lesson?.date ?? .distantPast) }
    }
}

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var routine: Routine?

    init(id: UUID = UUID(), date: Date = .now) {
        self.id = id
        self.date = date
    }
}

enum PassaggioSchema {
    static let models: [any PersistentModel.Type] = [
        Lesson.self, TranscriptSegment.self, KeyPoint.self, FeedbackTopic.self,
        SpeakerReference.self, PracticeClip.self, GeneratorPreset.self,
        Routine.self, RoutineExercise.self, PracticeSession.self,
    ]
}
