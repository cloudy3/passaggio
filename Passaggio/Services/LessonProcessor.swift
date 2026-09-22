import Foundation
import Observation
import PassaggioCore
import SwiftData

/// Runs the transcribe → key points → topics pipeline for a lesson and reports progress.
@Observable
final class LessonProcessor {
    struct Progress: Equatable {
        var message: String
        /// 0...1, or nil when indeterminate.
        var fraction: Double?
    }

    private(set) var progress: [UUID: Progress] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func isRunning(_ lesson: Lesson) -> Bool { tasks[lesson.id] != nil }

    /// Transcribes (if needed) and analyses. Safe to call again after a failure.
    func process(_ lesson: Lesson, context: ModelContext, retranscribe: Bool = false) {
        guard tasks[lesson.id] == nil else { return }
        let id = lesson.id
        tasks[id] = Task {
            defer {
                tasks[id] = nil
                progress[id] = nil
            }
            do {
                if retranscribe || lesson.segments.isEmpty {
                    try await transcribe(lesson, context: context)
                }
                guard lesson.segments.contains(where: { $0.role == .teacher }) else {
                    // Without reference clips the model labels speakers "A", "B"; the
                    // user picks which one is the teacher before analysis can run.
                    lesson.status = .needsSpeakers
                    try context.save()
                    return
                }
                try await analyze(lesson, context: context)
            } catch is CancellationError {
                lesson.status = lesson.segments.isEmpty ? .imported : .needsSpeakers
            } catch {
                lesson.status = .failed
                lesson.lastError = error.localizedDescription
            }
            try? context.save()
        }
    }

    func cancel(_ lesson: Lesson) {
        tasks[lesson.id]?.cancel()
    }

    /// Re-runs key point extraction only (e.g. after changing speaker labels or model).
    func reanalyze(_ lesson: Lesson, context: ModelContext) {
        process(lesson, context: context, retranscribe: false)
    }

    // MARK: - Transcription

    private func transcribe(_ lesson: Lesson, context: ModelContext) async throws {
        let client = try settings.makeTranscriptionClient()
        lesson.status = .transcribing
        lesson.lastError = nil
        progress[lesson.id] = Progress(message: "Preparing audio…", fraction: nil)

        let analysis = try await AudioAnalysis.analyze(url: lesson.fileURL)
        let planner = ChunkPlanner()
        let chunks = planner.plan(duration: analysis.duration, envelope: analysis.envelope, hop: analysis.hop)
        let references = try loadReferences(context: context)

        let scratch = try FileStore.makeTemporaryDirectory()
        defer { FileStore.removeIfPresent(scratch) }

        var results: [(chunk: AudioChunk, response: DiarizedTranscription)] = []
        var pending = chunks
        var completedSeconds: TimeInterval = 0
        var splits = 0

        while !pending.isEmpty {
            try Task.checkCancellation()
            let chunk = pending.removeFirst()
            let fraction = completedSeconds / max(analysis.duration, 1)
            progress[lesson.id] = Progress(
                message: "Transcribing \(formatTimestamp(chunk.nominalStart))–\(formatTimestamp(chunk.nominalEnd))",
                fraction: fraction
            )

            let chunkURL = scratch.appendingPathComponent("chunk-\(results.count)-\(splits).m4a")
            try await AudioExport.exportM4A(from: lesson.fileURL, range: chunk.audioStart...chunk.audioEnd, to: chunkURL)
            let audio = try Data(contentsOf: chunkURL)
            let response = try await client.transcribe(audio: audio, filename: chunkURL.lastPathComponent, references: references)
            FileStore.removeIfPresent(chunkURL)

            // The model stops at 2,000 output tokens. If a chunk hit that, halve it and
            // try again rather than silently losing the rest of the chunk.
            if response.isLikelyTruncated, chunk.nominalEnd - chunk.nominalStart > 60, splits < 8 {
                splits += 1
                pending.insert(contentsOf: planner.split(chunk, duration: analysis.duration,
                                                         envelope: analysis.envelope, hop: analysis.hop), at: 0)
                continue
            }
            results.append((chunk, response))
            completedSeconds += chunk.nominalEnd - chunk.nominalStart
        }

        // Re-index in timeline order: split halves share their parent's index.
        let ordered = results
            .sorted { $0.chunk.nominalStart < $1.chunk.nominalStart }
            .enumerated()
            .map { index, item in
                var chunk = item.chunk
                chunk.index = index
                return (chunk: chunk, response: item.response)
            }
        let merged = TranscriptMerger.merge(ordered)

        for segment in lesson.segments { context.delete(segment) }
        for item in merged {
            let segment = TranscriptSegment(start: item.start, end: item.end, speaker: item.speaker, role: item.role, text: item.text)
            context.insert(segment)
            segment.lesson = lesson
        }
        try context.save()
    }

