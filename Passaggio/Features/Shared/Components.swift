import PassaggioCore
import SwiftUI

extension View {
    /// Presents `message` in an alert while it is non-nil.
    func errorAlert(_ title: String = "Something went wrong", message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}

/// Scrubbable waveform. The one custom control: nothing standard draws audio.
struct WaveformView: View {
    var samples: [Float]
    var duration: TimeInterval
    var currentTime: TimeInterval
    /// Highlighted stretch (a clip or loop range).
    var selection: ClosedRange<TimeInterval>? = nil
    /// Small ticks, e.g. key point timestamps.
    var markers: [TimeInterval] = []
    var onScrub: (TimeInterval) -> Void

    @State private var dragTime: TimeInterval?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let shownTime = dragTime ?? currentTime
            let progressX = duration > 0 ? CGFloat(shownTime / duration) * width : 0

            Canvas { context, size in
                if let selection, duration > 0 {
                    let x0 = CGFloat(selection.lowerBound / duration) * size.width
                    let x1 = CGFloat(selection.upperBound / duration) * size.width
                    context.fill(Path(CGRect(x: x0, y: 0, width: max(x1 - x0, 1), height: size.height)),
                                 with: .color(.accentColor.opacity(0.18)))
                }

                let count = max(samples.count, 1)
                let barWidth = size.width / CGFloat(count)
                var played = Path()
                var unplayed = Path()
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let barHeight = max(1.5, CGFloat(sample) * size.height * 0.9)
                    let rect = CGRect(x: x, y: (size.height - barHeight) / 2, width: max(barWidth * 0.8, 0.5), height: barHeight)
                    if x < progressX { played.addRect(rect) } else { unplayed.addRect(rect) }
                }
                context.fill(unplayed, with: .color(.secondary.opacity(0.45)))
                context.fill(played, with: .color(.accentColor))

                for marker in markers where duration > 0 {
                    let x = CGFloat(marker / duration) * size.width
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: size.height - 6, width: 6, height: 6)),
                                 with: .color(.primary.opacity(0.7)))
                }

                context.fill(Path(CGRect(x: progressX - 1, y: 0, width: 2, height: size.height)), with: .color(.primary))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragTime = time(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        onScrub(time(at: value.location.x, width: width))
                        dragTime = nil
                    }
            )
            .frame(height: height)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(formatTimestamp(currentTime)) of \(formatTimestamp(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrub(min(duration, currentTime + 5))
            case .decrement: onScrub(max(0, currentTime - 5))
            @unknown default: break
            }
        }
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(0, Double(x / width)), 1) * duration
    }
}

/// Large transport controls for use with the phone on a stand: one big play button
/// with skip buttons either side, all at least 64 pt and within thumb reach.
struct TransportControls: View {
    var isPlaying: Bool
    var skipSeconds: TimeInterval = 5
    var onSkip: ((TimeInterval) -> Void)?
    var onPlayPause: () -> Void

    var body: some View {
        HStack(spacing: 36) {
            if let onSkip {
                Button { onSkip(-skipSeconds) } label: {
                    Image(systemName: "gobackward.\(Int(skipSeconds))")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 64, height: 64)
                }
                .accessibilityLabel("Back \(Int(skipSeconds)) seconds")
            }

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Color.accentColor, in: Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            if let onSkip {
                Button { onSkip(skipSeconds) } label: {
                    Image(systemName: "goforward.\(Int(skipSeconds))")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 64, height: 64)
                }
                .accessibilityLabel("Forward \(Int(skipSeconds)) seconds")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
    }
}

struct TimeRow: View {
    var current: TimeInterval
    var total: TimeInterval

    var body: some View {
        HStack {
            Text(formatTimestamp(current))
            Spacer()
            Text("-" + formatTimestamp(max(0, total - current)))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

extension Theme {
    var label: some View {
        Label(displayName, systemImage: systemImage)
    }
}
