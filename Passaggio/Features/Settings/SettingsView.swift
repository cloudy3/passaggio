import PassaggioCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("How to Use Passaggio", systemImage: "questionmark.circle")
                    }
                } footer: {
                    Text("Step-by-step help for every feature.")
                }

                APIKeySection(account: .openAI, title: "OpenAI API Key",
                              footer: "Used for transcription (gpt-4o-transcribe-diarize) and, if selected below, key points and routines. Stored in the Keychain on this iPhone only.")
                APIKeySection(account: .anthropic, title: "Anthropic API Key",
                              footer: "Only needed if you choose Anthropic below.")

                Section {
                    Picker("Provider", selection: $settings.provider) {
                        ForEach(LLMProviderKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    ModelField(kind: .openAI, text: $settings.openAIModel)
                    ModelField(kind: .anthropic, text: $settings.anthropicModel)
                } header: {
                    Text("Key Points and Routines")
                } footer: {
                    Text("Only your teacher’s transcribed speech is sent to this model. Transcription always uses OpenAI.")
                }

                SpeakerReferencesSection()

                BackupSection()

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Piano sound")
                        Text("“Upright Piano KW” by the FreePats project (freepats.zenvoid.org), dedicated to the public domain under CC0 1.0.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct ModelField: View {
    let kind: LLMProviderKind
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(kind.displayName) model")
                .font(.subheadline)
            HStack {
                TextField(kind.defaultModel, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                if text != kind.defaultModel {
                    Button("Default") { text = kind.defaultModel }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Reset \(kind.displayName) model to \(kind.defaultModel)")
                }
            }
        }
    }
}

private struct APIKeySection: View {
    let account: KeychainStore.Account
    let title: String
    let footer: String

    @State private var draft = ""
    @State private var isStored = false
    @State private var errorMessage: String?
    private let keychain = KeychainStore()

    var body: some View {
        Section {
            if isStored {
                LabeledContent("Status") {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                }
                Button("Remove Key", role: .destructive) {
                    do {
                        try keychain.delete(account)
                        isStored = false
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } else {
                SecureField("Paste key", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                Button("Save to Keychain") {
                    do {
                        try keychain.save(draft, for: account)
                        draft = ""
                        isStored = keychain.read(account) != nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
        .onAppear { isStored = keychain.read(account) != nil }
        .errorAlert(message: $errorMessage)
    }
}

private struct SpeakerReferencesSection: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player
    @Query(sort: \SpeakerReference.createdAt) private var references: [SpeakerReference]

    var body: some View {
        Section {
            ForEach([SpeakerRole.teacher, .student], id: \.self) { role in
                if let reference = references.last(where: { $0.role == role }) {
                    HStack {
                        Label(role == .teacher ? "Teacher’s voice" : "My voice", systemImage: "waveform")
                        Spacer()
                        Text(String(format: "%.1f s", reference.duration))
                            .foregroundStyle(.secondary)
                        Button {
                            let id = "reference-\(reference.id)"
                            if player.isCurrent(id), player.isPlaying {
                                player.pause()
                            } else {
                                player.load(reference.fileURL, id: id)
                                player.play()
                            }
                        } label: {
                            Image(systemName: "play.circle.fill").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Play \(role == .teacher ? "teacher’s" : "my") voice sample")
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            FileStore.removeIfPresent(reference.fileURL)
                            context.delete(reference)
                            try? context.save()
                        }
                    }
                } else {
                    LabeledContent(role == .teacher ? "Teacher’s voice" : "My voice", value: "Not set")
                }
            }
        } header: {
            Text("Voice Samples")
        } footer: {
            Text("Open a lesson, then ⋯ › Mark Teacher’s Voice / Mark My Voice to select 2–10 seconds of speech. The samples are sent with every transcription so speakers are labelled consistently.")
        }
    }
}

private struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerController.self) private var player

    @State private var isWorking = false
    @State private var exportURL: URL?
    @State private var showingMover = false
    @State private var showingImporter = false
    @State private var pendingRestore: BackupService.PreparedRestore?
    @State private var showingRestoreConfirmation = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button {
                Task { await makeBackup() }
            } label: {
                Label("Back Up to Files…", systemImage: "externaldrive.badge.plus")
            }
            // Each file panel is attached to its own button: SwiftUI only honours one
            // file importer/exporter/mover per view.
            .fileMover(isPresented: $showingMover, file: exportURL) { result in
                switch result {
                case .success:
                    message = "Backup saved."
                case .failure(let error as CocoaError) where error.code == .userCancelled:
                    break
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
                if let exportURL { FileStore.removeIfPresent(exportURL.deletingLastPathComponent()) }
                exportURL = nil
            }
            Button {
                showingImporter = true
            } label: {
                Label("Restore from Backup…", systemImage: "arrow.counterclockwise")
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.passaggioBackup, .data]) { result in
                switch result {
                case .success(let url): Task { await prepare(url) }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            if isWorking {
                ProgressView()
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("One file with all recordings, transcripts, notes, routines and tracks. Keep it in Files (iCloud Drive or On My iPhone) before the app expires or you reinstall. API keys aren’t included.")
        }
        .disabled(isWorking)
        .confirmationDialog(
            "Replace everything with this backup?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace All Data", role: .destructive) { restore() }
            Button("Cancel", role: .cancel) { cancelRestore() }
        } message: {
            if let payload = pendingRestore?.payload {
                Text("Backup from \(payload.createdAt.formatted(date: .abbreviated, time: .shortened)): \(payload.lessons.count) lessons, \(payload.routines.count) routines. Current data on this phone will be replaced.")
            }
        }
        .onChange(of: PendingRestore.shared.url) { _, url in
            guard let url else { return }
            PendingRestore.shared.url = nil
            Task { await prepare(url) }
        }
        .onAppear {
            if let url = PendingRestore.shared.url {
                PendingRestore.shared.url = nil
                Task { await prepare(url) }
            }
        }
        .alert("Done", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
        .errorAlert(message: $errorMessage)
    }

    private func makeBackup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try context.save()
            exportURL = try await BackupService.makeBackup(context: context)
            showingMover = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepare(_ url: URL) async {
        isWorking = true
        defer { isWorking = false }
        do {
            cancelRestore() // discard any earlier unpacked backup
            pendingRestore = try await BackupService.prepareRestore(from: url)
            showingRestoreConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() {
        guard let prepared = pendingRestore else { return }
        pendingRestore = nil
        player.stop()
        do {
            try BackupService.restore(prepared, context: context)
            message = "Restored \(prepared.payload.lessons.count) lessons."
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func cancelRestore() {
        if let prepared = pendingRestore {
            FileStore.removeIfPresent(prepared.directory)
        }
        pendingRestore = nil
    }
}
