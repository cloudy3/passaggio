import Foundation

/// A vocal exercise shape, expressed as semitone offsets from the root of each repetition.
public enum ExercisePattern: Hashable, Codable, Sendable {
    case fiveNoteScale
    case majorScale
    case arpeggio          // 1-3-5-8-5-3-1
    case octaveSlide
    /// Scale degrees in major, e.g. "1 3 5 3 1". Accidentals prefix the degree: "b3", "#4".
    case custom(String)

    public static let builtIn: [ExercisePattern] = [.fiveNoteScale, .majorScale, .arpeggio, .octaveSlide]

    public var displayName: String {
        switch self {
        case .fiveNoteScale: "5-note scale"
        case .majorScale: "Major scale"
        case .arpeggio: "Arpeggio 1-3-5-8-5-3-1"
        case .octaveSlide: "Octave slide"
        case .custom: "Custom sequence"
        }
    }

    /// Semitone offsets from the root, in singing order.
    public var offsets: [Int] {
        switch self {
        case .fiveNoteScale: [0, 2, 4, 5, 7, 5, 4, 2, 0]
        case .majorScale: [0, 2, 4, 5, 7, 9, 11, 12, 11, 9, 7, 5, 4, 2, 0]
        case .arpeggio: [0, 4, 7, 12, 7, 4, 0]
        case .octaveSlide: [0, 12, 0]
        case .custom(let text): (try? ExercisePattern.parseDegrees(text)) ?? []
        }
    }

    /// Length of each note in beats. Scales end on a held note; the slide is sustained
    /// so the singer has time to glide between the piano's anchor notes.
    public var beats: [Double] {
        let count = offsets.count
        guard count > 0 else { return [] }
        switch self {
        case .octaveSlide:
            return [2, 2, 2]
        default:
            return Array(repeating: 1, count: count - 1) + [2]
        }
    }

    public enum ParseError: Error, Equatable, LocalizedError {
        case empty
        case invalidToken(String)

        public var errorDescription: String? {
            switch self {
            case .empty: "Enter at least one scale degree, for example 1 3 5 3 1."
            case .invalidToken(let token): "“\(token)” isn’t a scale degree. Use numbers 1–15, optionally with b or #."
            }
        }
    }

    /// Converts major-scale degrees ("1 2 3 b3 #4 8 9") to semitone offsets.
    /// Degrees above 7 continue into the next octave, so 8 is the octave and 9 the ninth.
    public static func parseDegrees(_ text: String) throws -> [Int] {
        let separators = CharacterSet(charactersIn: " ,-–").union(.whitespacesAndNewlines)
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { throw ParseError.empty }

        let majorSteps = [0, 2, 4, 5, 7, 9, 11]
        return try tokens.map { token in
            var body = Substring(token)
            var accidental = 0
            while let c = body.first, c == "b" || c == "#" || c == "♭" || c == "♯" {
                accidental += (c == "#" || c == "♯") ? 1 : -1
                body = body.dropFirst()
            }
            guard let degree = Int(body), (1...15).contains(degree) else {
                throw ParseError.invalidToken(token)
            }
            let zeroBased = degree - 1
            return majorSteps[zeroBased % 7] + 12 * (zeroBased / 7) + accidental
        }
    }
}
