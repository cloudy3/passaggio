import PassaggioCore
import SwiftData
import SwiftUI

struct LessonDetailView: View {
    @Bindable var lesson: Lesson
    var startAt: TimeInterval?

    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Environment(LessonProcessor.self) private var processor

    enum Pane: String, CaseIterable, Identifiable {
        case notes = "Key Points"
        case transcript = "Transcript"
        case details = "Details"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .notes
    @State private var focusedSegment: PersistentIdentifier?
    @State private var rangeTask: RangeSelectionSheet.Purpose?
    @State private var errorMessage: String?
    @State private var didApplyStart = false

    private var playerID: String { lesson.id.uuidString }
    private var isCurrent: Bool { player.isCurrent(playerID) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch pane {
            case .notes:
                KeyPointsView(lesson: lesson, onJump: { jump(to: $0) }, onShowInTranscript: { segment in
                    focusedSegment = segment.persistentModelID
                    pane = .transcript
                    jump(to: segment.start, leadIn: 0)
                })
            case .transcript:
                TranscriptView(lesson: lesson, focusedSegment: $focusedSegment, onJump: { jump(to: $0, leadIn: 0) })
            case .details:
                LessonDetailsForm(lesson: lesson)
            }
        }
        .safeAreaInset(edge: .bottom) {
            playerPanel
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        rangeTask = .clip
                    } label: {
                        Label("Save Practice Clip…", systemImage: "scissors")
                    }
                    Divider()
                    Button {
                        rangeTask = .reference(.teacher)
                    } label: {
                        Label("Mark Teacher’s Voice…", systemImage: "person.wave.2")
                    }
                    Button {
                        rangeTask = .reference(.student)
                    } label: {
                        Label("Mark My Voice…", systemImage: "person.crop.circle")
                    }
                    Divider()
                    Button {
                        processor.process(lesson, context: context, retranscribe: true)
                    } label: {
                        Label("Transcribe Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(processor.isRunning(lesson))
                    Button {
                        processor.reanalyze(lesson, context: context)
                    } label: {
                        Label("Find Key Points Again", systemImage: "sparkles")
                    }
                    .disabled(processor.isRunning(lesson) || lesson.segments.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $rangeTask) { purpose in
            RangeSelectionSheet(lesson: lesson, purpose: purpose)
        }
        .onAppear(perform: prepare)
        .errorAlert(message: $errorMessage)
    }

    private var playerPanel: some View {
        VStack(spacing: 10) {
            WaveformView(
                samples: lesson.waveform,
                duration: lesson.duration,
                currentTime: isCurrent ? player.currentTime : 0,
                markers: lesson.keyPoints.map(\.timestamp),
                onScrub: { time in
                    ensureLoaded()
                    player.seek(to: time)
                }
            )
            .frame(height: 64)
            TimeRow(current: isCurrent ? player.currentTime : 0, total: lesson.duration)
            TransportControls(
                isPlaying: isCurrent && player.isPlaying,
                onSkip: { delta in
                    ensureLoaded()
                    player.skip(by: delta)
                },
                onPlayPause: {
                    ensureLoaded()
                    player.togglePlayPause()
                }
            )
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func prepare() {
        guard !didApplyStart else { return }
        didApplyStart = true
        if let startAt {
            jump(to: startAt)
        }
    }

    private func ensureLoaded() {
        if !isCurrent {
            player.load(lesson.fileURL, id: playerID)
            if let message = player.errorMessage { errorMessage = message }
        } else if player.loopRange != nil {
            player.setLoop(nil)
        }
    }

    /// Key points seek a little before the moment so the correction is heard in context.
    private func jump(to time: TimeInterval, leadIn: TimeInterval = 1.5) {
        ensureLoaded()
        player.seek(to: max(0, time - leadIn))
        player.play()
    }
}

struct LessonDetailsForm: View {
    @Bindable var lesson: Lesson
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Lesson") {
                TextField("Title", text: $lesson.title)
                DatePicker("Date", selection: $lesson.date)
                LabeledContent("Length") {
                    Text(Duration.seconds(lesson.duration), format: .time(pattern: .hourMinuteSecond))
                }
            }
            Section("My Notes") {
                TextField("Notes about this lesson", text: $lesson.notes, axis: .vertical)
                    .lineLimit(4...12)
            }
            if !lesson.clips.isEmpty {
                Section("Practice Clips") {
                    ForEach(lesson.clips.sorted { $0.start < $1.start }) { clip in
                        LabeledContent(clip.name) {
                            Text("\(formatTimestamp(clip.start))–\(formatTimestamp(clip.end))")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .onDisappear { try? context.save() }
    }
}

#if DEBUG
#Preview("Lesson", traits: .sampleData) {
    @Previewable @Query(sort: \Lesson.date, order: .reverse) var lessons: [Lesson]
    NavigationStack {
        if let lesson = lessons.first(where: { $0.status == .analyzed }) {
            LessonDetailView(lesson: lesson)
        }
    }
}

#Preview("Lesson, speakers not labelled", traits: .sampleData) {
    @Previewable @Query(sort: \Lesson.date, order: .reverse) var lessons: [Lesson]
    NavigationStack {
        if let lesson = lessons.first(where: { $0.status == .needsSpeakers }) {
            LessonDetailView(lesson: lesson)
        }
    }
}

#Preview("Lesson, dark, large text", traits: .sampleData) {
    @Previewable @Query(sort: \Lesson.date, order: .reverse) var lessons: [Lesson]
    NavigationStack {
        if let lesson = lessons.first(where: { $0.status == .analyzed }) {
            LessonDetailView(lesson: lesson)
        }
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
#endif
