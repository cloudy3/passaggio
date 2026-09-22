import Foundation

/// A recurring topic as the planner sees it.
public struct TopicHistory: Hashable, Sendable {
    public var id: UUID
    public var theme: Theme
    /// Dates of the lessons in which this topic came up.
    public var occurrences: [Date]

    public init(id: UUID, theme: Theme, occurrences: [Date]) {
        self.id = id
        self.theme = theme
        self.occurrences = occurrences
    }
}

public struct PlannedSlot: Hashable, Sendable {
    public var topicID: UUID
    public var theme: Theme
    public var minutes: Int
    public var score: Double
}

/// Chooses which topics a routine covers and how long each gets.
///
/// Weighting: each time a topic came up contributes `0.5^(age / halfLife)`. Summing
/// rewards recurrence (three mentions beat one) while the decay favours recent
/// lessons, so a correction from last week outranks one from three months ago that
/// hasn't come up since.
public struct RoutinePlanner: Sendable {
    public var halfLifeDays: Double = 21
    /// One focus slot per this many minutes: 15 → 3 slots, 30 → 6, 45 → 9.
    public var minutesPerSlot = 5
    public var minimumMinutes = 3
    public var maximumMinutes = 10

    public static let lengths = [15, 30, 45]

    public init() {}

    public func score(_ topic: TopicHistory, now: Date) -> Double {
        topic.occurrences.reduce(0) { total, date in
            let ageDays = max(0, now.timeIntervalSince(date) / 86_400)
            return total + pow(0.5, ageDays / halfLifeDays)
        }
    }

    public func plan(topics: [TopicHistory], lengthMinutes: Int, now: Date = .now) -> [PlannedSlot] {
        let scored = topics
            .filter { !$0.occurrences.isEmpty }
            .map { (topic: $0, score: score($0, now: now)) }
            // Ties break on id so regenerating with the same data gives the same focus.
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.topic.id.uuidString < $1.topic.id.uuidString }

        let slotCount = min(scored.count, max(1, lengthMinutes / minutesPerSlot))
        guard slotCount > 0 else { return [] }
        let chosen = Array(scored.prefix(slotCount))

        let minutes = allocate(total: lengthMinutes, weights: chosen.map(\.score))
        return zip(chosen, minutes)
            .map { PlannedSlot(topicID: $0.topic.id, theme: $0.topic.theme, minutes: $1, score: $0.score) }
            // Practice order: themes in their natural order (breath → … → repertoire),
            // then the heavier topic first within a theme.
            .sorted { $0.theme != $1.theme ? $0.theme < $1.theme : $0.score > $1.score }
    }

    /// Splits `total` minutes across weights, each within min...max, summing exactly to
    /// `total` (largest-remainder rounding).
    func allocate(total: Int, weights: [Double]) -> [Int] {
        let n = weights.count
        guard n > 0 else { return [] }
        let floorMinutes = min(minimumMinutes, total / n)
        // With few topics the cap has to give, or the minutes couldn't all be used.
        let cap = max(maximumMinutes, Int((Double(total) / Double(n)).rounded(.up)))

        var result = Array(repeating: floorMinutes, count: n)
        var remaining = total - floorMinutes * n
        var open = Set(0..<n)

        // Hand out the remainder in proportion to weight, re-spreading whatever a
        // capped slot can't take.
        while remaining > 0, !open.isEmpty {
            let weightSum = open.reduce(0) { $0 + max(weights[$1], 1e-9) }
            let shares = open.map { i in (i, Double(remaining) * max(weights[i], 1e-9) / weightSum) }
            var given = 0
            var remainders: [(Int, Double)] = []
            for (i, share) in shares {
                let room = cap - result[i]
                let whole = min(Int(share.rounded(.down)), room)
                result[i] += whole
                given += whole
                if result[i] >= cap { open.remove(i) } else { remainders.append((i, share - Double(whole))) }
            }
            remaining -= given
            // Largest remainders get the leftover single minutes; ties go to the lower index.
            for (i, _) in remainders.sorted(by: { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }) where remaining > 0 {
                result[i] += 1
                remaining -= 1
                if result[i] >= cap { open.remove(i) }
            }
            if given == 0 && remainders.isEmpty { break }
        }
        return result
    }
}
