import Foundation
import Testing
@testable import PassaggioCore

@Suite("LLM providers")
struct LLMProviderTests {
    let output = StructuredOutput(name: "x", schema: Schema.object(["a": Schema.string()]))

    @Test func openAIRequestUsesStrictJSONSchema() throws {
        let provider = OpenAIProvider(apiKey: "sk", model: "gpt-5.6-luna", http: StubHTTPClient([]))
        let request = try provider.makeRequest(system: "SYS", user: "USER", output: output)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(request.url == OpenAIProvider.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk")
        #expect(body["model"] == "gpt-5.6-luna")
        #expect(body["instructions"] == "SYS")
        #expect(body["input"] == "USER")
        #expect(body["store"] == false)
        #expect(body["text"]?["format"]?["type"] == "json_schema")
        #expect(body["text"]?["format"]?["strict"] == true)
        #expect(body["text"]?["format"]?["schema"]?["additionalProperties"] == false)
    }

    @Test func openAIExtractsOutputText() throws {
        let json = try OpenAIProvider.extractJSON(from: Fixture.data("openai_responses_keypoints"))
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(value["points"]?.arrayValue?.count == 3)
    }

    @Test func openAISurfacesRefusalAndTruncation() throws {
        #expect(throws: APIError.refused("I can't help with that.")) {
            try OpenAIProvider.extractJSON(from: Fixture.data("openai_responses_refusal"))
        }
        #expect(throws: APIError.truncated) {
            try OpenAIProvider.extractJSON(from: Fixture.data("openai_responses_incomplete"))
        }
    }

    @Test func anthropicRequestShape() throws {
        let provider = AnthropicProvider(apiKey: "ak", model: "claude-opus-5", http: StubHTTPClient([]))
        let request = try provider.makeRequest(system: "SYS", user: "USER", output: output)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "ak")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(body["fallbacks"] == "default")
        #expect(body["system"] == "SYS")
        #expect(body["messages"]?.arrayValue?.first?["content"] == "USER")
        #expect(body["output_config"]?["format"]?["type"] == "json_schema")
        #expect(body["max_tokens"] == 16000)
        // No sampling parameters: current models reject non-default values.
        #expect(body["temperature"] == nil)
    }

    @Test func anthropicFallbacksOnlyForModelsThatSupportThem() throws {
        let provider = AnthropicProvider(apiKey: "ak", model: "claude-sonnet-5", http: StubHTTPClient([]))
        let request = try provider.makeRequest(system: "", user: "", output: output)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(body["fallbacks"] == nil)
    }

    @Test func anthropicSkipsThinkingBlocksAndHandlesRefusal() throws {
        let json = try AnthropicProvider.extractJSON(from: Fixture.data("anthropic_messages_keypoints"))
        #expect(String(decoding: json, as: UTF8.self).hasPrefix("{\"points\""))
        #expect(throws: APIError.refused("Declined.")) {
            try AnthropicProvider.extractJSON(from: Fixture.data("anthropic_messages_refusal"))
        }
    }

    @Test func retriesTransientErrorsThenSucceeds() async throws {
        let http = StubHTTPClient([
            (529, Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)),
            (200, try Fixture.data("anthropic_messages_keypoints")),
        ])
        let provider = AnthropicProvider(apiKey: "ak", model: "claude-opus-5", http: http)
        _ = try await provider.generateJSON(system: "", user: "", output: output)
        #expect(http.requests.count == 2)
    }

    @Test func doesNotRetryClientErrors() async throws {
        let http = StubHTTPClient([(401, try Fixture.data("openai_error_401")), (200, Data())])
        let provider = OpenAIProvider(apiKey: "sk", model: "m", http: http)
        await #expect(throws: APIError.self) { try await provider.generateJSON(system: "", user: "", output: output) }
        #expect(http.requests.count == 1)
    }

    @Test func schemaHelpersProduceStrictObjects() {
        let schema = Schema.object(["b": Schema.string(), "a": Schema.integer()])
        #expect(schema["required"] == ["a", "b"])
        #expect(schema["additionalProperties"] == false)
    }
}

@Suite("Feedback analysis")
struct FeedbackAnalystTests {
    let teacherLines = [
        TimedSegment(start: 0.4, end: 4.1, speaker: "teacher", role: .teacher, text: "Five note scale on nay."),
        TimedSegment(start: 15.2, end: 22.9, speaker: "teacher", role: .teacher, text: "You're pushing chest too high around the C."),
        TimedSegment(start: 25.3, end: 31.7, speaker: "teacher", role: .teacher, text: "Keep the jaw loose."),
    ]

    @Test func keyPointsAnchorToSegmentStartsAndDropBadIndices() async throws {
        let reply = try OpenAIProvider.extractJSON(from: Fixture.data("openai_responses_keypoints"))
        let analyst = FeedbackAnalyst(provider: StubLLM(reply: reply))
        let points = try await analyst.extractKeyPoints(from: teacherLines)
        #expect(points.count == 2)
        #expect(points[0].theme == .registrationMix)
        #expect(points[0].timestamp == 15.2)
        #expect(points[1].theme == .tensionHabits)
        #expect(points[1].timestamp == 25.3)
    }

    @Test func noTeacherSpeechMeansNoCall() async throws {
        let analyst = FeedbackAnalyst(provider: StubLLM(reply: Data("not json".utf8)))
        #expect(try await analyst.extractKeyPoints(from: []).isEmpty)
    }

