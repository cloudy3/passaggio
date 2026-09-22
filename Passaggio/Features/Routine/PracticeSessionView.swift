import PassaggioCore
import SwiftData
import SwiftUI

/// Full-screen practice mode for use while singing, often with the phone on a
/// stand: one exercise at a time, large high-contrast controls in the bottom third,
/// and the screen kept awake.
struct PracticeSessionView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player

    @State private var index = 0
    @State private var remaining: TimeInterval = 0
    @State private var timerRunning = false
    @State private var finished = false

    private var exercises: [RoutineExercise] { routine.sortedExercises }
    private var exercise: RoutineExercise? { exercises.indices.contains(index) ? exercises[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if finished {
                    finishedView
                } else if let exercise {
                    exerciseView(exercise)
                } else {
                    ContentUnavailableView("No Exercises", systemImage: "list.bullet")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { close() }
                }
                ToolbarItem(placement: .principal) {
                    if !finished, !exercises.isEmpty {
                        Text("Exercise \(index + 1) of \(exercises.count)")
                            .font(.headline)
                    }
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            resetTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task(id: timerRunning) {
            guard timerRunning else { return }
            while timerRunning, remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if timerRunning { remaining = max(0, remaining - 1) }
            }
            if remaining == 0 { timerRunning = false }
        }
        // A haptic tap when time is up, so you needn’t watch the screen.
        .sensoryFeedback(.success, trigger: remaining) { old, new in old > 0 && new == 0 }
    }

    private func exerciseView(_ exercise: RoutineExercise) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    exercise.theme.label
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(exercise.title)
                        .font(.largeTitle.bold())
                    Text(exercise.instructions)
                        .font(.title3)
                    if !exercise.goal.isEmpty {
                        Label(exercise.goal, systemImage: "target")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    if let source = exercise.sortedSources.first, !source.quote.isEmpty {
                        Text("Your teacher: “\(source.quote)”")
                            .font(.body)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    if let track = PracticeTrack.resolve(exercise.trackReference, context: context) {
                        TrackPlayerCard(track: track)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            controls
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(remaining == 0 ? Color.accentColor : .primary)
                .accessibilityLabel("Time remaining")
                .accessibilityValue(Duration.seconds(remaining).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))

            HStack(spacing: 28) {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 72, height: 72)
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous exercise")

                Button {
                    timerRunning.toggle()
                } label: {
                    Image(systemName: timerRunning ? "pause.fill" : "timer")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Color.accentColor, in: Circle())
                }
                .accessibilityLabel(timerRunning ? "Pause timer" : "Start timer")

                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: index == exercises.count - 1 ? "checkmark" : "forward.end.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 72, height: 72)
                }
                .accessibilityLabel(index == exercises.count - 1 ? "Finish session" : "Next exercise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var finishedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Session Done")
                .font(.largeTitle.bold())
            Text("Logged to this routine’s history.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                close()
            } label: {
                Text("Close")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func move(by delta: Int) {
        player.pause()
        let next = index + delta
        if next >= exercises.count {
            finish()
        } else if next >= 0 {
            index = next
            resetTimer()
        }
    }

    private func resetTimer() {
        timerRunning = false
        remaining = TimeInterval((exercise?.minutes ?? 0) * 60)
    }

    private func finish() {
        let session = PracticeSession()
        context.insert(session)
        session.routine = routine
        try? context.save()
        timerRunning = false
        finished = true
    }

    private func close() {
        player.pause()
        dismiss()
    }
}
