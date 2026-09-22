import Foundation

/// Local, deterministic topic matching. Used when the model skips a point, and as a
/// cheap sanity net. It compares content words, so it only catches near-identical
/// wording; the model handles paraphrases.
public enum RecurrenceMatcher {
    public static let threshold = 0.4

    public static func assign(_ point: ExtractedKeyPoint, to topics: [TopicCandidate]) -> TopicAssignment {
        let words = contentWords(point.summary)
        var best: (id: UUID, score: Double)?
        for topic in topics where topic.theme == point.theme {
            let corpus = ([topic.title] + topic.examples).map(contentWords)
            let score = corpus.map { jaccard(words, $0) }.max() ?? 0
            if score >= threshold, score > (best?.score ?? 0) {
                best = (topic.id, score)
            }
        }
        if let best { return .existing(best.id) }
        return .new(title: point.summary)
    }

    public static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    public static func contentWords(_ text: String) -> Set<String> {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(tokens.map(stem))
    }

    /// Crude suffix stripping so "pushing"/"push" and "vowels"/"vowel" match.
    static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where word.count > suffix.count + 3 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    static let stopWords: Set<String> = [
        "the", "and", "you", "your", "for", "with", "that", "this", "when", "are", "not", "don",
        "but", "into", "more", "less", "keep", "let", "too", "very", "just", "from", "out", "about",
        "make", "sure", "try", "it's", "its", "can", "should", "will", "have", "has", "was", "were",
    ]
}