    @Test func promptContainsOnlyGivenLinesAndAllThemes() {
        let prompt = FeedbackAnalyst.keyPointPrompt(teacherSegments: teacherLines)
        #expect(prompt.contains("[1] (0:15) You're pushing chest too high around the C."))
        for theme in Theme.allCases {
            #expect(prompt.contains(theme.rawValue))
        }
    }

    @Test func topicAssignmentsResolveIDsAndFallBackLocally() throws {
        let breath = TopicCandidate(id: UUID(), theme: .breathSupport, title: "Support through the phrase end", examples: [])
        let jaw = TopicCandidate(id: UUID(), theme: .tensionHabits, title: "Jaw clamps on high notes", examples: ["Keep the jaw loose on high notes"])
        let points = [
            ExtractedKeyPoint(theme: .breathSupport, summary: "Keep support to the end of the phrase", quote: "", timestamp: 1),
            ExtractedKeyPoint(theme: .registrationMix, summary: "Tip into mix before C4", quote: "", timestamp: 2),
            ExtractedKeyPoint(theme: .tensionHabits, summary: "Keep the jaw loose on high notes", quote: "", timestamp: 3),
            ExtractedKeyPoint(theme: .vowels, summary: "Narrow the ah", quote: "", timestamp: 4),
        ]
        let reply = Data("""
        {"assignments":[
          {"point":0,"existing_topic":"T0","new_topic_title":""},
          {"point":1,"existing_topic":"","new_topic_title":"Tip into mix earlier"},
          {"point":3,"existing_topic":"T9","new_topic_title":""},
          {"point":7,"existing_topic":"T0","new_topic_title":""}
        ]}
        """.utf8)
        let result = try FeedbackAnalyst.parseTopicAssignments(reply, points: points, existing: [breath, jaw])
        #expect(result[0] == .existing(breath.id))
        #expect(result[1] == .new(title: "Tip into mix earlier"))
        // Omitted by the model: the local matcher recognises the same wording.
        #expect(result[2] == .existing(jaw.id))
        // Invalid id and no title: the local matcher finds nothing, so it's a new topic.
        #expect(result[3] == .new(title: "Narrow the ah"))
    }

    @Test func routineParsingValidatesTracksAndFillsMissingSlots() throws {
        let slots = [
            RoutineSlotContext(theme: .registrationMix, topicTitle: "Mix before C4", quotes: ["Let it tip over earlier"], minutes: 10, occurrences: 3),
            RoutineSlotContext(theme: .tensionHabits, topicTitle: "Jaw clamp", quotes: ["Keep the jaw loose"], minutes: 5, occurrences: 1),
        ]
        let tracks = [TrackOption(id: "preset:passaggio-5", name: "Passaggio 5-note", detail: "")]
        let reply = Data("""
        {"exercises":[{"slot":0,"title":"Nay slides through the bridge","instructions":"Sing the passaggio 5-note on nay; let it tip over earlier.","goal":"No push at C4","track_id":"preset:passaggio-5"},
                      {"slot":0,"title":"dup","instructions":"","goal":"","track_id":""},
                      {"slot":5,"title":"bogus","instructions":"","goal":"","track_id":"nope"}]}
        """.utf8)
        let drafts = try FeedbackAnalyst.parseRoutine(reply, slots: slots, tracks: tracks)
        #expect(drafts.count == 2)
        #expect(drafts[0].trackID == "preset:passaggio-5")
        #expect(drafts[0].title == "Nay slides through the bridge")
        #expect(drafts[1].title == "Jaw clamp")
        #expect(drafts[1].instructions.contains("Keep the jaw loose"))
        #expect(drafts[1].trackID == nil)
    }

    @Test func malformedJSONIsADecodingError() {
        #expect(throws: APIError.self) {
            try FeedbackAnalyst.parseKeyPoints(Data("{}".utf8), teacherSegments: teacherLines)
        }
    }

    @Test func timestampFormatting() {
        #expect(formatTimestamp(0) == "0:00")
        #expect(formatTimestamp(75.9) == "1:15")
        #expect(formatTimestamp(3725) == "1:02:05")
        #expect(formatTimestamp(-3) == "0:00")
    }
}

@Suite("Recurrence matching")
struct RecurrenceMatcherTests {
    @Test func matchesSameWordingWithinTheme() {
        let topic = TopicCandidate(id: UUID(), theme: .vowels, title: "Modify ah to aw on high notes", examples: [])
        let point = ExtractedKeyPoint(theme: .vowels, summary: "On high notes modify the ah towards aw", quote: "", timestamp: 0)
        #expect(RecurrenceMatcher.assign(point, to: [topic]) == .existing(topic.id))
    }

    @Test func neverMatchesAcrossThemes() {
        let topic = TopicCandidate(id: UUID(), theme: .range, title: "Modify ah to aw on high notes", examples: [])
        let point = ExtractedKeyPoint(theme: .vowels, summary: "Modify ah to aw on high notes", quote: "", timestamp: 0)
        #expect(RecurrenceMatcher.assign(point, to: [topic]) == .new(title: point.summary))
    }

    @Test func stemsCommonSuffixes() {
        #expect(RecurrenceMatcher.contentWords("pushing vowels") == RecurrenceMatcher.contentWords("push vowel"))
    }
}
