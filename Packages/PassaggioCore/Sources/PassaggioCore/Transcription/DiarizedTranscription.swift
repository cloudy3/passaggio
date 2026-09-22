import Foundation

/// `diarized_json` response from `POST /v1/audio/transcriptions`
/// with `gpt-4o-transcribe-diarize`.
///
/// Decoding is deliberately lenient about fields we don't rely on (`id`, `type`,
/// `usage`, `duration`) so a harmless schema addition or omission doesn't fail a
/// whole lesson.
public struct DiarizedTranscription: Decodable, Sendable {
    public struct Segment: Decodable, Hashable, Sendable {
        public var id: String?
        public var speaker: String
        public var start: TimeInterval
        public var end: TimeInterval
        public var text: String

        public init(id: String? = nil, speaker: String, start: TimeInterval, end: TimeInterval, text: String) {
            self.id = id
            self.speaker = speaker
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public struct Usage: Decodable, Sendable {
        public var type: String?
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var seconds: Double?

        enum CodingKeys: String, CodingKey {
            case type, seconds
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    public var text: String
    public var segments: [Segment]
    public var duration: TimeInterval?
    public var usage: Usage?

    enum CodingKeys: String, CodingKey {
        case text, segments, duration, usage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        segments = try container.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        usage = try? container.decodeIfPresent(Usage.self, forKey: .usage)
    }

    public init(text: String, segments: [Segment], duration: TimeInterval? = nil, usage: Usage? = nil) {
        self.text = text
        self.segments = segments
        self.duration = duration
        self.usage = usage
    }

    public static func decode(_ data: Data) throws -> DiarizedTranscription {
        try JSONDecoder().decode(DiarizedTranscription.self, from: data)
    }

    /// The model caps output at 2,000 tokens. A response at (or within a hair of) that
    /// cap was probably cut off, and the chunk should be split and re-sent.
    public static let outputTokenLimit = 2_000

    public var isLikelyTruncated: Bool {
        guard let output = usage?.outputTokens else { return false }
        return output >= Self.outputTokenLimit - 40
    }
}

/// Who a transcript segment belongs to.
public enum SpeakerRole: String, Codable, CaseIterable, Sendable {
    case teacher
    case student
    case unknown

    /// Names sent in `known_speaker_names[]`. The model echoes them back as `speaker`.
    public var referenceName: String? {
        switch self {
        case .teacher: "teacher"
        case .student: "me"
        case .unknown: nil
        }
    }

    public init(speakerLabel: String) {
        switch speakerLabel.lowercased() {
        case "teacher": self = .teacher
        case "me": self = .student
        default: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .teacher: "Teacher"
        case .student: "Me"
        case .unknown: "Unknown"
        }
    }
}

/// A segment placed on the lesson's timeline.
public struct TimedSegment: Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    /// Known names pass through ("teacher", "me"). Anonymous labels ("A", "B") are only
    /// meaningful within one request, so they get a chunk suffix to stop "A" in chunk 1
    /// being conflated with a different "A" in chunk 2.
    public var speaker: String
    public var role: SpeakerRole
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, speaker: String, role: SpeakerRole, text: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.role = role
        self.text = text
    }
}

/// Stitches per-chunk responses into one continuous transcript.
public enum TranscriptMerger {
    /// - Parameter results: Each chunk paired with its response. Chunk order doesn't matter.
    public static func merge(_ results: [(chunk: AudioChunk, response: DiarizedTranscription)]) -> [TimedSegment] {
        let multiChunk = results.count > 1
        let lessonEnd = results.map(\.chunk.nominalEnd).max() ?? 0
        var merged: [TimedSegment] = []

        for (chunk, response) in results {
            let isLastChunk = chunk.nominalEnd >= lessonEnd
            for segment in response.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                // Response times are relative to the exported audio, which starts at audioStart.
                let start = segment.start + chunk.audioStart
                let end = max(segment.end, segment.start) + chunk.audioStart

                // Each chunk owns only its nominal range; overlap copies are dropped by
                // midpoint so a word heard twice is kept exactly once.
                let midpoint = (start + end) / 2
                // The final chunk also keeps anything past the nominal end (rounding in the
                // response's timestamps can put the last word a hair beyond the duration).
                let owns = midpoint >= chunk.nominalStart && (midpoint < chunk.nominalEnd || isLastChunk)
                guard owns else { continue }

                let role = SpeakerRole(speakerLabel: segment.speaker)
                let speaker = (role == .unknown && multiChunk)
                    ? "\(segment.speaker) (part \(chunk.index + 1))"
                    : segment.speaker
                merged.append(TimedSegment(start: start, end: end, speaker: speaker, role: role, text: text))
            }
        }
        return merged.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }
}