    private func loadReferences(context: ModelContext) throws -> [SpeakerReferenceClip] {
        let stored = try context.fetch(FetchDescriptor<SpeakerReference>(sortBy: [SortDescriptor(\.createdAt)]))
        return stored.compactMap { reference in
            guard let name = reference.role.referenceName,
                  let data = try? Data(contentsOf: reference.fileURL) else { return nil }
            return SpeakerReferenceClip(name: name, audio: data, mimeType: "audio/wav")
        }
    }

    // MARK: - Analysis

    private func analyze(_ lesson: Lesson, context: ModelContext) async throws {
        let analyst = FeedbackAnalyst(provider: try settings.makeLLMProvider())
        lesson.status = .analyzing
        lesson.lastError = nil
        progress[lesson.id] = Progress(message: "Finding your teacher’s key points…", fraction: nil)

        let teacherSegments = lesson.sortedSegments
            .filter { $0.role == .teacher }
            .map { TimedSegment(start: $0.start, end: $0.end, speaker: $0.speaker, role: .teacher, text: $0.text) }
        let extracted = try await analyst.extractKeyPoints(from: teacherSegments)
        try Task.checkCancellation()

        progress[lesson.id] = Progress(message: "Matching with earlier lessons…", fraction: nil)
        // Offer every topic except ones only this lesson contributed to, so re-analysing
        // a lesson doesn't match its points against themselves.
        let allTopics = try context.fetch(FetchDescriptor<FeedbackTopic>())
        let candidates = allTopics.filter { topic in
            topic.keyPoints.contains { $0.lesson?.id != lesson.id }
        }
        let candidateInputs = candidates.map { topic in
            TopicCandidate(
                id: topic.id,
                theme: topic.theme,
                title: topic.title,
                examples: topic.sortedKeyPoints.prefix(2).map(\.summary)
            )
        }
        let assignments: [TopicAssignment]
        do {
            assignments = try await analyst.assignTopics(points: extracted, existing: candidateInputs)
        } catch let error as APIError where !error.isTransient {
            throw error
        } catch {
            // Topic matching is a refinement; fall back to local matching rather than
            // losing the lesson's key points over a hiccup.
            assignments = extracted.map { RecurrenceMatcher.assign($0, to: candidateInputs) }
        }
        try Task.checkCancellation()

        // Replace this lesson's points.
        for point in lesson.keyPoints { context.delete(point) }
        lesson.keyPoints = []

        let topicsByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var newTopics: [String: FeedbackTopic] = [:]
        for (point, assignment) in zip(extracted, assignments) {
            let keyPoint = KeyPoint(theme: point.theme, summary: point.summary, quote: point.quote, timestamp: point.timestamp)
            context.insert(keyPoint)
            keyPoint.lesson = lesson
            switch assignment {
            case .existing(let id):
                keyPoint.topic = topicsByID[id]
            case .new(let title):
                let key = "\(point.theme.rawValue)|\(title.lowercased())"
                let topic = newTopics[key] ?? {
                    let topic = FeedbackTopic(theme: point.theme, title: title)
                    context.insert(topic)
                    return topic
                }()
                newTopics[key] = topic
                keyPoint.topic = topic
            }
        }
        lesson.status = .analyzed
        // Save first so relationship arrays no longer include the deleted points.
        try context.save()
        try Self.deleteOrphanTopics(context: context)
        try context.save()
    }

    /// Topics left with no key points (after re-analysis or deleting a lesson).
    static func deleteOrphanTopics(context: ModelContext) throws {
        for topic in try context.fetch(FetchDescriptor<FeedbackTopic>()) where topic.keyPoints.isEmpty {
            context.delete(topic)
        }
    }
}
