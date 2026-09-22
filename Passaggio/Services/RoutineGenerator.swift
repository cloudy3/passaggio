import Foundation
import PassaggioCore
import SwiftData

/// Builds routines from accumulated feedback: the planner picks topics and minutes
/// (deterministic, tested in PassaggioCore), the model phrases each exercise from the
/// teacher's own words.
enum RoutineGenerator {
    nonisolated enum GenerationError: Error, LocalizedError {
        case noFeedbackYet

        var errorDescription: String? {
            "There’s no lesson feedback to build a routine from yet. Transcribe and analyse a lesson first."
        }
    }

    /// Creates a new routine, or regenerates `existing` in place (its practice history is kept).
    @discardableResult
    static func generate(
        lengthMinutes: Int,
        replacing existing: Routine? = nil,
        context: ModelContext,
        settings: AppSettings
    ) async throws -> Routine {
        let topics = try context.fetch(FetchDescriptor<FeedbackTopic>())
        let histories = topics.map { topic in
            TopicHistory(id: topic.id, theme: topic.theme, occurrences: topic.lessons.map(\.date))
        }
        let plan = RoutinePlanner().plan(topics: histories, lengthMinutes: lengthMinutes)
        guard !plan.isEmpty else { throw GenerationError.noFeedbackYet }

        let topicsByID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        let plannedTopics = plan.compactMap { topicsByID[$0.topicID] }
        let slots = zip(plan, plannedTopics).map { slot, topic in
            RoutineSlotContext(
                theme: topic.theme,
                topicTitle: topic.title,
                quotes: topic.sortedKeyPoints.map { $0.quote.isEmpty ? $0.summary : $0.quote },
                minutes: slot.minutes,
                occurrences: topic.lessons.count
            )
        }

        let tracks = try availableTracks(context: context)
        let analyst = FeedbackAnalyst(provider: try settings.makeLLMProvider())
        let drafts = try await analyst.draftRoutine(slots: slots, tracks: tracks)

        let routine: Routine
        if let existing {
            for exercise in existing.exercises { context.delete(exercise) }
            existing.exercises = []
            existing.lengthMinutes = lengthMinutes
            existing.createdAt = .now
            routine = existing
        } else {
            routine = Routine(lengthMinutes: lengthMinutes)
            context.insert(routine)
        }

        for (index, (slot, draft)) in zip(slots, drafts).enumerated() {
            let topic = plannedTopics[index]
            let exercise = RoutineExercise(
                order: index,
                title: draft.title,
                instructions: draft.instructions,
                goal: draft.goal,
                minutes: slot.minutes,
                theme: slot.theme,
                trackReference: draft.trackID
            )
            context.insert(exercise)
            exercise.routine = routine
            exercise.topic = topic
            // Link the three most recent times the teacher said it, for timestamp jumps.
            exercise.sourceKeyPoints = Array(topic.sortedKeyPoints.prefix(3))
        }
        try context.save()
        return routine
    }

    static func availableTracks(context: ModelContext) throws -> [TrackOption] {
        let presets = try context.fetch(FetchDescriptor<GeneratorPreset>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))
        let clips = try context.fetch(FetchDescriptor<PracticeClip>(sortBy: [SortDescriptor(\.createdAt)]))
        let presetOptions = presets.map { preset in
            let spec = preset.spec
            return TrackOption(
                id: preset.trackReference,
                name: preset.name,
                detail: "Generated piano track: \(spec.pattern.displayName), \(spec.floor.name)–\(spec.ceiling.name), \(Int(spec.tempo)) BPM"
            )
        }
        let clipOptions = clips.map { clip in
            TrackOption(
                id: clip.trackReference,
                name: clip.name,
                detail: "Recording of the teacher from the lesson on \(clip.lesson?.date.formatted(date: .abbreviated, time: .omitted) ?? "an earlier lesson"), \(Int(clip.duration)) s"
            )
        }
        return presetOptions + clipOptions
    }
}

/// Default generator presets, created once on first launch. All are editable.
enum BuiltInPresets {
    static func seedIfNeeded(context: ModelContext) throws {
        let descriptor = FetchDescriptor<GeneratorPreset>(predicate: #Predicate { $0.isBuiltIn })
        guard try context.fetchCount(descriptor) == 0 else { return }

        var order = 0
        for pattern in ExercisePattern.builtIn {
            context.insert(GeneratorPreset(name: "Passaggio · \(pattern.displayName)", spec: .passaggioFocus(pattern), isBuiltIn: true, sortOrder: order))
            order += 1
        }
        for pattern in ExercisePattern.builtIn {
            context.insert(GeneratorPreset(name: "Full range · \(pattern.displayName)", spec: .fullRange(pattern), isBuiltIn: true, sortOrder: order))
            order += 1
        }
        try context.save()
    }
}

/// Resolves a routine's `trackReference` to something playable.
enum PracticeTrack {
    case preset(GeneratorPreset)
    case clip(PracticeClip)

    static func resolve(_ reference: String?, context: ModelContext) -> PracticeTrack? {
        guard let reference else { return nil }
        let parts = reference.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "preset":
            let descriptor = FetchDescriptor<GeneratorPreset>(predicate: #Predicate { $0.id == id })
            return (try? context.fetch(descriptor).first).map(PracticeTrack.preset)
        case "clip":
            let descriptor = FetchDescriptor<PracticeClip>(predicate: #Predicate { $0.id == id })
            return (try? context.fetch(descriptor).first).map(PracticeTrack.clip)
        default:
            return nil
        }
    }

    var name: String {
        switch self {
        case .preset(let preset): preset.name
        case .clip(let clip): clip.name
        }
    }
}
