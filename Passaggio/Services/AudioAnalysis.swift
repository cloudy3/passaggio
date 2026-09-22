import Accelerate
import AVFoundation
import Foundation

/// Reads a recording once and derives what the UI and chunk planner need.
nonisolated enum AudioAnalysis {
    struct Result: Sendable {
        /// Peak amplitude per bucket, normalised to 0...1, for drawing.
        var waveform: [Float]
        /// RMS per `hop` seconds, for finding quiet cut points.
        var envelope: [Float]
        var hop: TimeInterval
        var duration: TimeInterval
    }

    static let waveformBuckets = 1_200
    static let envelopeHop: TimeInterval = 0.5

    /// Streams the file in blocks, so an hour-long lesson never sits in memory.
    @concurrent
    static func analyze(url: URL) async throws -> Result {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = max(Int(file.length), 1)
        let hopFrames = max(Int(sampleRate * envelopeHop), 1)
        let bucketFrames = max(totalFrames / waveformBuckets, 1)

        var waveform = [Float](repeating: 0, count: (totalFrames + bucketFrames - 1) / bucketFrames)
        var envelope: [Float] = []
        envelope.reserveCapacity(totalFrames / hopFrames + 1)

        let blockSize: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockSize) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var frameIndex = 0
        var hopSum: Float = 0
        var hopCount = 0
        let channels = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: Int(blockSize))

        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: blockSize)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }

            // Mix down to mono (Voice Memos is mono, but imported files might not be).
            mono.withUnsafeMutableBufferPointer { out in
                out.baseAddress!.update(from: data[0], count: frames)
                for c in 1..<max(channels, 1) {
                    vDSP_vadd(out.baseAddress!, 1, data[c], 1, out.baseAddress!, 1, vDSP_Length(frames))
                }
                if channels > 1 {
                    var scale = 1 / Float(channels)
                    vDSP_vsmul(out.baseAddress!, 1, &scale, out.baseAddress!, 1, vDSP_Length(frames))
                }
            }

            // Walk the block in runs that never cross a bucket or hop boundary, so each
            // run is one vectorised peak and one sum of squares. (A per-sample Swift
            // loop takes tens of seconds on an hour of 48 kHz audio in debug builds.)
            var offset = 0
            mono.withUnsafeBufferPointer { samples in
                while offset < frames {
                    let toBucketEnd = bucketFrames - frameIndex % bucketFrames
                    let toHopEnd = hopFrames - hopCount
                    let run = min(frames - offset, toBucketEnd, toHopEnd)
                    let pointer = samples.baseAddress! + offset

                    var peak: Float = 0
                    vDSP_maxmgv(pointer, 1, &peak, vDSP_Length(run))
                    let bucket = frameIndex / bucketFrames
                    if bucket < waveform.count, peak > waveform[bucket] {
                        waveform[bucket] = peak
                    }

                    var squares: Float = 0
                    vDSP_svesq(pointer, 1, &squares, vDSP_Length(run))
                    hopSum += squares
                    hopCount += run
                    if hopCount == hopFrames {
                        envelope.append((hopSum / Float(hopCount)).squareRoot())
                        hopSum = 0
                        hopCount = 0
                    }

                    offset += run
                    frameIndex += run
                }
            }
        }
        if hopCount > 0 {
            envelope.append((hopSum / Float(hopCount)).squareRoot())
        }

        let peak = waveform.max() ?? 0
        if peak > 0 {
            waveform = waveform.map { $0 / peak }
        }
        return Result(
            waveform: waveform,
            envelope: envelope,
            hop: envelopeHop,
            duration: Double(file.length) / sampleRate
        )
    }
}

/// Cuts and converts audio.
nonisolated enum AudioExport {
    enum ExportError: Error, LocalizedError {
        case cannotCreateSession
        case emptyRange

        var errorDescription: String? {
            switch self {
            case .cannotCreateSession: "This audio can't be exported."
            case .emptyRange: "The selected range is empty."
            }
        }
    }

    /// Writes `range` of `source` as AAC in an .m4a container.
    @concurrent
    static func exportM4A(from source: URL, range: ClosedRange<TimeInterval>? = nil, to destination: URL) async throws {
        FileStore.removeIfPresent(destination)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.cannotCreateSession
        }
        if let range {
            guard range.upperBound > range.lowerBound else { throw ExportError.emptyRange }
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: range.upperBound, preferredTimescale: 600)
            )
        }
        try await session.export(to: destination, as: .m4a)
    }

    /// Writes `range` of `source` as 16-bit PCM WAV. Used for speaker references,
    /// which the transcription API takes as `data:audio/wav` URLs.
    @concurrent
    static func exportWAV(from source: URL, range: ClosedRange<TimeInterval>, to destination: URL) async throws {
        FileStore.removeIfPresent(destination)
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let startFrame = AVAudioFramePosition(range.lowerBound * format.sampleRate)
        let endFrame = min(AVAudioFramePosition(range.upperBound * format.sampleRate), input.length)
        guard endFrame > startFrame else { throw ExportError.emptyRange }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = try AVAudioFile(forWriting: destination, settings: settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)

        input.framePosition = startFrame
        let blockSize: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockSize) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        while input.framePosition < endFrame {
            let remaining = AVAudioFrameCount(endFrame - input.framePosition)
            try input.read(into: buffer, frameCount: min(blockSize, remaining))
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
    }
}
