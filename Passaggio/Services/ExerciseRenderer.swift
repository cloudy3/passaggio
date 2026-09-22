import AVFoundation
import CryptoKit
import Foundation
import PassaggioCore

/// Renders generated exercises to audio files with a piano SoundFont.
///
/// Why render to a file instead of playing through AVAudioSequencer live: one code
/// path then serves preview, looping and export (the same file is played on a loop
/// and shared), timing is sample-accurate, and playback uses the same player as
/// lesson recordings. Rendering runs much faster than real time, so a typical
/// two-minute exercise is ready in well under a second.
nonisolated enum ExerciseRenderer {
    enum RenderError: Error, LocalizedError {
        case missingSoundFont
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .missingSoundFont: "The piano sound is missing from the app bundle."
            case .renderFailed: "The exercise couldn't be rendered."
            }
        }
    }

    static let sampleRate: Double = 44_100
    /// Lets the last notes ring out before the file ends (and before a loop restarts).
    static let tail: TimeInterval = 1.2

    static var soundFontURL: URL? {
        Bundle.main.url(forResource: "UprightPianoKW", withExtension: "sf2")
    }

    /// Renders (or reuses a cached render of) `spec` and returns the WAV file URL.
    @concurrent
    static func renderedFile(for spec: ExerciseSpec) async throws -> URL {
        let sequence = try ExerciseSequencer.sequence(for: spec)
        let key = cacheKey(for: spec)
        let url = FileStore.renders.appendingPathComponent("\(key).wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        try FileManager.default.createDirectory(at: FileStore.renders, withIntermediateDirectories: true)
        // AVAudioFile picks the container from the extension, so the temp name keeps .wav.
        let partial = FileStore.renders.appendingPathComponent("\(key).partial.wav")
        try render(sequence, to: partial)
        FileStore.removeIfPresent(url)
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }

    /// Converts a render to .m4a for sharing.
    @concurrent
    static func exportM4A(for spec: ExerciseSpec, name: String) async throws -> URL {
        let wav = try await renderedFile(for: spec)
        let directory = try FileStore.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("\(sanitized(name)).m4a")
        try await AudioExport.exportM4A(from: wav, to: url)
        return url
    }

    /// Copies a render to a nicely named .wav for sharing.
    @concurrent
    static func exportWAV(for spec: ExerciseSpec, name: String) async throws -> URL {
        let wav = try await renderedFile(for: spec)
        let directory = try FileStore.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("\(sanitized(name)).wav")
        try FileManager.default.copyItem(at: wav, to: url)
        return url
    }

    static func cacheKey(for spec: ExerciseSpec) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(spec)) ?? Data()
        // Includes a render version so changing the synthesis invalidates old files.
        let digest = SHA256.hash(data: data + Data("render-v1".utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func sanitized(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return cleaned.isEmpty ? "Exercise" : cleaned
    }

    private struct MIDIAction {
        var frame: Int
        var isOn: Bool
        var note: UInt8
        var velocity: UInt8
    }

    /// Offline render: drive the sampler directly and pull audio from the engine block
    /// by block, stopping each block at the next note event so events land on the
    /// exact sample rather than on a buffer boundary.
    static func render(_ sequence: ExerciseSequence, to url: URL) throws {
        guard let soundFontURL else { throw RenderError.missingSoundFont }

        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw RenderError.renderFailed
        }
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        let maxFrames: AVAudioFrameCount = 1_024
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
        try sampler.loadSoundBankInstrument(
            at: soundFontURL,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
        try engine.start()
        defer { engine.stop() }

        var actions: [MIDIAction] = []
        for event in sequence.events {
            let on = Int((event.start * sampleRate).rounded())
            let off = Int((event.end * sampleRate).rounded())
            for note in event.notes where (0...127).contains(note) {
                actions.append(MIDIAction(frame: on, isOn: true, note: UInt8(note), velocity: event.velocity))
                actions.append(MIDIAction(frame: off, isOn: false, note: UInt8(note), velocity: 0))
            }
        }
        // Note-offs before note-ons at the same frame, so a repeated pitch re-strikes.
        actions.sort { $0.frame != $1.frame ? $0.frame < $1.frame : (!$0.isOn && $1.isOn) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames) else {
            throw RenderError.renderFailed
        }

        let totalFrames = Int(((sequence.duration + tail) * sampleRate).rounded())
        var frame = 0
        var next = 0
        var stalls = 0
        while frame < totalFrames {
            while next < actions.count, actions[next].frame <= frame {
                let action = actions[next]
                if action.isOn {
                    sampler.startNote(action.note, withVelocity: action.velocity, onChannel: 0)
                } else {
                    sampler.stopNote(action.note, onChannel: 0)
                }
                next += 1
            }
            let untilNextEvent = next < actions.count ? actions[next].frame - frame : Int.max
            let count = max(1, min(Int(maxFrames), totalFrames - frame, untilNextEvent))

            switch try engine.renderOffline(AVAudioFrameCount(count), to: buffer) {
            case .success:
                try file.write(from: buffer)
                frame += Int(buffer.frameLength)
                stalls = 0
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                // Transient in principle; never expected offline. Bail rather than spin.
                stalls += 1
                if stalls > 100 { throw RenderError.renderFailed }
            case .error:
                throw RenderError.renderFailed
            @unknown default:
                throw RenderError.renderFailed
            }
        }
    }
}
