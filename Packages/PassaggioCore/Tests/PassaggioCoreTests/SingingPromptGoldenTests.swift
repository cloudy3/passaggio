import Foundation
import Testing
@testable import PassaggioCore

/// Mixed-voice (singing) lessons must keep sending exactly the prompts and schemas they
/// did before screaming lessons were added. The fixtures were recorded from the
/// singing-only code; if one of these fails, a change has leaked into singing lessons.
/// Don't re-record the fixtures to make them pass.
@Suite("Singing prompts are unchanged")
struct SingingPromptGoldenTests {
    static let teacherLines = [
        TimedSegment(start: 0.4, end: 4.1, speaker: "teacher", role: .teacher, text: "Five note scale on nay."),
        TimedSegment(start: 15.2, end: 22.9, speaker: "teacher", role: .teacher, text: "You're pushing chest too high around the C."),
        TimedSegment(start: 25.3, end: 31.7, speaker: "teacher", role: .teacher, text: "Keep the jaw loose."),
    ]

    static let points = [
        ExtractedKeyPoint(theme: .breathSupport, summary: "Keep support to the end of the phrase", quote: "support to the end", timestamp: 1),
        ExtractedKeyPoint(theme: .registrationMix, summary: "Tip into mix before C4", quote: "tip over before the C", timestamp: 2),
    ]

    static let topics = [
        TopicCandidate(id: UUID(), theme: .breathSupport, title: "Support through the phrase end", examples: ["Don't let the support go at the end"]),
        TopicCandidate(id: UUID(), theme: .tensionHabits, title: "Jaw clamps on high notes", examples: ["Keep the jaw loose on high notes", "Jaw is tight"]),
    ]

    static let slots = [
        RoutineSlotContext(theme: .registrationMix, topicTitle: "Mix before C4", quotes: ["Let it tip over earlier", "Don't haul chest up"], minutes: 10, occurrences: 3),
        RoutineSlotContext(theme: .tensionHabits, topicTitle: "Jaw clamp", quotes: ["Keep the jaw loose"], minutes: 5, occurrences: 1),
    ]

    static let tracks = [
        TrackOption(id: "preset:passaggio-5", name: "Passaggio · 5-note scale", detail: "Generated piano track: 5-note scale, D#2–G#4, 90 BPM"),
        TrackOption(id: "clip:nay", name: "Nay slides", detail: "Recording of the teacher from the lesson on 1 Sep 2026, 40 s"),
    ]

    static func golden(_ name: String) throws -> String {
        String(decoding: try Fixture.data(name, extension: "txt"), as: UTF8.self)
    }

    @Test func keyPointRequest() async throws {
        let llm = RecordingLLM(reply: #"{"points":[]}"#)
        _ = try await FeedbackAnalyst(provider: llm).extractKeyPoints(from: Self.teacherLines)
        #expect(llm.requests.count == 1)
        #expect(try llm.requests[0].transcript() == Self.golden("golden_singing_keypoints"))
    }

    @Test func topicRequest() async throws {
        let llm = RecordingLLM(reply: #"{"assignments":[]}"#)
        _ = try await FeedbackAnalyst(provider: llm).assignTopics(points: Self.points, existing: Self.topics)
        #expect(llm.requests.count == 1)
        #expect(try llm.requests[0].transcript() == Self.golden("golden_singing_topics"))
    }

    @Test func routineRequest() async throws {
        let llm = RecordingLLM(reply: #"{"exercises":[]}"#)
        _ = try await FeedbackAnalyst(provider: llm).draftRoutine(slots: Self.slots, tracks: Self.tracks)
        #expect(llm.requests.count == 1)
        #expect(try llm.requests[0].transcript() == Self.golden("golden_singing_routine"))
    }
}
