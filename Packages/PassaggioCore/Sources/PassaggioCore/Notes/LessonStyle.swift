import Foundation

/// What kind of lesson a recording is. It decides which themes and prompt wording the
/// analysis uses. Singing is the default, and its prompts must never change because
/// screaming exists (`SingingPromptGoldenTests`).
public enum LessonStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case singing
    case screaming

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singing: "Singing"
        case .screaming: "Screaming"
        }
    }
}
