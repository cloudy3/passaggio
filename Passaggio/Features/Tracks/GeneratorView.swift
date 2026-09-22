import PassaggioCore
import SwiftData
import SwiftUI

/// Edits a generated exercise and previews, loops and exports it.
struct GeneratorView: View {
    @Bindable var preset: GeneratorPreset

    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player

    @State private var spec = ExerciseSpec()
    @State private var customDegrees = ""
    @State private var isRendering = false
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?
    @State private var loaded = false

    private enum PatternChoice: Hashable {
        case builtIn(ExercisePattern)
        case custom
    }

    private var patternChoice: Binding<PatternChoice> {
        Binding {
            if case .custom = spec.pattern { return .custom }
            return .builtIn(spec.pattern)
        } set: { choice in
            switch choice {
            case .builtIn(let pattern): spec.pattern = pattern
            case .custom: spec.pattern = .custom(customDegrees.isEmpty ? "1 3 5 3 1" : customDegrees)
            }
        }
    }

    private var sequence: Result<ExerciseSequence, Error> {
        Result { try ExerciseSequencer.sequence(for: spec) }
    }

    private var playerID: String { "\(preset.trackReference)-\(ExerciseRenderer.cacheKey(for: spec))" }
    private var isPlaying: Bool { player.isCurrent(playerID) && player.isPlaying }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $preset.name)
            }

            Section("Pattern") {
                Picker("Pattern", selection: patternChoice) {
                    ForEach(ExercisePattern.builtIn, id: \.self) { pattern in
                        Text(pattern.displayName).tag(PatternChoice.builtIn(pattern))
                    }
                    Text("Custom sequence").tag(PatternChoice.custom)
                }
                if case .custom = spec.pattern {
                    TextField("Scale degrees, e.g. 1 3 5 8 5 3 1", text: $customDegrees)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .onChange(of: customDegrees) { _, text in spec.pattern = .custom(text) }
                    if case .failure(let error) = Result(catching: { try ExercisePattern.parseDegrees(customDegrees) }) {
                        Text(error.localizedDescription)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                NotePicker(title: "Start on", note: $spec.startNote)
                NotePicker(title: "Lowest note", note: $spec.floor)
                NotePicker(title: "Highest note", note: $spec.ceiling)
                HStack {
                    Button("My range") {
                        spec.floor = .singerFloor
                        spec.ceiling = .singerCeiling
                        spec.startNote = .singerFloor
                    }
                    Spacer()
                    Button("Passaggio focus") {
                        let focus = ExerciseSpec.passaggioFocus(spec.pattern)
                        spec.floor = focus.floor
                        spec.ceiling = focus.ceiling
                        spec.startNote = focus.startNote
                    }
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Range")
            } footer: {
                Text("No sung note goes outside the lowest–highest range. Your range is D#2–G#4; the passaggio preset keeps each repetition’s top note in C4–F#4.")
            }

            Section("Movement") {
                Picker("Direction", selection: $spec.direction) {
                    ForEach(ExerciseSpec.Direction.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Stepper(value: $spec.step, in: ExerciseSpec.stepRange) {
                    LabeledContent("Step each repetition", value: spec.step == 1 ? "1 semitone" : "\(spec.step) semitones")
                }
                Stepper(value: $spec.tempo, in: ExerciseSpec.tempoRange, step: 4) {
                    LabeledContent("Tempo", value: "\(Int(spec.tempo)) BPM")
                }
            }

            Section("Piano") {
                Toggle("Play root chord before each repetition", isOn: $spec.playsCueChord)
                Stepper(value: $spec.pianoOctaveShift, in: -1...1) {
                    LabeledContent("Piano octave", value: spec.pianoOctaveShift == 0 ? "As sung" : (spec.pianoOctaveShift > 0 ? "One up" : "One down"))
                }
            }

            Section {
                switch sequence {
                case .success(let sequence):
                    LabeledContent("Repetitions", value: "\(sequence.repetitions.count)")
                    LabeledContent("Length") {
                        Text(Duration.seconds(sequence.duration), format: .time(pattern: .minuteSecond))
                    }
                    if let first = sequence.repetitions.first, let top = sequence.repetitions.map(\.root).max() {
                        LabeledContent("Roots", value: "\(first.root.name) → \(top.name)")
                    }
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                previewControls
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Share as M4A") { Task { await export(m4a: true) } }
                    Button("Share as WAV") { Task { await export(m4a: false) } }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled((try? sequence.get()) == nil)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            spec = preset.spec
            if case .custom(let text) = spec.pattern { customDegrees = text }
        }
        .onChange(of: spec) { _, newValue in
            preset.spec = newValue
            try? context.save()
            // A playing preview keeps playing the old render; restart it with the new one.
            if player.itemID?.hasPrefix(preset.trackReference) == true, player.isPlaying {
                Task { await togglePreview(forceRestart: true) }
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private var previewControls: some View {
        HStack {
            Spacer()
            Button {
                Task { await togglePreview() }
            } label: {
                ZStack {
                    Circle().fill(Color.accentColor)
                    if isRendering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .disabled((try? sequence.get()) == nil)
            .accessibilityLabel(isPlaying ? "Stop preview" : "Play on a loop")
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func togglePreview(forceRestart: Bool = false) async {
        if isPlaying && !forceRestart {
            player.pause()
            return
        }
        isRendering = true
        defer { isRendering = false }
        do {
            let url = try await ExerciseRenderer.renderedFile(for: spec)
            player.load(url, id: playerID, loopWholeFile: true)
            player.seek(to: 0)
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func export(m4a: Bool) async {
        isRendering = true
        defer { isRendering = false }
        do {
            let url = m4a
                ? try await ExerciseRenderer.exportM4A(for: spec, name: preset.name)
                : try await ExerciseRenderer.exportWAV(for: spec, name: preset.name)
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Picks a note from C1 to C6 by name.
struct NotePicker: View {
    let title: String
    @Binding var note: Note

    private static let choices = (24...84).map(Note.init(midi:))

    var body: some View {
        Picker(title, selection: $note) {
            ForEach(Self.choices, id: \.self) { note in
                Text(note.name).tag(note)
            }
        }
        .accessibilityValue(note.accessibilityName)
    }
}

/// The system share sheet, for handing an exported file to AirDrop, Files, Messages…
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
