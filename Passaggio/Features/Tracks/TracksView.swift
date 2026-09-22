import PassaggioCore
import SwiftData
import SwiftUI

struct TracksView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: [SortDescriptor(\GeneratorPreset.sortOrder), SortDescriptor(\GeneratorPreset.createdAt)])
    private var presets: [GeneratorPreset]
    @Query(sort: \PracticeClip.createdAt, order: .reverse) private var clips: [PracticeClip]

    @State private var path = NavigationPath()
    @State private var renaming: PracticeClip?
    @State private var newName = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(presets) { preset in
                        NavigationLink(value: preset) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                let spec = preset.spec
                                Text("\(spec.floor.name)–\(spec.ceiling.name) · \(Int(spec.tempo)) BPM · \(spec.direction.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(presets[index]) }
                        try? context.save()
                    }
                    Button {
                        let preset = GeneratorPreset(name: "New Exercise", spec: ExerciseSpec())
                        context.insert(preset)
                        try? context.save()
                        path.append(preset)
                    } label: {
                        Label("New Exercise", systemImage: "plus")
                    }
                } header: {
                    Text("Piano Exercises")
                } footer: {
                    Text("Generated on the phone. Passaggio presets keep every repetition’s top note in C4–F#4.")
                }

                Section {
                    if clips.isEmpty {
                        Text("Save a stretch of a lesson (usually your teacher playing an exercise) from a lesson’s ⋯ menu.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(clips) { clip in
                        TrackPlayerCard(track: .clip(clip))
                            .contextMenu {
                                Button("Rename") {
                                    newName = clip.name
                                    renaming = clip
                                }
                                if let lesson = clip.lesson {
                                    Button("Open Lesson") {
                                        path.append(LessonMoment(lessonID: lesson.id, time: clip.start))
                                    }
                                }
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if player.isCurrent(clips[index].trackReference) { player.stop() }
                            context.delete(clips[index])
                        }
                        try? context.save()
                    }
                } header: {
                    Text("Lesson Clips")
                }
            }
            .navigationTitle("Tracks")
            .navigationDestination(for: GeneratorPreset.self) { preset in
                GeneratorView(preset: preset)
            }
            .navigationDestination(for: LessonMoment.self) { moment in
                LessonDestination(moment: moment)
            }
            .alert("Rename Clip", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { renaming?.name = trimmed }
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
