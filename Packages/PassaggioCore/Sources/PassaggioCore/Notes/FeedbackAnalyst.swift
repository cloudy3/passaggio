import Foundation

/// A point of teacher feedback extracted from one lesson.
public struct ExtractedKeyPoint: Hashable, Sendable {
    public var theme: Theme
    public var summary: String
    public var quote: String
    /// Start of the teacher segment the point comes from, on the lesson timeline.
    public var timestamp: TimeInterval
}

/// A recurring feedback topic that already exists, offered to the model for matching.
public struct TopicCandidate: Hashable, Sendable {
    public var id: UUID
    public var theme: Theme
    public var title: String
    public var examples: [String]

    public init(id: UUID, theme: Theme, title: String, examples: [String]) {
        self.id = id
        self.theme = theme
        self.title = title
        self.examples = examples
    }
}

/// Where a new key point belongs.
public enum TopicAssignment: Hashable, Sendable {
    case existing(UUID)
    /// A new topic. Points in the same lesson that get the same title share one topic.
    case new(title: String)
}

/// One routine exercise as phrased by the model, before it is saved.
public struct DraftExercise: Hashable, Sendable {
    public var slotIndex: Int
    public var title: String
    public var instructions: String
    public var goal: String
    public var trackID: String?
}

/// A practice track the routine may attach to an exercise.
public struct TrackOption: Hashable, Sendable {
    public var id: String
    public var name: String
    public var detail: String

    public init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// A routine slot handed to the model to phrase as an exercise.
public struct RoutineSlotContext: Hashable, Sendable {
    public var theme: Theme
    public var topicTitle: String
    /// The teacher's own words, most recent first.
    public var quotes: [String]
    public var minutes: Int
    public var occurrences: Int

    public init(theme: Theme, topicTitle: String, quotes: [String], minutes: Int, occurrences: Int) {
        self.theme = theme
        self.topicTitle = topicTitle
        self.quotes = quotes
        self.minutes = minutes
        self.occurrences = occurrences
    }
}

/// All language-model work: extracting key points, matching them to recurring topics,
/// and phrasing routine exercises. Prompts, schemas and response validation live here
/// so they can be tested with recorded responses.
public struct FeedbackAnalyst: Sendable {
    public var provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    /// Shared by every prompt. The teacher is the authority; the app only organises.
    static let principles = """
    You help a singing student organise feedback from their private voice teacher. \
    The teacher's feedback is the only authority. Never add vocal technique, pedagogy, \
    exercises or advice the teacher did not give, never contradict the teacher, and never \
    "improve" on what they said. Keep the teacher's own words and imagery wherever you can. \
    If something the teacher said is ambiguous, keep it ambiguous rather than guessing. \
    The student is a male singer working on finding and strengthening his mixed voice and on \
    removing bad habits.
    """

    // MARK: Key points

    static var themeGuide: String {
        Theme.allCases.map { "- \($0.rawValue): \($0.promptDefinition)" }.joined(separator: "\n")
    }

    static let keyPointSchema = StructuredOutput(
        name: "lesson_key_points",
        schema: Schema.object([
            "points": Schema.array(Schema.object([
                "theme": Schema.enumeration(Theme.allCases.map(\.rawValue)),
                "summary": Schema.string("The feedback as a short instruction to the student, in the teacher's terms."),
                "quote": Schema.string("A short verbatim excerpt of the teacher's words that carries this point."),
                "segment": Schema.integer("The number of the transcript line where the teacher gives this feedback."),
            ])),
        ])
    )

    static func keyPointPrompt(teacherSegments: [TimedSegment]) -> String {
        let lines = teacherSegments.enumerated().map { index, segment in
            "[\(index)] (\(formatTimestamp(segment.start))) \(segment.text)"
        }
        return """
        Below is everything the teacher said in one lesson, as numbered lines. The recording also \
        contained singing and piano, which were removed; some lines may be fragments or \
        mis-transcribed lyrics.

        Extract each distinct piece of feedback or instruction the teacher gave the student. \
        Skip greetings, scheduling, small talk, counting-in and lyrics. Merge repeats of the same \
        point within this lesson into one entry, pointing at the line where it is first given \
        most clearly. Classify each point into exactly one theme:
        \(themeGuide)

        Teacher's lines:
        \(lines.joined(separator: "\n"))
        """
    }

