import Foundation
import PassaggioCore
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let passaggioBackup = UTType(exportedAs: "sg.cloudy3.passaggio.backup", conformingTo: .data)
}

/// Export and restore of everything the app stores, as one `.passaggiobackup` file.
///
/// Layout (a tar archive, see `TarArchive`):
///   data.json                      every model as JSON (`BackupPayload`)
///   recordings/<file>.m4a          lesson audio
///   references/<file>.wav          speaker reference clips
///
/// The database travels as JSON rather than as the SQLite file: copying a live
/// SQLite store risks capturing it mid-write (WAL), and JSON survives future
/// schema changes. API keys are deliberately not included.
enum BackupService {
    nonisolated static let formatVersion = 1
    nonisolated static let payloadName = "data.json"

    nonisolated enum BackupError: Error, LocalizedError {
        case missingPayload
        case unsupportedVersion(Int)
        case missingFile(String)

        var errorDescription: String? {
            switch self {
            case .missingPayload: "This file isn’t a Passaggio backup."
            case .unsupportedVersion(let version): "This backup (format \(version)) was made by a newer version of Passaggio."
            case .missingFile(let name): "The backup is missing \(name)."
            }
        }
    }

    // MARK: Export

    /// Writes the backup to a temporary file and returns its URL; the caller moves it
    /// to Files with `.fileMover` so a multi-gigabyte archive is never read into memory.
    static func makeBackup(context: ModelContext) async throws -> URL {
        let payload = try BackupPayload(context: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(payload)

        var files: [(path: String, source: URL)] = []
        for lesson in payload.lessons {
            files.append(("recordings/\(lesson.fileName)", FileStore.recordings.appendingPathComponent(lesson.fileName)))
        }
        for reference in payload.references {
            files.append(("references/\(reference.fileName)", FileStore.references.appendingPathComponent(reference.fileName)))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: .now)
        return try await writeArchive(json: json, files: files, name: "Passaggio-\(stamp).passaggiobackup")
    }

    @concurrent
    nonisolated private static func writeArchive(json: Data, files: [(path: String, source: URL)], name: String) async throws -> URL {
        let directory = try FileStore.makeTemporaryDirectory()
        let payloadURL = directory.appendingPathComponent(payloadName)
        try json.write(to: payloadURL)
        for file in files where !FileManager.default.fileExists(atPath: file.source.path) {
            throw BackupError.missingFile(file.path)
        }
        let archive = directory.appendingPathComponent(name)
        try TarArchive.write(entries: [(payloadName, payloadURL)] + files, to: archive)
        FileStore.removeIfPresent(payloadURL)
        return archive
    }

    // MARK: Restore

    nonisolated struct PreparedRestore: Sendable {
        var directory: URL
        var payload: BackupPayload
    }

    /// Unpacks and validates a backup without touching current data.
    @concurrent
    nonisolated static func prepareRestore(from archive: URL) async throws -> PreparedRestore {
        let scoped = archive.startAccessingSecurityScopedResource()
        defer { if scoped { archive.stopAccessingSecurityScopedResource() } }

        let directory = try FileStore.makeTemporaryDirectory()
        do {
            try TarArchive.extract(from: archive, into: directory)
            let payloadURL = directory.appendingPathComponent(payloadName)
            guard FileManager.default.fileExists(atPath: payloadURL.path) else { throw BackupError.missingPayload }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(BackupPayload.self, from: Data(contentsOf: payloadURL))
            guard payload.formatVersion <= formatVersion else { throw BackupError.unsupportedVersion(payload.formatVersion) }

            for lesson in payload.lessons {
                let path = "recordings/\(lesson.fileName)"
                guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path) else {
                    throw BackupError.missingFile(path)
                }
            }
            return PreparedRestore(directory: directory, payload: payload)
        } catch {
            FileStore.removeIfPresent(directory)
            throw error
        }
    }

    /// Replaces all current data with the prepared backup.
    static func restore(_ prepared: PreparedRestore, context: ModelContext) throws {
        defer { FileStore.removeIfPresent(prepared.directory) }

        // Files first: if moving fails, the database is still intact.
        try replaceDirectory(FileStore.recordings, with: prepared.directory.appendingPathComponent("recordings"))
        try replaceDirectory(FileStore.references, with: prepared.directory.appendingPathComponent("references"))
        FileStore.removeIfPresent(FileStore.renders)
        try FileStore.prepare()

        try deleteAll(RoutineExercise.self, context: context)
        try deleteAll(PracticeSession.self, context: context)
        try deleteAll(Routine.self, context: context)
        try deleteAll(KeyPoint.self, context: context)
        try deleteAll(TranscriptSegment.self, context: context)
        try deleteAll(PracticeClip.self, context: context)
        try deleteAll(Lesson.self, context: context)
        try deleteAll(FeedbackTopic.self, context: context)
        try deleteAll(SpeakerReference.self, context: context)
        try deleteAll(GeneratorPreset.self, context: context)
        try context.save()

        prepared.payload.insert(into: context)
        try context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }

    private static func replaceDirectory(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        if fm.fileExists(atPath: source.path) {
            try fm.moveItem(at: source, to: target)
        } else {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Payload

nonisolated struct BackupPayload: Codable, Sendable {
    struct SegmentDTO: Codable, Sendable {
        var start: TimeInterval, end: TimeInterval, speaker: String, role: String, text: String
    }
    struct KeyPointDTO: Codable, Sendable {
        var id: UUID, theme: String, summary: String, quote: String, timestamp: TimeInterval, topicID: UUID?
    }
    struct ClipDTO: Codable, Sendable {
        var id: UUID, name: String, start: TimeInterval, end: TimeInterval, createdAt: Date
    }
    struct LessonDTO: Codable, Sendable {
        var id: UUID, title: String, date: Date, duration: TimeInterval, notes: String
        var fileName: String, importedAt: Date, waveform: Data, status: String, lastError: String?
        /// Missing from backups made before lesson styles existed; those restore as singing.
        var style: String?
        var segments: [SegmentDTO], keyPoints: [KeyPointDTO], clips: [ClipDTO]
    }
    struct TopicDTO: Codable, Sendable {
        var id: UUID, theme: String, title: String, createdAt: Date
    }
    struct ReferenceDTO: Codable, Sendable {
        var id: UUID, role: String, fileName: String, duration: TimeInterval, createdAt: Date
    }
    struct PresetDTO: Codable, Sendable {
        var id: UUID, name: String, spec: Data, isBuiltIn: Bool, sortOrder: Int, createdAt: Date
    }
    struct ExerciseDTO: Codable, Sendable {
        var id: UUID, order: Int, title: String, instructions: String, goal: String, minutes: Int
        var theme: String, trackReference: String?, topicID: UUID?, sourceKeyPointIDs: [UUID]
    }
    struct RoutineDTO: Codable, Sendable {
        var id: UUID, createdAt: Date, lengthMinutes: Int
        var exercises: [ExerciseDTO], sessions: [SessionDTO]
    }
    struct SessionDTO: Codable, Sendable {
        var id: UUID, date: Date
    }

    var formatVersion: Int
    var createdAt: Date
    var appVersion: String
    var lessons: [LessonDTO]
    var topics: [TopicDTO]
    var references: [ReferenceDTO]
    var presets: [PresetDTO]
    var routines: [RoutineDTO]
}

extension BackupPayload {
    @MainActor
    init(context: ModelContext) throws {
        formatVersion = BackupService.formatVersion
        createdAt = .now
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

        lessons = try context.fetch(FetchDescriptor<Lesson>()).map { lesson in
            LessonDTO(
                id: lesson.id, title: lesson.title, date: lesson.date, duration: lesson.duration,
                notes: lesson.notes, fileName: lesson.fileName, importedAt: lesson.importedAt,
                waveform: lesson.waveformData, status: lesson.statusRaw, lastError: lesson.lastError,
                style: lesson.styleRaw,
                segments: lesson.sortedSegments.map {
                    SegmentDTO(start: $0.start, end: $0.end, speaker: $0.speaker, role: $0.roleRaw, text: $0.text)
                },
                keyPoints: lesson.keyPoints.map {
                    KeyPointDTO(id: $0.id, theme: $0.themeRaw, summary: $0.summary, quote: $0.quote,
                                timestamp: $0.timestamp, topicID: $0.topic?.id)
                },
                clips: lesson.clips.map {
                    ClipDTO(id: $0.id, name: $0.name, start: $0.start, end: $0.end, createdAt: $0.createdAt)
                }
            )
        }
        topics = try context.fetch(FetchDescriptor<FeedbackTopic>()).map {
            TopicDTO(id: $0.id, theme: $0.themeRaw, title: $0.title, createdAt: $0.createdAt)
        }
        references = try context.fetch(FetchDescriptor<SpeakerReference>()).map {
            ReferenceDTO(id: $0.id, role: $0.roleRaw, fileName: $0.fileName, duration: $0.duration, createdAt: $0.createdAt)
        }
        presets = try context.fetch(FetchDescriptor<GeneratorPreset>()).map {
            PresetDTO(id: $0.id, name: $0.name, spec: $0.specData, isBuiltIn: $0.isBuiltIn, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
        }
        routines = try context.fetch(FetchDescriptor<Routine>()).map { routine in
            RoutineDTO(
                id: routine.id, createdAt: routine.createdAt, lengthMinutes: routine.lengthMinutes,
                exercises: routine.sortedExercises.map {
                    ExerciseDTO(id: $0.id, order: $0.order, title: $0.title, instructions: $0.instructions,
                                goal: $0.goal, minutes: $0.minutes, theme: $0.themeRaw,
                                trackReference: $0.trackReference, topicID: $0.topic?.id,
                                sourceKeyPointIDs: $0.sourceKeyPoints.map(\.id))
                },
                sessions: routine.sessions.map { SessionDTO(id: $0.id, date: $0.date) }
            )
        }
    }

    @MainActor
    func insert(into context: ModelContext) {
        var topicsByID: [UUID: FeedbackTopic] = [:]
        for dto in topics {
            let topic = FeedbackTopic(id: dto.id, theme: Theme(rawValue: dto.theme) ?? .tensionHabits, title: dto.title)
            topic.createdAt = dto.createdAt
            context.insert(topic)
            topicsByID[dto.id] = topic
        }

        var keyPointsByID: [UUID: KeyPoint] = [:]
        for dto in lessons {
            let lesson = Lesson(id: dto.id, title: dto.title, date: dto.date, duration: dto.duration, fileName: dto.fileName, waveform: [])
            lesson.waveformData = dto.waveform
            lesson.notes = dto.notes
            lesson.importedAt = dto.importedAt
            lesson.statusRaw = dto.status
            lesson.lastError = dto.lastError
            lesson.styleRaw = dto.style ?? LessonStyle.singing.rawValue
            context.insert(lesson)

            for segment in dto.segments {
                let model = TranscriptSegment(start: segment.start, end: segment.end, speaker: segment.speaker,
                                              role: SpeakerRole(rawValue: segment.role) ?? .unknown, text: segment.text)
                context.insert(model)
                model.lesson = lesson
            }
            for point in dto.keyPoints {
                let model = KeyPoint(id: point.id, theme: Theme(rawValue: point.theme) ?? .tensionHabits,
                                     summary: point.summary, quote: point.quote, timestamp: point.timestamp)
                context.insert(model)
                model.lesson = lesson
                model.topic = point.topicID.flatMap { topicsByID[$0] }
                keyPointsByID[point.id] = model
            }
            for clip in dto.clips {
                let model = PracticeClip(id: clip.id, name: clip.name, start: clip.start, end: clip.end)
                model.createdAt = clip.createdAt
                context.insert(model)
                model.lesson = lesson
            }
        }

        for dto in references {
            let model = SpeakerReference(id: dto.id, role: SpeakerRole(rawValue: dto.role) ?? .unknown,
                                         fileName: dto.fileName, duration: dto.duration)
            model.createdAt = dto.createdAt
            context.insert(model)
        }

        for dto in presets {
            let model = GeneratorPreset(id: dto.id, name: dto.name, spec: ExerciseSpec(), isBuiltIn: dto.isBuiltIn, sortOrder: dto.sortOrder)
            model.specData = dto.spec
            model.createdAt = dto.createdAt
            context.insert(model)
        }

        for dto in routines {
            let routine = Routine(id: dto.id, lengthMinutes: dto.lengthMinutes)
            routine.createdAt = dto.createdAt
            context.insert(routine)
            for exercise in dto.exercises {
                let model = RoutineExercise(id: exercise.id, order: exercise.order, title: exercise.title,
                                            instructions: exercise.instructions, goal: exercise.goal,
                                            minutes: exercise.minutes, theme: Theme(rawValue: exercise.theme) ?? .tensionHabits,
                                            trackReference: exercise.trackReference)
                context.insert(model)
                model.routine = routine
                model.topic = exercise.topicID.flatMap { topicsByID[$0] }
                model.sourceKeyPoints = exercise.sourceKeyPointIDs.compactMap { keyPointsByID[$0] }
            }
            for session in dto.sessions {
                let model = PracticeSession(id: session.id, date: session.date)
                context.insert(model)
                model.routine = routine
            }
        }
    }
}
