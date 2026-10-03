#if DEBUG
import PassaggioCore
import SwiftData
import SwiftUI

/// An in-memory store with a few lessons and a routine, for SwiftUI previews.
/// Use it with `#Preview(traits: .sampleData)`.
struct SampleData: PreviewModifier {
    static func makeSharedContext() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(PassaggioSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        try populate(container.mainContext)
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "PassaggioPreviews") ?? .standard)
        content
            .modelContainer(context)
            .environment(settings)
            .environment(PlayerController())
            .environment(LessonProcessor(settings: settings))
    }

    private static func populate(_ context: ModelContext) throws {
        try BuiltInPresets.seedIfNeeded(context: context)
        let presets = try context.fetch(FetchDescriptor<GeneratorPreset>(sortBy: [SortDescriptor(\.sortOrder)]))

        let day: TimeInterval = 86_400
        let analysed = Lesson(title: "Mixed voice through the passaggio", date: .now.addingTimeInterval(-2 * day),
                              duration: 2_730, fileName: "sample-analysed.m4a", waveform: waveform(seed: 1))
        analysed.status = .analyzed
        let earlier = Lesson(title: "Breath and onset", date: .now.addingTimeInterval(-9 * day),
                             duration: 2_580, fileName: "sample-earlier.m4a", waveform: waveform(seed: 2))
        earlier.status = .analyzed
        let fresh = Lesson(title: "Lesson recording", date: .now, duration: 2_640,
                           fileName: "sample-fresh.m4a", waveform: waveform(seed: 3))
        let unlabelled = Lesson(title: "Speakers not labelled yet", date: .now.addingTimeInterval(-1 * day),
                                duration: 2_700, fileName: "sample-unlabelled.m4a", waveform: waveform(seed: 4))
        unlabelled.status = .needsSpeakers
        let screaming = Lesson(title: "False-cord screams", date: .now.addingTimeInterval(-5 * day),
                               duration: 2_460, fileName: "sample-screaming.m4a", waveform: waveform(seed: 5))
        screaming.status = .analyzed
        screaming.style = .screaming
        for lesson in [analysed, earlier, fresh, unlabelled, screaming] { context.insert(lesson) }

        let screamLines: [(TimeInterval, String)] = [
            (64, "The rattle sits on top. Underneath it’s still a clean, supported note."),
            (212, "Brace like you’re about to lift something, then let the scream ride on that."),
        ]
        for (start, text) in screamLines {
            let segment = TranscriptSegment(start: start, end: start + 8, speaker: "teacher", role: .teacher, text: text)
            context.insert(segment)
            segment.lesson = screaming
        }

        let lines: [(TimeInterval, SpeakerRole, String)] = [
            (12, .teacher, "Let’s start on an ng hum, five-tone scale, from C3."),
            (31, .student, "It flips around E4 again."),
            (38, .teacher, "Don’t push through it. Let the vowel narrow as you go up and keep the volume down."),
            (74, .teacher, "Better. Your jaw is still reaching forward on the top note."),
            (96, .student, "Should I drop it more?"),
            (101, .teacher, "Not more, just let it hang. The space is behind the tongue, not in front of it."),
        ]
        for (start, role, text) in lines {
            let segment = TranscriptSegment(start: start, end: start + 8, speaker: role.referenceName ?? "A", role: role, text: text)
            context.insert(segment)
            segment.lesson = analysed
        }
        // The same exchange repeated through a long lesson, with anonymous speakers,
        // so jumping to a speaker's sample line has somewhere to scroll.
        for round in 0..<8 {
            for (start, role, text) in lines {
                let speaker = role == .teacher ? "A" : "B"
                let time = Double(round) * 300 + start
                let segment = TranscriptSegment(start: time, end: time + 8, speaker: speaker, role: .unknown,
                                                text: round == 5 && start == 38 ? text + " Keep it on the breath all the way to the end of the phrase." : text)
                context.insert(segment)
                segment.lesson = unlabelled
            }
        }

        let mix = FeedbackTopic(theme: .registrationMix, title: "Narrow the vowel through the passaggio")
        let jaw = FeedbackTopic(theme: .tensionHabits, title: "Jaw reaching forward on high notes")
        let breath = FeedbackTopic(theme: .breathSupport, title: "Steady airflow on the onset")
        let rattle = FeedbackTopic(theme: .distortion, title: "Rattle on top of a supported tone")
        let brace = FeedbackTopic(theme: .breathSupport, title: "Brace before the scream")
        for topic in [mix, jaw, breath, rattle, brace] { context.insert(topic) }

        let points: [(Lesson, FeedbackTopic, String, String, TimeInterval)] = [
            (analysed, mix, "Narrow the vowel and keep the volume down as you go up through E4.",
             "Don’t push through it. Let the vowel narrow as you go up and keep the volume down.", 38),
            (analysed, jaw, "Let the jaw hang on top notes instead of pushing it forward.",
             "Not more, just let it hang. The space is behind the tongue, not in front of it.", 101),
            (earlier, mix, "Lighten the sound before the break rather than after.",
             "Get lighter before you get there, not once you’ve cracked.", 420),
            (earlier, breath, "Start the note on the breath, without a glottal click.",
             "Think of the air starting before the sound.", 180),
            (screaming, rattle, "Keep the false-cord rattle on top of a clean, supported note.",
             "The rattle sits on top. Underneath it’s still a clean, supported note.", 64),
            (screaming, brace, "Brace before the scream and let it ride on that.",
             "Brace like you’re about to lift something, then let the scream ride on that.", 212),
        ]
        var keyPoints: [KeyPoint] = []
        for (lesson, topic, summary, quote, time) in points {
            let point = KeyPoint(theme: topic.theme, summary: summary, quote: quote, timestamp: time)
            context.insert(point)
            point.lesson = lesson
            point.topic = topic
            keyPoints.append(point)
        }

        let routine = Routine(lengthMinutes: 15)
        context.insert(routine)
        let exercises: [(String, String, String, Int, FeedbackTopic, GeneratorPreset?)] = [
            ("Narrowing slides", "Sing five-tone scales on “oo” from C3. Narrow the vowel as you pass E4 and keep the volume at a comfortable speaking level.",
             "Cross E4 with no flip, three times in a row.", 6, mix, presets.first),
            ("Hanging jaw", "Sing an octave arpeggio with a finger resting on your chin. Let the jaw hang on the top note rather than reaching forward.",
             "No forward jaw on the top note.", 5, jaw, presets.dropFirst().first),
            ("Breath before sound", "Sustain an “ah” on a comfortable pitch, letting the air start just before the tone.",
             "", 4, breath, nil),
        ]
        for (order, (title, instructions, goal, minutes, topic, preset)) in exercises.enumerated() {
            let exercise = RoutineExercise(order: order, title: title, instructions: instructions, goal: goal,
                                           minutes: minutes, theme: topic.theme, trackReference: preset?.trackReference)
            context.insert(exercise)
            exercise.routine = routine
            exercise.topic = topic
            exercise.sourceKeyPoints = keyPoints.filter { $0.topic === topic }
        }

        try context.save()
    }

    /// A plausible lesson envelope: phrases of singing between quieter talking.
    private static func waveform(seed: Double) -> [Float] {
        (0..<240).map { index in
            let x = Double(index)
            let phrase = 0.5 + 0.5 * sin(x / 9 + seed)
            let texture = 0.5 + 0.5 * sin(x * 1.7 + seed * 3)
            return Float(0.12 + 0.75 * phrase * (0.6 + 0.4 * texture))
        }
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    /// Sample lessons, feedback and a routine in an in-memory store, plus the app's environment objects.
    static var sampleData: Self { .modifier(SampleData()) }
}
#endif