    public func extractKeyPoints(from teacherSegments: [TimedSegment]) async throws -> [ExtractedKeyPoint] {
        guard !teacherSegments.isEmpty else { return [] }
        let data = try await provider.generateJSON(
            system: Self.principles,
            user: Self.keyPointPrompt(teacherSegments: teacherSegments),
            output: Self.keyPointSchema
        )
        return try Self.parseKeyPoints(data, teacherSegments: teacherSegments)
    }

    static func parseKeyPoints(_ data: Data, teacherSegments: [TimedSegment]) throws -> [ExtractedKeyPoint] {
        struct Response: Decodable {
            struct Point: Decodable { var theme: String; var summary: String; var quote: String; var segment: Int }
            var points: [Point]
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
        return response.points.compactMap { point in
            // Drop anything we can't anchor to a real line: the timestamp jump is the
            // point of the feature, and an invented index would jump somewhere wrong.
            guard let theme = Theme(rawValue: point.theme),
                  teacherSegments.indices.contains(point.segment) else { return nil }
            let summary = point.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return nil }
            return ExtractedKeyPoint(
                theme: theme,
                summary: summary,
                quote: point.quote.trimmingCharacters(in: .whitespacesAndNewlines),
                timestamp: teacherSegments[point.segment].start
            )
        }
    }

    // MARK: Recurring topics

    static let topicSchema = StructuredOutput(
        name: "topic_assignments",
        schema: Schema.object([
            "assignments": Schema.array(Schema.object([
                "point": Schema.integer("Number of the new point."),
                "existing_topic": Schema.string("Id of the existing topic this point repeats, or an empty string."),
                "new_topic_title": Schema.string("If no existing topic fits: a short title (max 8 words) for a new topic. Otherwise an empty string."),
            ])),
        ])
    )

    static func topicPrompt(points: [ExtractedKeyPoint], topics: [TopicCandidate]) -> String {
        let topicLines = topics.enumerated().map { index, topic in
            let examples = topic.examples.prefix(2).map { "“\($0)”" }.joined(separator: "; ")
            return "- id T\(index) [\(topic.theme.rawValue)] \(topic.title) — e.g. \(examples)"
        }
        let pointLines = points.enumerated().map { index, point in
            "[\(index)] [\(point.theme.rawValue)] \(point.summary)"
        }
        return """
        The student tracks which pieces of feedback recur across lessons. Assign each new point \
        to an existing topic only if the teacher is making the same correction again (same \
        underlying issue, even if worded differently). Otherwise give it a new topic title that \
        names the issue in the teacher's terms. New points from this lesson that make the same \
        correction must share the same new title.

        Existing topics:
        \(topicLines.isEmpty ? "(none yet)" : topicLines.joined(separator: "\n"))

        New points:
        \(pointLines.joined(separator: "\n"))
        """
    }

    public func assignTopics(points: [ExtractedKeyPoint], existing: [TopicCandidate]) async throws -> [TopicAssignment] {
        guard !points.isEmpty else { return [] }
        let data = try await provider.generateJSON(
            system: Self.principles,
            user: Self.topicPrompt(points: points, topics: existing),
            output: Self.topicSchema
        )
        return try Self.parseTopicAssignments(data, points: points, existing: existing)
    }

    static func parseTopicAssignments(_ data: Data, points: [ExtractedKeyPoint], existing: [TopicCandidate]) throws -> [TopicAssignment] {
        struct Response: Decodable {
            struct Item: Decodable {
                var point: Int
                var existingTopic: String
                var newTopicTitle: String
                enum CodingKeys: String, CodingKey {
                    case point
                    case existingTopic = "existing_topic"
                    case newTopicTitle = "new_topic_title"
                }
            }
            var assignments: [Item]
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }

        var byPoint: [Int: Response.Item] = [:]
        for item in response.assignments where points.indices.contains(item.point) {
            byPoint[item.point] = byPoint[item.point] ?? item
        }

        // Any point the model skipped or mislabelled falls back to the local matcher,
        // so every point always ends up with a topic.
        return points.indices.map { index in
            let point = points[index]
            if let item = byPoint[index] {
                let id = item.existingTopic.trimmingCharacters(in: .whitespaces)
                if id.hasPrefix("T"), let n = Int(id.dropFirst()), existing.indices.contains(n) {
                    return .existing(existing[n].id)
                }
                let title = item.newTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return .new(title: title)
                }
            }
            return RecurrenceMatcher.assign(point, to: existing)
        }
    }

