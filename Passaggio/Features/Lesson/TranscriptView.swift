import PassaggioCore
import SwiftData
import SwiftUI

struct TranscriptView: View {
    let lesson: Lesson
    var onJump: (TimeInterval) -> Void

    @Environment(\.modelContext) private var context
    @State private var teacherOnly = false

    private var segments: [TranscriptSegment] {
        let all = lesson.sortedSegments
        return teacherOnly ? all.filter { $0.role == .teacher } : all
    }

    var body: some View {
        List {
            if lesson.segments.isEmpty {
                ContentUnavailableView("No Transcript Yet", systemImage: "text.alignleft",
                                       description: Text("Transcribe the lesson from the Key Points tab."))
            } else {
                Toggle("Teacher only", isOn: $teacherOnly)
                ForEach(segments) { segment in
                    Button {
                        onJump(segment.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(label(for: segment))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(segment.role == .teacher ? Color.accentColor : .secondary)
                                Spacer()
                                Text(formatTimestamp(segment.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(segment.text)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Plays from here")
                    .contextMenu {
                        Button("Label This Speaker as Teacher") { relabel(segment.speaker, as: .teacher) }
                        Button("Label This Speaker as Me") { relabel(segment.speaker, as: .student) }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func label(for segment: TranscriptSegment) -> String {
        segment.role == .unknown ? "Speaker \(segment.speaker)" : segment.role.displayName
    }

    private func relabel(_ speaker: String, as role: SpeakerRole) {
        for segment in lesson.segments where segment.speaker == speaker {
            segment.role = role
        }
        if lesson.status == .analyzed || lesson.status == .needsSpeakers {
            lesson.status = .needsSpeakers
        }
        try? context.save()
    }
}
