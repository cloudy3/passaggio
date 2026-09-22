import PassaggioCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LessonListView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: \Lesson.date, order: .reverse) private var lessons: [Lesson]

    @State private var path = NavigationPath()
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(lessons) { lesson in
                    NavigationLink(value: LessonMoment(lessonID: lesson.id, time: -1)) {
                        LessonRow(lesson: lesson)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if lessons.isEmpty {
                    ContentUnavailableView {
                        Label("No Lessons Yet", systemImage: "waveform")
                    } description: {
                        Text("Import a lesson recording from Files, or share it from Voice Memos and choose Passaggio.")
                    } actions: {
                        Button("Import Recording") { showingImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Lessons")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Recording", systemImage: "plus")
                    }
                    .disabled(isImporting)
                }
            }
            .navigationDestination(for: LessonMoment.self) { moment in
                LessonDestination(moment: moment)
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    Task { await importFiles(urls) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .overlay(alignment: .bottom) {
                if isImporting {
                    ProgressView("Importing…")
                        .padding()
                        .background(.regularMaterial, in: .capsule)
                        .padding()
                }
            }
            .errorAlert("Couldn’t import", message: $errorMessage)
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        for url in urls {
            do {
                _ = try await LessonImporter.importRecording(from: url, into: context)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let lesson = lessons[index]
            if player.isCurrent(lesson.id.uuidString) { player.stop() }
            FileStore.removeIfPresent(lesson.fileURL)
            context.delete(lesson)
        }
        do {
            try context.save()
            try LessonProcessor.deleteOrphanTopics(context: context)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LessonRow: View {
    let lesson: Lesson
    @Environment(LessonProcessor.self) private var processor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lesson.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(lesson.date, format: .dateTime.day().month(.abbreviated).year())
                Text("·")
                Text(Duration.seconds(lesson.duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            statusLabel
                .font(.caption)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let progress = processor.progress[lesson.id] {
            Label(progress.message, systemImage: "hourglass")
                .foregroundStyle(.secondary)
        } else {
            switch lesson.status {
            case .imported:
                Label("Not transcribed", systemImage: "text.badge.plus").foregroundStyle(.secondary)
            case .transcribing, .analyzing:
                Label("Interrupted — open to resume", systemImage: "pause.circle").foregroundStyle(.secondary)
            case .needsSpeakers:
                Label("Choose which speaker is your teacher", systemImage: "person.2.badge.gearshape").foregroundStyle(.orange)
            case .analyzed:
                Label("\(lesson.keyPoints.count) key points", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            case .failed:
                Label("Failed — open to retry", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        }
    }
}

/// Resolves a lesson ID from navigation into the detail screen.
struct LessonDestination: View {
    let moment: LessonMoment
    @Query private var matches: [Lesson]

    init(moment: LessonMoment) {
        self.moment = moment
        let id = moment.lessonID
        _matches = Query(filter: #Predicate<Lesson> { $0.id == id })
    }

    var body: some View {
        if let lesson = matches.first {
            LessonDetailView(lesson: lesson, startAt: moment.time >= 0 ? moment.time : nil)
        } else {
            ContentUnavailableView("Lesson Not Found", systemImage: "questionmark.folder")
        }
    }
}
