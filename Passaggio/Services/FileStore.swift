import Foundation

/// Where the app keeps audio. Everything lives under Application Support, which is
/// private to the app, survives reinstalls over the same bundle ID, and is included
/// in device backups.
nonisolated enum FileStore {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Passaggio", isDirectory: true)
    }()

    static let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    static let references = root.appendingPathComponent("SpeakerReferences", isDirectory: true)

    /// Regenerable files (rendered exercise tracks, transcription chunks, exports).
    static let cache: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Passaggio", isDirectory: true)
    }()

    static var renders: URL { cache.appendingPathComponent("Renders", isDirectory: true) }

    static func prepare() throws {
        for directory in [recordings, references, renders] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// A fresh scratch directory, removed by the caller when done.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeIfPresent(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
