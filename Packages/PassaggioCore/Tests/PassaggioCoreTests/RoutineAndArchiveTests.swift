import Foundation
import Testing
@testable import PassaggioCore

@Suite("Routine planning")
struct RoutinePlannerTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let planner = RoutinePlanner()

    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func topics(_ count: Int) -> [TopicHistory] {
        (0..<count).map { i in
            TopicHistory(id: UUID(), theme: Theme.allCases[i % Theme.allCases.count], occurrences: [daysAgo(Double(i))])
        }
    }

    @Test(arguments: RoutinePlanner.lengths)
    func minutesAlwaysSumToTheChosenLength(_ length: Int) {
        for count in 1...12 {
            let plan = planner.plan(topics: topics(count), lengthMinutes: length, now: now)
            #expect(plan.reduce(0) { $0 + $1.minutes } == length, "\(count) topics, \(length) min")
            #expect(plan.count == min(count, length / 5))
            #expect(plan.allSatisfy { $0.minutes >= 3 })
        }
    }

    @Test func recurringFeedbackOutweighsOneOffs() {
        let recurring = TopicHistory(id: UUID(), theme: .vowels, occurrences: [daysAgo(1), daysAgo(8), daysAgo(15)])
        let once = TopicHistory(id: UUID(), theme: .breathSupport, occurrences: [daysAgo(1)])
        #expect(planner.score(recurring, now: now) > planner.score(once, now: now))

        let plan = planner.plan(topics: [once, recurring], lengthMinutes: 15, now: now)
        let recurringMinutes = plan.first { $0.topicID == recurring.id }!.minutes
        let onceMinutes = plan.first { $0.topicID == once.id }!.minutes
        #expect(recurringMinutes > onceMinutes)
    }

    @Test func recentFeedbackOutweighsOldFeedback() {
        let recent = TopicHistory(id: UUID(), theme: .range, occurrences: [daysAgo(2)])
        let old = TopicHistory(id: UUID(), theme: .range, occurrences: [daysAgo(90)])
        #expect(planner.score(recent, now: now) > planner.score(old, now: now))
        // One half-life halves the weight.
        let halfLife = TopicHistory(id: UUID(), theme: .range, occurrences: [daysAgo(21)])
        #expect(abs(planner.score(halfLife, now: now) - 0.5) < 1e-9)
    }

    @Test func picksTheHighestScoringTopicsAndOrdersByTheme() {
        let fresh = (0..<3).map { _ in TopicHistory(id: UUID(), theme: .repertoire, occurrences: [daysAgo(1), daysAgo(3)]) }
        let stale = TopicHistory(id: UUID(), theme: .breathSupport, occurrences: [daysAgo(200)])
        let plan = planner.plan(topics: fresh + [stale], lengthMinutes: 15, now: now)
        #expect(plan.count == 3)
        #expect(!plan.contains { $0.topicID == stale.id })

        let mixed = [
            TopicHistory(id: UUID(), theme: .repertoire, occurrences: [daysAgo(1)]),
            TopicHistory(id: UUID(), theme: .breathSupport, occurrences: [daysAgo(1)]),
        ]
        #expect(planner.plan(topics: mixed, lengthMinutes: 15, now: now).map(\.theme) == [.breathSupport, .repertoire])
    }

    @Test func noTopicsNoPlan() {
        #expect(planner.plan(topics: [], lengthMinutes: 30, now: now).isEmpty)
        #expect(planner.plan(topics: [TopicHistory(id: UUID(), theme: .vowels, occurrences: [])], lengthMinutes: 30, now: now).isEmpty)
    }

    @Test func planIsDeterministic() {
        let set = topics(9)
        #expect(planner.plan(topics: set, lengthMinutes: 45, now: now) == planner.plan(topics: set.reversed(), lengthMinutes: 45, now: now))
    }
}

@Suite("Backup archive")
struct TarArchiveTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("passaggio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripsFilesOfAwkwardSizes() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sizes = [0, 1, 511, 512, 513, 1_500_000]
        var entries: [(path: String, source: URL)] = []
        for (i, size) in sizes.enumerated() {
            let source = dir.appendingPathComponent("src-\(i)")
            let bytes = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ i) }
            try Data(bytes).write(to: source)
            entries.append((i == 0 ? "manifest.json" : "recordings/file-\(i).m4a", source))
        }

        let archive = dir.appendingPathComponent("backup.passaggiobackup")
        try TarArchive.write(entries: entries, to: archive)

        let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as! NSNumber
        #expect(size.intValue % 512 == 0)

        let out = dir.appendingPathComponent("out")
        let paths = try TarArchive.extract(from: archive, into: out)
        #expect(paths == entries.map(\.path))
        for entry in entries {
            let original = try Data(contentsOf: entry.source)
            let restored = try Data(contentsOf: out.appendingPathComponent(entry.path))
            #expect(original == restored, "\(entry.path) differs")
        }
    }

    @Test(arguments: ["../evil", "/abs", "a/../b", "a//b", "a\\b", "", "./x"])
    func rejectsUnsafePaths(_ path: String) {
        #expect(throws: TarArchive.Error.unsafePath(path)) { try TarArchive.validate(path: path) }
    }

    @Test func detectsCorruptHeaders() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("a")
        try Data("hello".utf8).write(to: source)
        let archive = dir.appendingPathComponent("a.tar")
        try TarArchive.write(entries: [("a.txt", source)], to: archive)

        var bytes = try Data(contentsOf: archive)
        bytes[3] ^= 0xFF
        try bytes.write(to: archive)
        #expect(throws: TarArchive.Error.corruptHeader) { try TarArchive.extract(from: archive, into: dir.appendingPathComponent("o")) }
    }

    @Test func detectsTruncation() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("a")
        try Data(count: 5000).write(to: source)
        let archive = dir.appendingPathComponent("a.tar")
        try TarArchive.write(entries: [("a.bin", source)], to: archive)
        let bytes = try Data(contentsOf: archive)
        try bytes.prefix(2048).write(to: archive)
        #expect(throws: TarArchive.Error.truncated) { try TarArchive.extract(from: archive, into: dir.appendingPathComponent("o")) }
    }

    @Test func headerChecksumMatchesUstarDefinition() throws {
        let header = try TarArchive.header(path: "manifest.json", size: 42, modified: Date(timeIntervalSince1970: 0))
        #expect(header.count == 512)
        #expect(TarArchive.verifyChecksum([UInt8](header)))
        #expect(String(decoding: header[257..<262], as: UTF8.self) == "ustar")
        #expect(TarArchive.parseOctal([UInt8](header)[124..<136]) == 42)
    }
}
