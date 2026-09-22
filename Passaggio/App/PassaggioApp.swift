import SwiftData
import SwiftUI

@main
struct PassaggioApp: App {
    @State private var settings: AppSettings
    @State private var player = PlayerController()
    @State private var processor: LessonProcessor
    private let container: ModelContainer

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _processor = State(initialValue: LessonProcessor(settings: settings))
        do {
            try FileStore.prepare()
            container = try ModelContainer(for: Schema(PassaggioSchema.models))
            try BuiltInPresets.seedIfNeeded(context: container.mainContext)
        } catch {
            // Nothing useful can run without storage; surface the cause in the crash log.
            fatalError("Couldn't open the Passaggio database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(player)
                .environment(processor)
        }
        .modelContainer(container)
    }
}
