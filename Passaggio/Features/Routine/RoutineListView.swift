import PassaggioCore
import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    /// Routines are built from feedback topics, so there's nothing to build until a lesson is analysed.
    @Query private var topics: [FeedbackTopic]

    @State private var path = NavigationPath()
    @State private var generatingLength: Int?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(RoutinePlanner.lengths, id: \.self) { length in
                        Button {
                            Task { await generate(length) }
                        } label: {
                            HStack {
                                Label("New \(length)-minute routine", systemImage: "sparkles")
                                Spacer()
                                if generatingLength == length { ProgressView() }
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(generatingLength != nil || topics.isEmpty)
                    }
                } footer: {
                    if topics.isEmpty {
                        Text("Routines are built from your teacher’s feedback. Transcribe a lesson to get started.")
                    } else {
                        Text("Built from your lesson feedback, weighted toward points your teacher repeats and recent lessons.")
                    }
                }

                if !routines.isEmpty {
                    Section("Saved Routines") {
                        ForEach(routines) { routine in
                            NavigationLink(value: routine) {
                                RoutineRow(routine: routine)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(routines[index]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Practice")
            .navigationDestination(for: Routine.self) { routine in
                RoutineDetailView(routine: routine)
            }
            .navigationDestination(for: LessonMoment.self) { moment in
                LessonDestination(moment: moment)
            }
            .errorAlert("Couldn’t create a routine", message: $errorMessage)
        }
    }

    private func generate(_ length: Int) async {
        generatingLength = length
        defer { generatingLength = nil }
        do {
            let routine = try await RoutineGenerator.generate(lengthMinutes: length, context: context, settings: settings)
            path.append(routine)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(routine.lengthMinutes)-minute routine")
                .font(.headline)
            Text(routine.sortedExercises.map(\.title).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Group {
                if let last = routine.lastPracticed {
                    Text("Practised \(routine.sessions.count)× · last \(last, format: .relative(presentation: .named))")
                } else {
                    Text("Created \(routine.createdAt, format: .dateTime.day().month(.abbreviated))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Practice", traits: .sampleData) {
    RoutineListView()
}
#endif
