import Foundation
import Testing
@testable import PassaggioCore

@Suite("Chunk planning")
struct ChunkPlannerTests {
    let planner = ChunkPlanner()

    @Test func shortLessonIsOneChunk() {
        let chunks = planner.plan(duration: 310)
        #expect(chunks.count == 1)
        #expect(chunks[0].audioStart == 0 && chunks[0].audioEnd == 310)
        #expect(chunks[0].nominalStart == 0 && chunks[0].nominalEnd == 310)
    }

    @Test func emptyDurationHasNoChunks() {
        #expect(planner.plan(duration: 0).isEmpty)
    }

    @Test func withoutEnvelopeCutsAtTheTarget() {
        let chunks = planner.plan(duration: 1000)
        #expect(chunks.map(\.nominalStart) == [0, 300, 600, 900])
        #expect(chunks.map(\.nominalEnd) == [300, 600, 900, 1000])
    }

    @Test(arguments: [45.0, 299.0, 301.0, 320.0, 321.0, 1399.0, 3600.0, 5432.1])
    func nominalRangesTileTheLessonExactly(_ duration: Double) {
        let chunks = planner.plan(duration: duration)
        #expect(chunks.first?.nominalStart == 0)
        #expect(chunks.last?.nominalEnd == duration)
        for (a, b) in zip(chunks, chunks.dropFirst()) {
            #expect(a.nominalEnd == b.nominalStart)
        }
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
        // No chunk exceeds the target plus the tail allowance plus overlap on both sides,
        // which keeps us far below the API's ~1400 s limit.
        let config = planner.configuration
        for chunk in chunks {
            #expect(chunk.audioDuration <= config.targetDuration + config.minimumTail + 2 * config.overlap + 1e-9)
            #expect(chunk.audioStart >= 0 && chunk.audioEnd <= duration)
        }
    }

    @Test func overlapExtendsAudioIntoNeighbours() {
        let chunks = planner.plan(duration: 700)
        #expect(chunks[0].audioStart == 0)
        #expect(chunks[0].audioEnd == 301.5)
        #expect(chunks[1].audioStart == 298.5)
        #expect(chunks.last!.audioEnd == 700)
    }

    @Test func cutsInTheQuietestStretchBeforeTheTarget() {
        // Loud everywhere except a two-second pause at 270–272 s.
        let hop = 0.5
        var envelope = [Float](repeating: 0.8, count: Int(700 / hop))
        for i in Int(270 / hop)..<Int(272 / hop) { envelope[i] = 0.01 }
        let chunks = planner.plan(duration: 700, envelope: envelope, hop: hop)
        #expect(chunks[0].nominalEnd >= 270 && chunks[0].nominalEnd <= 272)
        #expect(chunks[1].nominalStart == chunks[0].nominalEnd)
    }

    @Test func ignoresSilenceOutsideTheSearchWindow() {
        let hop = 0.5
        var envelope = [Float](repeating: 0.8, count: Int(700 / hop))
        for i in Int(100 / hop)..<Int(110 / hop) { envelope[i] = 0 } // too early to use
        let chunks = planner.plan(duration: 700, envelope: envelope, hop: hop)
        let window = (300 - planner.configuration.searchWindow)...300
        #expect(window.contains(chunks[0].nominalEnd))
    }

    @Test func splitHalvesAChunkAndPreservesItsBounds() {
        let chunk = planner.plan(duration: 1000)[1]
        let halves = planner.split(chunk, duration: 1000)
        #expect(halves.count == 2)
        #expect(halves[0].nominalStart == chunk.nominalStart)
        #expect(halves[1].nominalEnd == chunk.nominalEnd)
        #expect(halves[0].nominalEnd == halves[1].nominalStart)
        #expect(halves[0].nominalEnd == 450)
    }
}

