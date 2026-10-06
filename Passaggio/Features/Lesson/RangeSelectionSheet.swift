import PassaggioCore
import SwiftData
import SwiftUI

/// Selects a stretch of a lesson, either to save as a practice clip or as a
/// reference sample of a speaker's voice.
struct RangeSelectionSheet: View {
    enum Purpose: Identifiable, Hashable {
        case clip
        case reference(SpeakerRole)

        var id: String {
            switch self {
            case .clip: "clip"
            case .reference(let role): "reference-\(role.rawValue)"
            }
        }

        var title: String {
            switch self {
            case .clip: "New Practice Clip"
            case .reference(.teacher): "Teacher’s Voice"
            case .reference: "My Voice"
            }
        }

        var defaultLength: TimeInterval {
            switch self {
            case .clip: 20
            // Lessons are mostly the teacher talking, so a long stretch of only the
            // student's voice is hard to find. The API accepts 2 s.
            case .reference(.student): 2
            case .reference: 6
            }
        }
    }

    let lesson: Lesson
    let purpose: Purpose

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player

    @State private var start: TimeInterval = 0
    @State private var end: TimeInterval = 0
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var previewID: String { "range-\(lesson.id.uuidString)" }
    private var isPreviewing: Bool { player.isCurrent(previewID) && player.isPlaying }
    private var length: TimeInterval { end - start }

    private var validationMessage: String? {
        switch purpose {
        case .clip:
            if length < 1 { return "Select at least a second." }
            if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the clip a name." }
        case .reference:
            let allowed = SpeakerReferenceClip.allowedDuration
            if !SpeakerReferenceClip.accepts(duration: length) {
                return "Select \(Int(allowed.lowerBound))–\(Int(allowed.upperBound)) seconds of only this voice (now \(String(format: "%.1f", length)) s)."
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WaveformView(
                        samples: lesson.waveform,
                        duration: lesson.duration,
                        currentTime: player.isCurrent(previewID) ? player.currentTime : start,
                        selection: start...max(start, end),
                        onScrub: { time in
                            let length = max(self.length, 1)
                            start = min(time, max(0, lesson.duration - length))
                            end = min(lesson.duration, start + length)
                            restartPreviewIfPlaying()
                        }
                    )
                    .frame(height: 72)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } footer: {
                    Text("Drag on the waveform to move the selection, then fine-tune its edges below.")
                }

                Section("Selection") {
                    EdgeAdjuster(title: "Start", time: $start, range: 0...max(0, end - 0.5))
                    EdgeAdjuster(title: "End", time: $end, range: min(lesson.duration, start + 0.5)...lesson.duration)
                    LabeledContent("Length", value: String(format: "%.1f s", length))
                    Button {
                        togglePreview()
                    } label: {
                        Label(isPreviewing ? "Stop Preview" : "Preview Selection",
                              systemImage: isPreviewing ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                if case .clip = purpose {
                    Section("Name") {
                        TextField("e.g. Lip trill on 1-5-1", text: $name)
                    }
                } else {
                    Section {
                        Text("Pick a stretch where only this person is speaking — no piano or singing. It’s sent with every transcription so speakers are labelled the same way in every lesson. Marking again replaces the previous sample.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(purpose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(validationMessage != nil || isSaving)
                }
            }
            .onAppear(perform: setInitialRange)
            .errorAlert(message: $errorMessage)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func setInitialRange() {
        let playhead = player.isCurrent(lesson.id.uuidString) ? player.currentTime : 0
        start = min(playhead, max(0, lesson.duration - purpose.defaultLength))
        end = min(lesson.duration, start + purpose.defaultLength)
    }

    private func togglePreview() {
        if isPreviewing {
            player.pause()
        } else {
            player.load(lesson.fileURL, id: previewID, loop: start...end)
            player.setLoop(start...end)
            player.seek(to: start)
            player.play()
        }
    }

    private func restartPreviewIfPlaying() {
        guard isPreviewing else { return }
        player.setLoop(start...end)
        player.seek(to: start)
    }

    private func close() {
        if player.isCurrent(previewID) { player.stop() }
        dismiss()
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch purpose {
            case .clip:
                let clip = PracticeClip(name: name.trimmingCharacters(in: .whitespaces), start: start, end: end)
                context.insert(clip)
                clip.lesson = lesson
            case .reference(let role):
                let fileName = "\(role.rawValue)-\(UUID().uuidString).wav"
                let url = FileStore.references.appendingPathComponent(fileName)
                try await AudioExport.exportWAV(from: lesson.fileURL, range: start...end, to: url)
                // One sample per role: the newest replaces the old one.
                let roleRaw = role.rawValue
                let existing = try context.fetch(FetchDescriptor<SpeakerReference>(predicate: #Predicate { $0.roleRaw == roleRaw }))
                for old in existing {
                    FileStore.removeIfPresent(old.fileURL)
                    context.delete(old)
                }
                context.insert(SpeakerReference(role: role, fileName: fileName, duration: length))
            }
            try context.save()
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A time value with ±0.1 s / ±1 s nudges, big enough to hit reliably.
private struct EdgeAdjuster: View {
    let title: String
    @Binding var time: TimeInterval
    let range: ClosedRange<TimeInterval>

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button { nudge(-1) } label: { Image(systemName: "backward.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("\(title) back one second")
            Button { nudge(-0.1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("\(title) back a tenth of a second")
            Text(String(format: "%@.%d", formatTimestamp(time), Int((time * 10).truncatingRemainder(dividingBy: 10))))
                .monospacedDigit()
                .frame(minWidth: 64)
            Button { nudge(0.1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("\(title) forward a tenth of a second")
            Button { nudge(1) } label: { Image(systemName: "forward.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("\(title) forward one second")
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityValue(formatTimestamp(time))
    }

    private func nudge(_ delta: TimeInterval) {
        time = min(max(time + delta, range.lowerBound), range.upperBound)
    }
}
