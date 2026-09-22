import PassaggioCore
import SwiftUI

/// Loads a generated preset or lesson clip into the shared player, always looping.
@MainActor
enum TrackPlayback {
    static func id(for track: PracticeTrack) -> String {
        switch track {
        case .preset(let preset): "\(preset.trackReference)-\(ExerciseRenderer.cacheKey(for: preset.spec))"
        case .clip(let clip): clip.trackReference
        }
    }

    static func load(_ track: PracticeTrack, into player: PlayerController) async throws {
        switch track {
        case .preset(let preset):
            let url = try await ExerciseRenderer.renderedFile(for: preset.spec)
            player.load(url, id: id(for: track), loopWholeFile: true)
        case .clip(let clip):
            guard let lesson = clip.lesson else { return }
            player.load(lesson.fileURL, id: id(for: track), loop: clip.start...clip.end)
            player.seek(to: clip.start)
        }
        if let message = player.errorMessage {
            throw PlaybackError(message: message)
        }
    }

    nonisolated struct PlaybackError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
}

/// A practice track's name with a large looping play button.
struct TrackPlayerCard: View {
    let track: PracticeTrack
    @Environment(PlayerController.self) private var player
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isPlaying: Bool { player.isCurrent(TrackPlayback.id(for: track)) && player.isPlaying }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                Task { await toggle() }
            } label: {
                ZStack {
                    Circle().fill(Color.accentColor)
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause \(track.name)" : "Play \(track.name) on a loop")

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.headline)
                Label(detail, systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .errorAlert(message: $errorMessage)
    }

    private var detail: String {
        switch track {
        case .preset(let preset):
            let spec = preset.spec
            return "\(spec.pattern.displayName) · \(spec.floor.name)–\(spec.ceiling.name) · \(Int(spec.tempo)) BPM"
        case .clip(let clip):
            return "Lesson clip · \(Int(clip.duration.rounded())) s"
        }
    }

    private func toggle() async {
        if isPlaying {
            player.pause()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await TrackPlayback.load(track, into: player)
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