@Suite("Transcript merging")
struct TranscriptMergerTests {
    @Test func offsetsSegmentsByChunkAudioStart() {
        let chunks = ChunkPlanner().plan(duration: 700)
        let second = DiarizedTranscription(text: "", segments: [segment(10, 12, "teacher", "Lift the soft palate.")])
        let merged = TranscriptMerger.merge([(chunks[1], second)])
        #expect(merged.count == 1)
        // Chunk 1's audio starts at 298.5 s (300 minus the 1.5 s overlap).
        #expect(merged[0].start == 308.5)
        #expect(merged[0].end == 310.5)
        #expect(merged[0].role == .teacher)
    }

    @Test func timestampsStayContinuousAcrossChunks() {
        let chunks = ChunkPlanner().plan(duration: 700)
        let results = chunks.map { chunk in
            // Each response has a segment at the same relative time.
            (chunk, DiarizedTranscription(text: "", segments: [segment(100, 101)]))
        }
        let merged = TranscriptMerger.merge(results)
        #expect(merged.map(\.start) == [100, 398.5, 698.5])
        #expect(zip(merged, merged.dropFirst()).allSatisfy { $0.start < $1.start })
    }

    @Test func overlapDuplicatesAreKeptOnce() {
        let chunks = ChunkPlanner().plan(duration: 700)
        // The word "support" straddles the 300 s cut and is heard by both requests:
        // chunk 0 hears it at 299.6–300.2 (relative 299.6), chunk 1 at relative 1.1–1.7.
        let first = DiarizedTranscription(text: "", segments: [
            segment(290, 299, "teacher", "Keep your"),
            segment(299.6, 300.2, "teacher", "support"),
        ])
        let second = DiarizedTranscription(text: "", segments: [
            segment(1.1, 1.7, "teacher", "support"),
            segment(2.0, 5.0, "teacher", "all the way through."),
        ])
        let merged = TranscriptMerger.merge([(chunks[1], second), (chunks[0], first)])
        #expect(merged.map(\.text) == ["Keep your", "support", "all the way through."])
        #expect(merged.filter { $0.text == "support" }.count == 1)
    }

    @Test func lastChunkKeepsTrailingWordsPastTheNominalEnd() {
        let chunks = ChunkPlanner().plan(duration: 100)
        let response = DiarizedTranscription(text: "", segments: [segment(99.8, 100.4, "me", "Thanks!")])
        #expect(TranscriptMerger.merge([(chunks[0], response)]).count == 1)
    }

    @Test func anonymousSpeakersAreScopedToTheirChunk() throws {
        let chunks = ChunkPlanner().plan(duration: 700)
        let response = try DiarizedTranscription.decode(Fixture.data("diarized_anonymous"))
        let single = TranscriptMerger.merge([(chunks[0], response)])
        let multi = TranscriptMerger.merge([(chunks[0], response), (chunks[1], DiarizedTranscription(text: "", segments: []))])
        #expect(multi.map(\.speaker) == ["A (part 1)", "B (part 1)"])
        #expect(single.allSatisfy { $0.role == .unknown })
        // Whitespace-only segments are dropped; text is trimmed.
        #expect(multi.map(\.text) == ["Hello there.", "Hi."])
    }
}

@Suite("Diarized responses")
struct DiarizedResponseTests {
    @Test func parsesDocumentedSchema() throws {
        let response = try DiarizedTranscription.decode(Fixture.data("diarized_lesson"))
        #expect(response.segments.count == 5)
        #expect(response.segments[0].id == "seg_0")
        #expect(response.segments[2].speaker == "teacher")
        #expect(response.segments[2].start == 15.2)
        #expect(response.duration == 62.4)
        #expect(response.usage?.outputTokens == 96)
        #expect(response.isLikelyTruncated == false)
    }

    @Test func mapsKnownSpeakerNamesToRoles() throws {
        let response = try DiarizedTranscription.decode(Fixture.data("diarized_lesson"))
        let merged = TranscriptMerger.merge([(ChunkPlanner().plan(duration: 62.4)[0], response)])
        #expect(merged.map(\.role) == [.teacher, .student, .teacher, .student, .teacher])
        #expect(merged.filter { $0.role == .teacher }.count == 3)
    }

