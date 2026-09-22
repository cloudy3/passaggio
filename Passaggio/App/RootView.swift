import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case lessons, insights, practice, tracks, settings
}

/// Navigation target for "jump to this moment in the lesson".
struct LessonMoment: Hashable {
    var lessonID: UUID
    var time: TimeInterval
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .lessons
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Lessons", systemImage: "waveform", value: AppTab.lessons) {
                LessonListView()
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: AppTab.insights) {
                InsightsView()
            }
            Tab("Practice", systemImage: "figure.mind.and.body", value: AppTab.practice) {
                RoutineListView()
            }
            Tab("Tracks", systemImage: "pianokeys", value: AppTab.tracks) {
                TracksView()
            }
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                SettingsView()
            }
        }
        // "Open in Passaggio" from Voice Memos or Files lands here.
        .onOpenURL { url in
            Task { await handleIncoming(url) }
        }
        .overlay {
            if isImporting {
                ProgressView("Importing…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .errorAlert("Couldn’t import", message: $importError)
    }

    private func handleIncoming(_ url: URL) async {
        if url.pathExtension.lowercased() == "passaggiobackup" {
            tab = .settings
            PendingRestore.shared.url = url
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            _ = try await LessonImporter.importRecording(from: url, into: context)
            tab = .lessons
        } catch {
            importError = error.localizedDescription
        }
        // "Open in" copies land in Documents/Inbox; our copy is made, so clean up.
        if url.path.contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// A backup opened from Files ("Open in Passaggio"), picked up by Settings.
@Observable
final class PendingRestore {
    static let shared = PendingRestore()
    var url: URL?
}
