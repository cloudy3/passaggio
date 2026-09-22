import AVFoundation
import Foundation
import SwiftData

/// Copies a recording into the app and creates its `Lesson`.
enum LessonImporter {
    nonisolated struct Metadata: Sendable {
        var recordedAt: Date
        var title: String
    }

    static func importRecording(from source: URL, into context: ModelContext) async throws -> Lesson {
        try FileStore.prepare()
        let fileName = "\(UUID().uuidString).\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased())"
        let destination = FileStore.recordings.appendingPathComponent(fileName)

        // Files from .fileImporter are security-scoped; "Open in" files already sit in
        // our Inbox and aren't. Accessing a non-scoped URL is harmless.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        // Read the original's creation date before copying: the copy's is "now".
        let originalCreated = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.creationDate] as? Date
        try copyCoordinated(from: source, to: destination)

        do {
            let metadata = await readMetadata(of: destination, originalURL: source, fileCreated: originalCreated)
            let analysis = try await AudioAnalysis.analyze(url: destination)
            let lesson = Lesson(
                title: metadata.title,
                date: metadata.recordedAt,
                duration: analysis.duration,
                fileName: fileName,
                waveform: analysis.waveform
            )
            context.insert(lesson)
            try context.save()
            return lesson
        } catch {
            FileStore.removeIfPresent(destination)
            throw error
        }
    }

    /// Coordinated read so files still downloading from a provider are fetched first.
    private static func copyCoordinated(from source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            do {
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }

    /// Recording date: the file's embedded creation date (Voice Memos writes one),
    /// then the file's own creation date, then now. It's editable afterwards.
    static func readMetadata(of url: URL, originalURL: URL, fileCreated: Date?) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var date: Date?
        if let item = try? await asset.load(.creationDate) {
            date = try? await item.load(.dateValue)
        }
        date = date ?? fileCreated
        let title = originalURL.deletingPathExtension().lastPathComponent
        return Metadata(recordedAt: date ?? .now, title: title.isEmpty ? "Lesson" : title)
    }
}
