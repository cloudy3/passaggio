import PassaggioCore
import SwiftData
import SwiftUI

struct KeyPointsView: View {
    let lesson: Lesson
    var onJump: (TimeInterval) -> Void
    var onShowInTranscript: (TranscriptSegment) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(LessonProcessor.self) private var processor

    var body: some View {
        List {
            statusSection

            if lesson.status == .needsSpeakers {
                SpeakerAssignmentSection(lesson: lesson, onShowInTranscript: onShowInTranscript)
            }

            let grouped = Dictionary(grouping: lesson.sortedKeyPoints, by: \.theme)
            ForEach(Theme.allCases.filter { grouped[$0] != nil }) { theme in
                Section {
                    ForEach(grouped[theme] ?? []) { point in
                        KeyPointRow(point: point, currentLessonID: lesson.id, onJump: onJump)
                    }
                } header: {
                    theme.label
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let progress = processor.progress[lesson.id] {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction) { Text(progress.message) }
                    } else {
                        ProgressView { Text(progress.message) }
                    }
                    Button("Cancel", role: .cancel) { processor.cancel(lesson) }
                }
            }
        } else {
            switch lesson.status {
            case .imported, .transcribing, .analyzing:
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcribe this lesson to pull out your teacher’s feedback. Only the teacher’s speech is sent for key points.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            processor.process(lesson, context: context)
                        } label: {
                            Label("Transcribe and Find Key Points", systemImage: "text.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .failed:
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(lesson.lastError ?? "Processing failed.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            processor.process(lesson, context: context)
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .analyzed where lesson.keyPoints.isEmpty:
                Section {
                    Text("No teacher feedback was found in this lesson.")
                        .foregroundStyle(.secondary)
                }
            case .needsSpeakers, .analyzed:
                EmptyView()
            }
        }
    }
}

struct KeyPointRow: View {
    let point: KeyPoint
    let currentLessonID: UUID
    var onJump: (TimeInterval) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var otherLessons: Int {
        (point.topic?.lessons.filter { $0.id != currentLessonID }.count) ?? 0
    }

    var body: some View {
        Button {
            onJump(point.timestamp)
        } label: {
            // At accessibility sizes the timestamp moves under the text, which would
            // otherwise be squeezed into a narrow column a few words wide.
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(point.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !point.quote.isEmpty {
                        Text("“\(point.quote)”")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    if otherLessons > 0 {
                        Label(otherLessons == 1 ? "Also said in 1 other lesson" : "Also said in \(otherLessons) other lessons",
                              systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                            .labelIconToTitleSpacing(4)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if !stacked { Spacer(minLength: 8) }
                Label(formatTimestamp(point.timestamp), systemImage: "play.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .labelIconToTitleSpacing(6)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays the lesson from \(formatTimestamp(point.timestamp))")
    }
}

/// Shown when the transcript has no teacher labels (no reference clips were set up):
/// the user picks which anonymous speaker is the teacher.
struct SpeakerAssignmentSection: View {
    let lesson: Lesson
    /// Tapping a speaker's sample line shows it in the transcript and plays from it,
    /// so you can hear who it is before labelling.
    var onShowInTranscript: (TranscriptSegment) -> Void
    @Environment(\.modelContext) private var context
    @Environment(LessonProcessor.self) private var processor

    private struct SpeakerSummary: Identifiable {
        var label: String
        var sample: TranscriptSegment
        var count: Int
        var id: String { label }
    }

    private var speakers: [SpeakerSummary] {
        let groups = Dictionary(grouping: lesson.sortedSegments.filter { $0.role == .unknown }, by: \.speaker)
        return groups
            .compactMap { label, segments in
                guard let longest = segments.max(by: { $0.text.count < $1.text.count }) else { return nil }
                return SpeakerSummary(label: label, sample: longest, count: segments.count)
            }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        Section {
            ForEach(speakers) { speaker in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speaker \(speaker.label) · \(speaker.count) lines")
                        .font(.headline)
                    Button {
                        onShowInTranscript(speaker.sample)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("“\(speaker.sample.text)”")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Label(formatTimestamp(speaker.sample.start), systemImage: "text.magnifyingglass")
                                .labelStyle(.titleAndIcon)
                                .labelIconToTitleSpacing(4)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Line at \(formatTimestamp(speaker.sample.start)): \(speaker.sample.text)")
                    .accessibilityHint("Shows this line in the transcript and plays from here")
                    .accessibilityAddTraits(.isButton)
                    HStack {
                        Button("Teacher") { assign(speaker.label, to: .teacher) }
                            .buttonStyle(.borderedProminent)
                        Button("Me") { assign(speaker.label, to: .student) }
                            .buttonStyle(.bordered)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Speaker \(speaker.label)")
                }
                .padding(.vertical, 4)
            }
            Button {
                processor.reanalyze(lesson, context: context)
            } label: {
                Label("Find Key Points", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!lesson.segments.contains { $0.role == .teacher })
        } header: {
            Text("Who is your teacher?")
        } footer: {
            Text("Mark a few seconds of your teacher’s voice and your own (menu › Mark Teacher’s Voice) and future lessons are labelled automatically.")
        }
    }

    private func assign(_ label: String, to role: SpeakerRole) {
        for segment in lesson.segments where segment.speaker == label {
            segment.role = role
        }
        try? context.save()
    }
}
