import AVFoundation
import Foundation
import Observation

/// The app's single audio player. Lessons, clips and generated tracks all play
/// through it, so starting one always stops the other.
@Observable
final class PlayerController: NSObject, AVAudioPlayerDelegate {
    /// Identifies what is loaded, e.g. a lesson ID or "preset:<id>".
    private(set) var itemID: String?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// While set, playback wraps from the end of the range back to its start.
    private(set) var loopRange: ClosedRange<TimeInterval>?
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Activating the audio session can block, so playback starts after it finishes.
    @ObservationIgnored private var startTask: Task<Void, Never>?

    /// Loads `url` unless it's already the current item.
    func load(_ url: URL, id: String, loop: ClosedRange<TimeInterval>? = nil, loopWholeFile: Bool = false) {
        if itemID == id, player != nil {
            setLoop(loop)
            player?.numberOfLoops = loopWholeFile ? -1 : 0
            return
        }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = false
            player.numberOfLoops = loopWholeFile ? -1 : 0
            player.prepareToPlay()
            self.player = player
            itemID = id
            duration = player.duration
            loopRange = loop
            currentTime = loop?.lowerBound ?? 0
            player.currentTime = currentTime
            errorMessage = nil
        } catch {
            itemID = nil
            errorMessage = "Couldn't open the audio: \(error.localizedDescription)"
        }
    }

    func isCurrent(_ id: String) -> Bool { itemID == id }

    func play() {
        guard player != nil, !isPlaying else { return }
        isPlaying = true
        startTask?.cancel()
        startTask = Task {
            let failure = await Self.activateSession()
            // Paused, stopped or replaced while the session was activating.
            guard !Task.isCancelled, let player else { return }
            if let failure { errorMessage = failure }
            if let loopRange, !loopRange.contains(player.currentTime) {
                player.currentTime = loopRange.lowerBound
            }
            player.play()
            startTicker()
        }
    }

    func pause() {
        startTask?.cancel()
        player?.pause()
        isPlaying = false
        syncTime()
        ticker?.cancel()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func stop() {
        startTask?.cancel()
        ticker?.cancel()
        player?.stop()
        player = nil
        itemID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        loopRange = nil
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setLoop(_ range: ClosedRange<TimeInterval>?) {
        loopRange = range
        if let range, !range.contains(currentTime) {
            seek(to: range.lowerBound)
        }
    }

    // MARK: - Private

    /// Returns an error message, or nil on success. Uses the async activation API so the
    /// main thread isn't blocked (`setActive` logs a warning when it is).
    private static func activateSession() async -> String? {
        // .playback keeps audio going with the silent switch on and the screen locked,
        // which matters with the phone on a music stand.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try await session.activate(options: [])
            return nil
        } catch {
            return "Audio session error: \(error.localizedDescription)"
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func tick() {
        guard let player else { return }
        if let loopRange, player.currentTime >= loopRange.upperBound {
            player.currentTime = loopRange.lowerBound
        }
        syncTime()
    }

    private func syncTime() {
        currentTime = player?.currentTime ?? 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // A loop range that runs to the very end of the file: restart the range.
            if let range = self.loopRange {
                self.player?.currentTime = range.lowerBound
                self.player?.play()
                return
            }
            self.isPlaying = false
            self.ticker?.cancel()
            self.currentTime = 0
            self.player?.currentTime = 0
        }
    }
}