    @Test func toleratesMissingOptionalFields() throws {
        let response = try DiarizedTranscription.decode(Fixture.data("diarized_anonymous"))
        #expect(response.segments.count == 3)
        #expect(response.usage == nil)
        #expect(response.segments[0].id == nil)
    }

    @Test func flagsResponsesAtTheOutputCap() throws {
        let response = try DiarizedTranscription.decode(Fixture.data("diarized_truncated"))
        #expect(response.isLikelyTruncated)
    }

    @Test func rejectsNonJSON() {
        #expect(throws: (any Error).self) { try DiarizedTranscription.decode(Data("<html>".utf8)) }
    }

    @Test func roleLabelsAreCaseInsensitive() {
        #expect(SpeakerRole(speakerLabel: "Teacher") == .teacher)
        #expect(SpeakerRole(speakerLabel: "ME") == .student)
        #expect(SpeakerRole(speakerLabel: "A") == .unknown)
    }
}

@Suite("Transcription request")
struct TranscriptionRequestTests {
    @Test func buildsMultipartBodyWithReferences() throws {
        let client = OpenAITranscriptionClient(apiKey: "sk-test", http: StubHTTPClient([]))
        let references = [
            SpeakerReferenceClip(name: "teacher", audio: Data([1, 2, 3])),
            SpeakerReferenceClip(name: "me", audio: Data([4, 5])),
        ]
        let request = client.makeRequest(audio: Data("AUDIO".utf8), filename: "chunk-0.m4a", references: references, boundary: "B")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        #expect(body.contains("name=\"model\"\r\n\r\ngpt-4o-transcribe-diarize\r\n"))
        #expect(body.contains("name=\"response_format\"\r\n\r\ndiarized_json\r\n"))
        #expect(body.contains("name=\"chunking_strategy\"\r\n\r\nauto\r\n"))
        #expect(body.components(separatedBy: "name=\"known_speaker_names[]\"").count == 3)
        #expect(body.contains("data:audio/wav;base64,AQID"))
        #expect(body.contains("filename=\"chunk-0.m4a\"\r\nContent-Type: audio/mp4\r\n\r\nAUDIO\r\n"))
        #expect(body.hasSuffix("--B--\r\n"))
        // Names and references are paired in the same order.
        let teacherName = try #require(body.range(of: "\r\n\r\nteacher\r\n"))
        let meName = try #require(body.range(of: "\r\n\r\nme\r\n"))
        #expect(teacherName.lowerBound < meName.lowerBound)
    }

    @Test func caps4References() throws {
        let client = OpenAITranscriptionClient(apiKey: "k", http: StubHTTPClient([]))
        let refs = (0..<6).map { SpeakerReferenceClip(name: "s\($0)", audio: Data([0])) }
        let body = String(decoding: client.makeRequest(audio: Data(), filename: "a.m4a", references: refs).httpBody!, as: UTF8.self)
        #expect(body.components(separatedBy: "known_speaker_references[]").count == 5)
    }

    @Test func transcribeDecodesAndSurfacesHTTPErrors() async throws {
        let ok = StubHTTPClient([(200, try Fixture.data("diarized_lesson"))])
        let response = try await OpenAITranscriptionClient(apiKey: "k", http: ok).transcribe(audio: Data(), filename: "a.m4a", references: [])
        #expect(response.segments.count == 5)

        let unauthorized = StubHTTPClient([(401, try Fixture.data("openai_error_401"))])
        await #expect(throws: APIError.http(status: 401, message: "Incorrect API key provided: sk-abc***.")) {
            try await OpenAITranscriptionClient(apiKey: "k", http: unauthorized).transcribe(audio: Data(), filename: "a.m4a", references: [])
        }

        await #expect(throws: APIError.missingAPIKey(provider: "OpenAI")) {
            try await OpenAITranscriptionClient(apiKey: "", http: ok).transcribe(audio: Data(), filename: "a.m4a", references: [])
        }
    }
}
