import PassaggioCore
import SwiftData
import SwiftUI

struct TranscriptView: View {
    let lesson: Lesson
    /// A line to scroll to and briefly highlight, set when another tab sends you here.
    /// Cleared once it's shown.
    @Binding var focusedSegment: PersistentIdentifier?
    var onJump: (TimeInterval) -> Void

    @Environment(\.modelContext) private var context
    @State private var teacherOnly = false
    @State private var highlighted: PersistentIdentifier?

    private var segments: [TranscriptSegment] {
        let all = lesson.sortedSegments
        return teacherOnly ? all.filter { $0.role == .teacher } : all
    }

    var body: some View {
        ScrollViewReader { proxy in
            transcriptList
                .task(id: focusedSegment) {
                    guard let id = focusedSegment else { return }
                    await Task.yield()
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    highlighted = id
                    focusedSegment = nil
                }
                .task(id: highlighted) {
                    guard highlighted != nil, (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                    withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
                }
        }
    }

    private var transcriptList: some View {
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
                    .listRowBackground(highlighted == segment.persistentModelID ? Color.accentColor.opacity(0.18) : nil)
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
