import Foundation

/// One slice of a lesson sent to the transcription API.
public struct AudioChunk: Hashable, Sendable {
    public var index: Int
    /// The stretch of the lesson this chunk is responsible for. Nominal ranges tile the
    /// lesson exactly, with no gaps or overlap.
    public var nominalStart: TimeInterval
    public var nominalEnd: TimeInterval
    /// The audio actually exported, which extends into neighbours by the overlap so
    /// words straddling a cut are heard whole by at least one request.
    public var audioStart: TimeInterval
    public var audioEnd: TimeInterval

    public var audioDuration: TimeInterval { audioEnd - audioStart }
}

/// Decides where to cut a lesson.
///
/// Limits (OpenAI docs, checked 2026-09): uploads are capped at 25 MB and about 1400 s,
/// and gpt-4o-transcribe-diarize returns at most 2,000 output tokens per request. The
/// token cap is the binding one: dense speech runs ~200 tokens a minute, so a
/// 20-minute chunk could be silently truncated. We target ~5 minutes per chunk and
/// prefer to cut in silence, where no word is being spoken.
public struct ChunkPlanner: Sendable {
    public struct Configuration: Hashable, Sendable {
        /// Preferred chunk length.
        public var targetDuration: TimeInterval = 300
        /// How far before the target we look for a quiet cut point.
        public var searchWindow: TimeInterval = 45
        /// Audio shared with each neighbour.
        public var overlap: TimeInterval = 1.5
        /// A trailing remainder shorter than this is folded into the previous chunk.
        public var minimumTail: TimeInterval = 20

        public init() {}

        public init(targetDuration: TimeInterval, searchWindow: TimeInterval, overlap: TimeInterval, minimumTail: TimeInterval) {
            self.targetDuration = targetDuration
            self.searchWindow = searchWindow
            self.overlap = overlap
            self.minimumTail = minimumTail
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// - Parameters:
    ///   - duration: Lesson length in seconds.
    ///   - envelope: Optional loudness envelope (e.g. RMS per hop). Without it, cuts land
    ///     exactly on the target length.
    ///   - hop: Seconds per envelope value.
    public func plan(duration: TimeInterval, envelope: [Float] = [], hop: TimeInterval = 0.5) -> [AudioChunk] {
        guard duration > 0 else { return [] }
        let config = configuration

        var cuts: [TimeInterval] = []
        var cursor: TimeInterval = 0
        while duration - cursor > config.targetDuration + config.minimumTail {
            let target = cursor + config.targetDuration
            let earliest = max(cursor + config.targetDuration - config.searchWindow, cursor + 1)
            let cut = quietestPoint(in: earliest...target, envelope: envelope, hop: hop) ?? target
            cuts.append(cut)
            cursor = cut
        }

        let bounds = [0] + cuts + [duration]
        return zip(bounds, bounds.dropFirst()).enumerated().map { index, pair in
            let (start, end) = pair
            return AudioChunk(
                index: index,
                nominalStart: start,
                nominalEnd: end,
                audioStart: max(0, start - config.overlap),
                audioEnd: min(duration, end + config.overlap)
            )
        }
    }

    /// Splits one chunk in two at its quietest middle point. Used when a response looks
    /// truncated: the halves are re-sent separately.
    public func split(_ chunk: AudioChunk, duration: TimeInterval, envelope: [Float] = [], hop: TimeInterval = 0.5) -> [AudioChunk] {
        let length = chunk.nominalEnd - chunk.nominalStart
        let middle = chunk.nominalStart + length / 2
        let window = (middle - length / 4)...(middle + length / 4)
        let cut = quietestPoint(in: window, envelope: envelope, hop: hop) ?? middle
        let overlap = configuration.overlap
        return [
            AudioChunk(index: chunk.index, nominalStart: chunk.nominalStart, nominalEnd: cut,
                       audioStart: max(0, chunk.nominalStart - overlap), audioEnd: min(duration, cut + overlap)),
            AudioChunk(index: chunk.index, nominalStart: cut, nominalEnd: chunk.nominalEnd,
                       audioStart: max(0, cut - overlap), audioEnd: min(duration, chunk.nominalEnd + overlap)),
        ]
    }

    /// Centre time of the quietest one-second stretch inside `range`, or nil without an envelope.
    func quietestPoint(in range: ClosedRange<TimeInterval>, envelope: [Float], hop: TimeInterval) -> TimeInterval? {
        guard !envelope.isEmpty, hop > 0 else { return nil }
        let first = max(0, Int((range.lowerBound / hop).rounded(.up)))
        let last = min(envelope.count - 1, Int((range.upperBound / hop).rounded(.down)))
        guard first <= last else { return nil }

        // Smooth over ~1 s so a single quiet hop between syllables doesn't win.
        let radius = max(0, Int((0.5 / hop).rounded()))
        var best: (index: Int, energy: Float)?
        for i in first...last {
            let lo = max(0, i - radius), hi = min(envelope.count - 1, i + radius)
            let energy = envelope[lo...hi].reduce(0, +) / Float(hi - lo + 1)
            // `<` keeps the earliest of equal minima, so results are deterministic.
            if best == nil || energy < best!.energy {
                best = (i, energy)
            }
        }
        return best.map { Double($0.index) * hop }
    }
}
