import PassaggioCore
import SwiftData
import SwiftUI

struct RoutineDetailView: View {
    let routine: Routine

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var isRegenerating = false
    @State private var showingSession = false
    @State private var confirmRegenerate = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    showingSession = true
                } label: {
                    Label("Start Practice", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityHint("Steps through each exercise with a timer")
            }

            ForEach(routine.sortedExercises) { exercise in
                Section {
                    ExerciseCard(exercise: exercise)
                } header: {
                    HStack {
                        exercise.theme.label
                        Spacer()
                        Text("\(exercise.minutes) min")
                    }
                }
            }

            Section("History") {
                if routine.sessions.isEmpty {
                    Text("Not practised yet").foregroundStyle(.secondary)
                } else {
                    ForEach(routine.sessions.sorted { $0.date > $1.date }) { session in
                        Label {
                            Text(session.date, format: .dateTime.weekday(.wide).day().month().hour().minute())
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                Button("Mark Session Done") { markDone() }
            }
        }
        .navigationTitle("\(routine.lengthMinutes)-Minute Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    confirmRegenerate = true
                } label: {
                    if isRegenerating {
                        ProgressView()
                    } else {
                        Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRegenerating)
            }
        }
        .confirmationDialog("Regenerate this routine?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Regenerate") { Task { await regenerate() } }
        } message: {
            Text("The exercises are rebuilt from your latest lesson feedback. Practice history is kept.")
        }
        .fullScreenCover(isPresented: $showingSession) {
            PracticeSessionView(routine: routine)
        }
        .errorAlert(message: $errorMessage)
    }

    private func markDone() {
        let session = PracticeSession()
        context.insert(session)
        session.routine = routine
        try? context.save()
    }

    private func regenerate() async {
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            try await RoutineGenerator.generate(lengthMinutes: routine.lengthMinutes, replacing: routine, context: context, settings: settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ExerciseCard: View {
    let exercise: RoutineExercise
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.title)
                .font(.headline)
            Text(exercise.instructions)
            if !exercise.goal.isEmpty {
                Label {
                    Text(exercise.goal)
                } icon: {
                    Image(systemName: "target")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)

        if let track = PracticeTrack.resolve(exercise.trackReference, context: context) {
            TrackPlayerCard(track: track)
                .padding(.vertical, 4)
        }

        ForEach(exercise.sortedSources) { source in
            if let lesson = source.lesson {
                NavigationLink(value: LessonMoment(lessonID: lesson.id, time: source.timestamp)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(source.quote.isEmpty ? source.summary : source.quote)”")
                            .font(.callout)
                            .italic()
                            .lineLimit(3)
                        Text("\(lesson.date, format: .dateTime.day().month(.abbreviated)) at \(formatTimestamp(source.timestamp))")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .accessibilityHint("Opens the lesson where your teacher said this")
            }
        }
    }
}