    // MARK: Routine exercises

    static let routineSchema = StructuredOutput(
        name: "practice_routine",
        schema: Schema.object([
            "exercises": Schema.array(Schema.object([
                "slot": Schema.integer("Number of the focus slot this exercise covers."),
                "title": Schema.string("Short exercise title."),
                "instructions": Schema.string("What to do, drawn only from the teacher's words (2–4 sentences)."),
                "goal": Schema.string("What success sounds or feels like, as the teacher described it."),
                "track_id": Schema.string("Id of the practice track to use, or an empty string."),
            ])),
        ])
    )

    static func routinePrompt(slots: [RoutineSlotContext], tracks: [TrackOption]) -> String {
        let slotLines = slots.enumerated().map { index, slot in
            let quotes = slot.quotes.prefix(3).map { "“\($0)”" }.joined(separator: " / ")
            return "[\(index)] \(slot.minutes) min — \(slot.theme.displayName): \(slot.topicTitle) (raised in \(slot.occurrences) lesson(s)). Teacher said: \(quotes)"
        }
        let trackLines = tracks.map { "- \($0.id): \($0.name) — \($0.detail)" }
        return """
        Write one practice exercise for each focus slot below, in the same order. Each exercise \
        must work on exactly the teacher's feedback for that slot. Use an exercise the teacher \
        assigned if the quotes mention one. Otherwise, the exercise is to sing one of the available \
        practice tracks (or the student's repertoire) while applying the teacher's correction, \
        described in the teacher's words. Do not invent new techniques. Only attach a track when \
        it suits the slot; lesson clips are recordings of the teacher, so prefer them when their \
        name matches the slot.

        Focus slots:
        \(slotLines.joined(separator: "\n"))

        Available practice tracks:
        \(trackLines.isEmpty ? "(none)" : trackLines.joined(separator: "\n"))
        """
    }

    public func draftRoutine(slots: [RoutineSlotContext], tracks: [TrackOption]) async throws -> [DraftExercise] {
        guard !slots.isEmpty else { return [] }
        let data = try await provider.generateJSON(
            system: Self.principles,
            user: Self.routinePrompt(slots: slots, tracks: tracks),
            output: Self.routineSchema
        )
        return try Self.parseRoutine(data, slots: slots, tracks: tracks)
    }

    static func parseRoutine(_ data: Data, slots: [RoutineSlotContext], tracks: [TrackOption]) throws -> [DraftExercise] {
        struct Response: Decodable {
            struct Item: Decodable {
                var slot: Int
                var title: String
                var instructions: String
                var goal: String
                var trackID: String
                enum CodingKeys: String, CodingKey {
                    case slot, title, instructions, goal
                    case trackID = "track_id"
                }
            }
            var exercises: [Item]
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }

        let trackIDs = Set(tracks.map(\.id))
        var bySlot: [Int: DraftExercise] = [:]
        for item in response.exercises where slots.indices.contains(item.slot) && bySlot[item.slot] == nil {
            bySlot[item.slot] = DraftExercise(
                slotIndex: item.slot,
                title: item.title,
                instructions: item.instructions,
                goal: item.goal,
                trackID: trackIDs.contains(item.trackID) ? item.trackID : nil
            )
        }
        // A slot the model dropped still gets an exercise: the teacher's words verbatim.
        return slots.indices.map { index in
            bySlot[index] ?? DraftExercise(
                slotIndex: index,
                title: slots[index].topicTitle,
                instructions: slots[index].quotes.first.map { "Your teacher said: “\($0)”" } ?? slots[index].topicTitle,
                goal: slots[index].topicTitle,
                trackID: nil
            )
        }
    }
}

/// "m:ss" or "h:mm:ss".
public func formatTimestamp(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
